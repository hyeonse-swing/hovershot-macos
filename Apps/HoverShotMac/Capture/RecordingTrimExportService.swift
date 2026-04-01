@preconcurrency import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

public enum RecordingTrimExportError: LocalizedError {
    case invalidRange
    case invalidDuration
    case failedToCreateExportSession
    case unsupportedFileType
    case exportFailed(String?)
    case exportCancelled

    public var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "The selected trim range is not valid."
        case .invalidDuration:
            return "The recording duration could not be read for trimming."
        case .failedToCreateExportSession:
            return "The trimmed recording could not be prepared."
        case .unsupportedFileType:
            return "The trimmed recording could not be exported in a supported file format."
        case let .exportFailed(message):
            return message ?? "The trimmed recording could not be exported."
        case .exportCancelled:
            return "The trim export was cancelled."
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(session: AVAssetExportSession) {
        self.session = session
    }
}

@MainActor
public final class RecordingTrimExportService {
    public init() {}

    public func exportInteractively(
        recording: RecordingItem,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName(for: recording)

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return nil
        }

        return try await exportTrim(
            from: recording.url,
            to: destinationURL,
            startTime: startTime,
            endTime: endTime
        )
    }

    public func exportTrim(
        from sourceURL: URL,
        to requestedDestinationURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> URL {
        guard endTime > startTime else {
            throw RecordingTrimExportError.invalidRange
        }

        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw RecordingTrimExportError.invalidDuration
        }

        let clampedStart = max(0, min(startTime, durationSeconds))
        let clampedEnd = max(clampedStart, min(endTime, durationSeconds))
        guard clampedEnd - clampedStart > 0.05 else {
            throw RecordingTrimExportError.invalidRange
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecordingTrimExportError.failedToCreateExportSession
        }

        let fileType = preferredFileType(from: exportSession.supportedFileTypes)
        guard let fileType else {
            throw RecordingTrimExportError.unsupportedFileType
        }

        let destinationURL = normalizedDestinationURL(
            requestedDestinationURL,
            fileType: fileType
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = fileType
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: clampedStart, preferredTimescale: 600),
            end: CMTime(seconds: clampedEnd, preferredTimescale: 600)
        )

        try await export(session: exportSession)
        return destinationURL
    }

    private func export(session: AVAssetExportSession) async throws {
        let sessionBox = ExportSessionBox(session: session)
        try await withCheckedThrowingContinuation { continuation in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: RecordingTrimExportError.exportCancelled)
                case .failed:
                    continuation.resume(
                        throwing: RecordingTrimExportError.exportFailed(
                            sessionBox.session.error?.localizedDescription
                        )
                    )
                default:
                    continuation.resume(
                        throwing: RecordingTrimExportError.exportFailed(
                            sessionBox.session.error?.localizedDescription
                        )
                    )
                }
            }
        }
    }

    private func preferredFileType(from supportedFileTypes: [AVFileType]) -> AVFileType? {
        if supportedFileTypes.contains(.mp4) {
            return .mp4
        }

        if supportedFileTypes.contains(.mov) {
            return .mov
        }

        return supportedFileTypes.first
    }

    private func normalizedDestinationURL(
        _ url: URL,
        fileType: AVFileType
    ) -> URL {
        let fileExtension = switch fileType {
        case .mov: "mov"
        default: "mp4"
        }

        return url
            .deletingPathExtension()
            .appendingPathExtension(fileExtension)
    }

    private func defaultFileName(for recording: RecordingItem) -> String {
        let sanitized = recording.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "Recording" : sanitized
        return "\(base) Trimmed.mp4"
    }
}
