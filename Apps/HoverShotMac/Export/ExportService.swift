import AppKit
import Foundation
import Library
import UniformTypeIdentifiers

public enum ExportError: LocalizedError {
    case imageUnavailable
    case unsupportedFormat
    case failedToEncodeImage

    public var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "The selected shot image is not available on disk."
        case .unsupportedFormat:
            return "The requested export format is not supported."
        case .failedToEncodeImage:
            return "The shot image could not be converted to the selected file format."
        }
    }
}

public enum ShotExportFormat: String, CaseIterable {
    case png
    case jpeg
    case tiff
    case pdf

    var contentType: UTType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return .jpeg
        case .tiff:
            return .tiff
        case .pdf:
            return .pdf
        }
    }

    var fileExtension: String {
        contentType.preferredFilenameExtension ?? rawValue
    }

    static func from(pathExtension: String) -> ShotExportFormat? {
        switch pathExtension.lowercased() {
        case "png":
            return .png
        case "jpg", "jpeg":
            return .jpeg
        case "tif", "tiff":
            return .tiff
        case "pdf":
            return .pdf
        default:
            return nil
        }
    }
}

@MainActor
public final class ExportService {
    private let shotStore: ShotStore
    private let fileManager: FileManager

    public init(
        shotStore: ShotStore,
        fileManager: FileManager = .default
    ) {
        self.shotStore = shotStore
        self.fileManager = fileManager
    }

    public func copyImage(for shot: Shot) throws {
        guard let image = shotStore.loadRenderedImage(for: shot) else {
            throw ExportError.imageUnavailable
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    public func revealInFinder(for shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shotStore.assetURL(for: shot)])
    }

    public func exportInteractively(for shot: Shot) throws {
        guard let image = shotStore.loadRenderedImage(for: shot) else {
            throw ExportError.imageUnavailable
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = ShotExportFormat.allCases.map(\.contentType)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName(for: shot, format: .png)

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        let format = ShotExportFormat.from(pathExtension: destinationURL.pathExtension) ?? .png
        let data = try encodedData(for: image, format: format)
        try data.write(to: destinationURL, options: .atomic)
    }

    public func dragFileURL(for shot: Shot) throws -> URL {
        guard shot.annotations.isEmpty == false else {
            return shotStore.assetURL(for: shot)
        }

        guard let image = shotStore.loadRenderedImage(for: shot) else {
            throw ExportError.imageUnavailable
        }

        let dragDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("HoverShot-Drag", isDirectory: true)
        try fileManager.createDirectory(at: dragDirectory, withIntermediateDirectories: true)

        let fileName = defaultFileName(for: shot, format: .png)
        let destinationURL = dragDirectory
            .appendingPathComponent(shot.id.uuidString.lowercased())
            .appendingPathExtension(fileName.components(separatedBy: ".").last ?? "png")

        let data = try encodedData(for: image, format: .png)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    private func defaultFileName(for shot: Shot, format: ShotExportFormat) -> String {
        let sanitized = shot.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = sanitized.isEmpty ? "Shot" : sanitized
        return "\(base).\(format.fileExtension)"
    }

    private func encodedData(for image: NSImage, format: ShotExportFormat) throws -> Data {
        switch format {
        case .png:
            return try bitmapData(for: image, fileType: .png, properties: [:])
        case .jpeg:
            return try bitmapData(
                for: image,
                fileType: .jpeg,
                properties: [.compressionFactor: 0.9]
            )
        case .tiff:
            return try bitmapData(for: image, fileType: .tiff, properties: [:])
        case .pdf:
            return try pdfData(for: image)
        }
    }

    private func bitmapData(
        for image: NSImage,
        fileType: NSBitmapImageRep.FileType,
        properties: [NSBitmapImageRep.PropertyKey: Any]
    ) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: fileType, properties: properties)
        else {
            throw ExportError.failedToEncodeImage
        }

        return data
    }

    private func pdfData(for image: NSImage) throws -> Data {
        let frame = NSRect(origin: .zero, size: image.size)
        let pdfView = ExportPDFView(frame: frame, image: image)
        return pdfView.dataWithPDF(inside: frame)
    }
}

private final class ExportPDFView: NSView {
    private let image: NSImage

    init(frame frameRect: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
    }
}
