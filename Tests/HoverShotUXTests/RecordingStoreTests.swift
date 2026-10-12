import Foundation
import XCTest
@testable import Capture

final class RecordingStoreTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 0)

    private func fixture() throws -> (RecordingStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (RecordingStore(baseDirectoryURL: directory), directory)
    }

    func testNextOutputURLSkipsExistingRecording() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = try store.nextOutputURL(prefix: "Session", date: fixedDate)
        let original = Data("original".utf8)
        try original.write(to: firstURL)

        let nextURL = try store.nextOutputURL(prefix: "Session", date: fixedDate)
        XCTAssertNotEqual(nextURL, firstURL)
        XCTAssertEqual(nextURL.pathExtension, "mp4")
        XCTAssertEqual(try Data(contentsOf: firstURL), original)
    }

    func testNextOutputURLSkipsSidecarOnlyPath() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstURL = try store.nextOutputURL(prefix: "Session", date: fixedDate)
        let sidecarURL = firstURL.appendingPathExtension("hovershot.json")
        let metadata = Data("existing metadata".utf8)
        try metadata.write(to: sidecarURL)

        let nextURL = try store.nextOutputURL(prefix: "Session", date: fixedDate)
        XCTAssertNotEqual(nextURL, firstURL)
        XCTAssertEqual(try Data(contentsOf: sidecarURL), metadata)
    }

    func testRepeatedImportsKeepEarlierMediaAndMetadata() throws {
        let (store, directory) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Source.mov")
        let sourceData = Data("source".utf8)
        try sourceData.write(to: sourceURL)

        let firstURL = try store.importRecording(from: sourceURL, date: fixedDate)
        let firstSidecarURL = firstURL.appendingPathExtension("hovershot.json")
        let metadata = Data("existing metadata".utf8)
        try metadata.write(to: firstSidecarURL)

        let secondURL = try store.importRecording(from: sourceURL, date: fixedDate)
        let thirdURL = try store.importRecording(from: sourceURL, date: fixedDate)
        XCTAssertEqual(Set([firstURL, secondURL, thirdURL]).count, 3)
        XCTAssertEqual(firstURL.pathExtension, "mov")
        XCTAssertEqual(secondURL.pathExtension, "mov")
        XCTAssertEqual(thirdURL.pathExtension, "mov")
        for url in [sourceURL, firstURL, secondURL, thirdURL] {
            XCTAssertEqual(try Data(contentsOf: url), sourceData)
        }
        XCTAssertEqual(try Data(contentsOf: firstSidecarURL), metadata)
    }
}
