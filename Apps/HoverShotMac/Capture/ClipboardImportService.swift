import AppKit
import Analysis
import Foundation
import Library

public enum ClipboardImportResult: Sendable {
    case shot(Shot)
    case recording(URL)
}

public enum ClipboardImportError: LocalizedError {
    case unsupportedContent
    case emptyText
    case unreadableImage
    case unsupportedFile(URL)

    public var errorDescription: String? {
        switch self {
        case .unsupportedContent:
            return "The clipboard does not currently contain a supported image, text snippet, or media file."
        case .emptyText:
            return "The clipboard text is empty."
        case .unreadableImage:
            return "The clipboard image could not be read."
        case let .unsupportedFile(url):
            return "The file \(url.lastPathComponent) is not a supported image or video import."
        }
    }
}

@MainActor
public final class ClipboardImportService {
    private let shotStore: ShotStore
    private let recordingStore: RecordingStore
    private let titleFormatter: DateFormatter

    public init(
        shotStore: ShotStore,
        recordingStore: RecordingStore
    ) {
        self.shotStore = shotStore
        self.recordingStore = recordingStore

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        self.titleFormatter = formatter
    }

    public func importFromClipboard() async throws -> ClipboardImportResult {
        let pasteboard = NSPasteboard.general

        if let image = imageFromPasteboard(pasteboard) {
            return .shot(try await importImage(image, title: "Clipboard Image \(titleFormatter.string(from: .now))"))
        }

        if let fileURL = fileURLFromPasteboard(pasteboard) {
            return try await importFile(from: fileURL)
        }

        if let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           text.isEmpty == false {
            let title = textTitle(from: text)
            return .shot(try shotStore.createTextShot(text: text, title: title))
        }

        if pasteboard.string(forType: .string) != nil {
            throw ClipboardImportError.emptyText
        }

        throw ClipboardImportError.unsupportedContent
    }

    private func importFile(from url: URL) async throws -> ClipboardImportResult {
        if isMovieURL(url) {
            let importedURL = try recordingStore.importRecording(from: url)
            return .recording(importedURL)
        }

        if let image = NSImage(contentsOf: url) {
            let title = url.deletingPathExtension().lastPathComponent
            return .shot(try await importImage(image, title: title))
        }

        if let text = try? String(contentsOf: url),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let title = url.deletingPathExtension().lastPathComponent
            return .shot(try shotStore.createTextShot(text: text, title: title))
        }

        throw ClipboardImportError.unsupportedFile(url)
    }

    private func importImage(
        _ image: NSImage,
        title: String
    ) async throws -> Shot {
        let shot = try shotStore.createShot(image: image, title: title)
        let recognizedText = try? await TextRecognitionService().recognizeText(in: image)
        try? shotStore.updateRecognizedText(for: shot.id, to: recognizedText)
        return try shotStore.loadShot(withID: shot.id)
    }

    private func imageFromPasteboard(_ pasteboard: NSPasteboard) -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] {
            return images.first
        }

        return nil
    }

    private func fileURLFromPasteboard(_ pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }

    private func isMovieURL(_ url: URL) -> Bool {
        let supportedExtensions = Set(["mov", "mp4", "m4v"])
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func textTitle(from text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if firstLine.isEmpty {
            return "Clipboard Text \(titleFormatter.string(from: .now))"
        }

        return String(firstLine.prefix(48))
    }
}
