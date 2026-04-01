import AVFoundation
import AppKit
import Foundation

public final class RecordingStore {
    public enum StoreError: LocalizedError {
        case failedToPrepareOutputDirectory

        public var errorDescription: String? {
            switch self {
            case .failedToPrepareOutputDirectory:
                return "The recordings folder could not be prepared."
            }
        }
    }

    private let fileManager: FileManager
    private let baseDirectoryURL: URL
    private let outputDateFormatter: DateFormatter
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager

        let moviesDirectory = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.baseDirectoryURL = baseDirectoryURL
            ?? moviesDirectory.appendingPathComponent("HoverShot", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH-mm-ss"
        self.outputDateFormatter = formatter
    }

    @MainActor
    public func loadRecordings() async throws -> [RecordingItem] {
        try prepareStorage()

        let fileURLs = try fileManager.contentsOfDirectory(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey
            ],
            options: [.skipsHiddenFiles]
        )

        let supportedExtensions = Set(["mp4", "mov"])

        var recordings: [RecordingItem] = []
        for url in fileURLs where supportedExtensions.contains(url.pathExtension.lowercased()) {
            if let item = await makeRecordingItem(from: url) {
                recordings.append(item)
            }
        }

        return recordings.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func nextOutputURL(prefix: String, date: Date = .now) throws -> URL {
        try prepareStorage()

        let timestamp = outputDateFormatter.string(from: date)
        let sanitizedPrefix = prefix
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedPrefix.isEmpty ? "Recording" : sanitizedPrefix

        return baseDirectoryURL
            .appendingPathComponent("\(baseName) \(timestamp)")
            .appendingPathExtension("mp4")
    }

    public func importRecording(from sourceURL: URL, date: Date = .now) throws -> URL {
        try prepareStorage()

        let timestamp = outputDateFormatter.string(from: date)
        let sanitizedPrefix = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedPrefix.isEmpty ? "Imported Recording" : sanitizedPrefix
        let destinationURL = baseDirectoryURL
            .appendingPathComponent("\(baseName) \(timestamp)")
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension)

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return destinationURL
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    public func recordingsDirectoryURL() throws -> URL {
        try prepareStorage()
        return baseDirectoryURL
    }

    public func open(_ recording: RecordingItem) {
        NSWorkspace.shared.open(recording.url)
    }

    public func reveal(_ recording: RecordingItem) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    public func revealDirectory() throws {
        try prepareStorage()
        NSWorkspace.shared.activateFileViewerSelecting([baseDirectoryURL])
    }

    public func delete(_ recording: RecordingItem) throws {
        if fileManager.fileExists(atPath: recording.url.path) {
            try fileManager.removeItem(at: recording.url)
        }

        let metadataURL = metadataURL(for: recording.url)
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
    }

    public func addMarker(
        to recordingURL: URL,
        at timestamp: TimeInterval
    ) throws -> RecordingEditMarker {
        var metadata = try loadMetadata(for: recordingURL)
        let marker = RecordingEditMarker(timestamp: max(0, timestamp))
        metadata.markers.append(marker)
        metadata.markers.sort { $0.timestamp < $1.timestamp }
        try saveMetadata(metadata, for: recordingURL)
        return marker
    }

    public func updateMetadata(
        for recordingURL: URL,
        title: String,
        notes: String?,
        isFavorite: Bool
    ) throws {
        var metadata = try loadMetadata(for: recordingURL)
        let fallbackTitle = recordingURL.deletingPathExtension().lastPathComponent
        metadata.customTitle = normalizedTitle(title, fallback: fallbackTitle)
        metadata.notes = normalizedNotes(notes)
        metadata.isFavorite = isFavorite
        try saveMetadata(metadata, for: recordingURL)
    }

    public func prepareSegmentMetadata(
        for recordingURL: URL,
        sessionName: String,
        segmentIndex: Int
    ) throws {
        var metadata = try loadMetadata(for: recordingURL)
        metadata.sessionName = normalizedNotes(sessionName)
        metadata.segmentIndex = max(segmentIndex, 1)
        try saveMetadata(metadata, for: recordingURL)
    }

    private func prepareStorage() throws {
        do {
            try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw StoreError.failedToPrepareOutputDirectory
        }
    }

    @MainActor
    private func makeRecordingItem(from url: URL) async -> RecordingItem? {
        guard
            let resourceValues = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .creationDateKey,
                .contentModificationDateKey,
                .fileSizeKey
            ]),
            resourceValues.isRegularFile ?? false
        else {
            return nil
        }

        let duration = await durationForRecording(at: url)
        let metadata = (try? loadMetadata(for: url)) ?? RecordingMetadata()
        let markers = metadata.markers.sorted { $0.timestamp < $1.timestamp }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        return RecordingItem(
            url: url,
            title: normalizedTitle(metadata.customTitle, fallback: fallbackTitle),
            sessionName: normalizedNotes(metadata.sessionName),
            segmentIndex: metadata.segmentIndex,
            createdAt: resourceValues.creationDate ?? .distantPast,
            modifiedAt: resourceValues.contentModificationDate ?? resourceValues.creationDate ?? .distantPast,
            fileSize: Int64(resourceValues.fileSize ?? 0),
            duration: duration,
            notes: normalizedNotes(metadata.notes),
            isFavorite: metadata.isFavorite,
            markers: markers
        )
    }

    @MainActor
    private func durationForRecording(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return nil
        }

        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }

        return seconds
    }

    private func metadataURL(for recordingURL: URL) -> URL {
        recordingURL.appendingPathExtension("hovershot.json")
    }

    private func loadMetadata(for recordingURL: URL) throws -> RecordingMetadata {
        let metadataURL = metadataURL(for: recordingURL)
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return RecordingMetadata()
        }

        let data = try Data(contentsOf: metadataURL)
        return try jsonDecoder.decode(RecordingMetadata.self, from: data)
    }

    private func saveMetadata(
        _ metadata: RecordingMetadata,
        for recordingURL: URL
    ) throws {
        let metadataURL = metadataURL(for: recordingURL)
        let data = try jsonEncoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else {
            return nil
        }

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedTitle(_ title: String?, fallback: String) -> String {
        guard let title else {
            return fallback
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
