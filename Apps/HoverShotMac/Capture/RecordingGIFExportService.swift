import AVFoundation
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RecordingGIFExportError: LocalizedError {
    case invalidDuration
    case failedToCreateDestination
    case failedToGenerateFrame
    case failedToFinalize

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            return "The recording duration could not be read for GIF export."
        case .failedToCreateDestination:
            return "The GIF file could not be created."
        case .failedToGenerateFrame:
            return "A frame could not be generated while exporting the GIF."
        case .failedToFinalize:
            return "The GIF file could not be finalized."
        }
    }
}

@MainActor
public final class RecordingGIFExportService {
    public init() {}

    public func exportInteractively(recording: RecordingItem) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName(for: recording)

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return nil
        }

        try await exportGIF(from: recording.url, to: destinationURL)
        return destinationURL
    }

    public func exportGIF(from sourceURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw RecordingGIFExportError.invalidDuration
        }

        let frameCount = recommendedFrameCount(for: durationSeconds)
        let frameDelay = max(durationSeconds / Double(frameCount), 0.08)
        let epsilon = min(frameDelay * 0.5, 0.03)

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 640, height: 640)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw RecordingGIFExportError.failedToCreateDestination
        }

        let fileProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)

        for index in 0..<frameCount {
            let second = min(Double(index) * frameDelay, max(durationSeconds - epsilon, 0))
            let time = CMTime(seconds: second, preferredTimescale: 600)

            let image: CGImage
            do {
                image = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            } catch {
                throw RecordingGIFExportError.failedToGenerateFrame
            }

            let frameProperties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay
                ]
            ] as CFDictionary
            CGImageDestinationAddImage(destination, image, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw RecordingGIFExportError.failedToFinalize
        }
    }

    private func defaultFileName(for recording: RecordingItem) -> String {
        let sanitized = recording.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "Recording" : sanitized
        return "\(base).gif"
    }

    private func recommendedFrameCount(for durationSeconds: TimeInterval) -> Int {
        let targetFPS = durationSeconds <= 4 ? 8.0 : 6.0
        let targetFrames = Int((durationSeconds * targetFPS).rounded(.up))
        return min(max(targetFrames, 12), 90)
    }
}
