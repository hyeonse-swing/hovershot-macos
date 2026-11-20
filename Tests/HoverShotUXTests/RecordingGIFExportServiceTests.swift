import AVFoundation
import CoreVideo
import ImageIO
import XCTest
@testable import Capture

final class RecordingGIFExportServiceTests: XCTestCase {
    func testShortRecordingKeepsItsPlaybackDuration() {
        let delays = RecordingGIFExportService.recommendedFrameDelays(for: 0.4)

        XCTAssertEqual(delays.count, 5)
        XCTAssertEqual(delays.reduce(0, +), 0.4, accuracy: 0.001)

        let singleFrame = RecordingGIFExportService.recommendedFrameDelays(for: 0.04)
        XCTAssertEqual(singleFrame.count, 1)
        XCTAssertEqual(singleFrame[0], 0.04, accuracy: 0.001)
    }

    func testLongerRecordingsKeepExistingFrameCount() {
        XCTAssertEqual(RecordingGIFExportService.recommendedFrameDelays(for: 1).count, 12)
        XCTAssertEqual(RecordingGIFExportService.recommendedFrameDelays(for: 4).count, 32)
        XCTAssertEqual(RecordingGIFExportService.recommendedFrameDelays(for: 10).count, 60)
        XCTAssertEqual(RecordingGIFExportService.recommendedFrameDelays(for: 20).count, 90)
    }

    @MainActor
    func testShortSyntheticRecordingExportsAtOriginalDuration() async throws {
        try await assertSyntheticGIFDuration(sourceDuration: 0.4, sourceFrameCount: 4, expectedGIFFrames: 5)
    }

    @MainActor
    func testUnevenSyntheticRecordingExportsAtOriginalDuration() async throws {
        try await assertSyntheticGIFDuration(sourceDuration: 0.84, sourceFrameCount: 8, expectedGIFFrames: 10)
    }

    @MainActor
    private func assertSyntheticGIFDuration(
        sourceDuration: Double,
        sourceFrameCount: Int,
        expectedGIFFrames: Int
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("short.mov")
        let destination = directory.appendingPathComponent("short.gif")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for index in 0..<sourceFrameCount {
            for _ in 0..<100 where !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            let attributes = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ] as CFDictionary
            XCTAssertEqual(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, attributes, &buffer), kCVReturnSuccess)
            let frame = try XCTUnwrap(buffer)
            let time = CMTime(value: CMTimeValue(index), timescale: 10)
            XCTAssertTrue(adaptor.append(frame, withPresentationTime: time))
        }
        writer.endSession(atSourceTime: CMTime(seconds: sourceDuration, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)

        try await RecordingGIFExportService().exportGIF(from: source, to: destination)
        let gif = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let count = CGImageSourceGetCount(gif)
        XCTAssertEqual(count, expectedGIFFrames)
        let duration = (0..<count).reduce(0.0) { total, index in
            let properties = CGImageSourceCopyPropertiesAtIndex(gif, index, nil) as? [CFString: Any]
            let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
            return total + delay
        }
        XCTAssertEqual(duration, sourceDuration, accuracy: 0.01)
    }
}
