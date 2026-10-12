import Foundation
import XCTest
@testable import Library

final class ShotStoreTests: XCTestCase {
    private func fixture(fileManager: FileManager = .default) throws -> (ShotStore, Shot, URL, Data) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ShotStore(fileManager: fileManager, baseDirectoryURL: directory)
        let shot = Shot(id: UUID(), title: "Keep this shot", assetFileName: "fixture.png")
        let imageData = Data("original image bytes".utf8)
        try imageData.write(to: store.assetURL(for: shot))
        try store.upsert(shot)
        return (store, shot, directory, imageData)
    }

    func testMetadataWriteFailurePreservesImageAndRecord() throws {
        let (store, shot, directory, imageData) = try fixture()
        let metadataURL = directory.appendingPathComponent("shots.json")
        let metadata = try Data(contentsOf: metadataURL)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        // Assets remains writable, reproducing the old remove-image-then-fail-write path.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try store.deleteShot(withID: shot.id))
        XCTAssertEqual(try Data(contentsOf: store.assetURL(for: shot)), imageData)
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadata)
        XCTAssertEqual(try store.loadShot(withID: shot.id).id, shot.id)
    }

    func testAssetRemovalFailureRestoresRecord() throws {
        let fileManager = FailingRemovalFileManager()
        let (store, shot, directory, imageData) = try fixture(fileManager: fileManager)
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataURL = directory.appendingPathComponent("shots.json")
        let metadata = try Data(contentsOf: metadataURL)
        fileManager.blockedURL = store.assetURL(for: shot)
        XCTAssertThrowsError(try store.deleteShot(withID: shot.id))
        XCTAssertEqual(try Data(contentsOf: store.assetURL(for: shot)), imageData)
        XCTAssertEqual(try Data(contentsOf: metadataURL), metadata)
    }

    func testSuccessfulDeletionRemovesImageAndOnlyMatchingRecord() throws {
        let (store, shot, directory, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let other = Shot(id: UUID(), title: "Other", assetFileName: "other.png")
        try store.upsert(other)
        XCTAssertEqual(try store.deleteShot(withID: shot.id).id, shot.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetURL(for: shot).path))
        XCTAssertEqual(try store.loadShots().map(\.id), [other.id])
    }

    func testMissingImageStillAllowsDeletingRecord() throws {
        let (store, shot, directory, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.removeItem(at: store.assetURL(for: shot))
        XCTAssertEqual(try store.deleteShot(withID: shot.id).id, shot.id)
        XCTAssertTrue(try store.loadShots().isEmpty)
    }
}

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    var blockedURL: URL?

    override func removeItem(at URL: URL) throws {
        if URL == blockedURL {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}
