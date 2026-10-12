import AppKit
import XCTest
@testable import Library
@testable import Capture
@testable import Editing

final class BrowserUXTests: XCTestCase {
    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    @MainActor
    private func field(_ label: String, in window: NSWindow) throws -> NSTextField {
        try XCTUnwrap(descendants(of: XCTUnwrap(window.contentView)).compactMap { $0 as? NSTextField }
            .first { $0.accessibilityLabel() == label })
    }

    @MainActor
    private func shotsFixture() throws -> (ShotStore, ShotsBrowserWindowController, NSWindow, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ShotStore(baseDirectoryURL: directory)
        try store.upsert(Shot(id: UUID(), title: "Alpha", assetFileName: "alpha.png"))
        try store.upsert(Shot(id: UUID(), title: "Beta", assetFileName: "beta.png"))
        let controller = ShotsBrowserWindowController(shotStore: store)
        controller.reloadShots(preservingSelection: false)
        return (store, controller, try XCTUnwrap(controller.window), directory)
    }

    @MainActor
    func testShotDraftSurvivesSelectionSearchAndReload() async throws {
        let (store, controller, window, directory) = try shotsFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = try XCTUnwrap(descendants(of: XCTUnwrap(window.contentView)).compactMap { $0 as? NSTableView }.first)
        let title = try field("Shot title", in: window)
        let originalTitle = title.stringValue
        title.stringValue = "Unpublished edit"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: title))
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertEqual(title.stringValue, "Unpublished edit")
        let search = try field("Search shots", in: window)
        search.stringValue = "definitely no match"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(table.numberOfRows, 0)
        search.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        controller.reloadShots()
        XCTAssertEqual(title.stringValue, "Unpublished edit")
        XCTAssertTrue(window.isDocumentEdited)
        XCTAssertTrue(try store.loadShots().contains { $0.title == originalTitle })
        XCTAssertFalse(try store.loadShots().contains { $0.title == "Unpublished edit" })
    }

    @MainActor
    func testShotMultipleSelectionSurvivesReload() async throws {
        let (_, controller, window, directory) = try shotsFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let table = try XCTUnwrap(descendants(of: XCTUnwrap(window.contentView)).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        controller.reloadShots()
        XCTAssertEqual(table.selectedRowIndexes.count, 2)
        XCTAssertEqual(try field("Shot title", in: window).stringValue, "2 shots selected")
    }

    @MainActor
    func testSurvivingSelectionIsKeptWhenFirstSelectedShotDisappears() async throws {
        let (store, controller, window, directory) = try shotsFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shots = try store.loadShots().sorted { $0.createdAt > $1.createdAt }
        let table = try XCTUnwrap(descendants(of: XCTUnwrap(window.contentView)).compactMap { $0 as? NSTableView }.first)
        table.selectRowIndexes(IndexSet(integersIn: 0..<2), byExtendingSelection: false)
        var newest = Shot(id: UUID(), title: "Newest unselected", assetFileName: "new.png")
        newest.createdAt = .distantFuture
        try store.save(shots: [shots[1], newest])
        controller.reloadShots()
        XCTAssertEqual(try field("Shot title", in: window).stringValue, shots[1].title)
        XCTAssertEqual(table.selectedRow, 1)
    }

    @MainActor
    func testRecordingsDraftSurvivesFilteringAndReload() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Deliberately unreadable media exercises the missing-preview state without recording the screen.
        try Data().write(to: directory.appendingPathComponent("Fixture.mp4"))
        let store = RecordingStore(baseDirectoryURL: directory)
        let controller = RecordingsBrowserWindowController(recordingStore: store)
        let window = try XCTUnwrap(controller.window)
        let title = try field("Recording title", in: window)
        for _ in 0..<100 where title.stringValue != "Fixture" {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(title.stringValue, "Fixture")
        title.stringValue = "Draft recording title"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: title))
        let search = try field("Search recordings", in: window)
        search.stringValue = "no result"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        search.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        XCTAssertEqual(title.stringValue, "Draft recording title")
        controller.reloadRecordings()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(title.stringValue, "Draft recording title")
        XCTAssertTrue(window.isDocumentEdited)
        let recordings = try await store.loadRecordings()
        XCTAssertEqual(recordings.first?.title, "Fixture")
    }

    @MainActor
    func testEmptyShotsAndNoResultsHaveDistinctRecovery() async throws {
        let (_, controller, window, directory) = try shotsFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let search = try field("Search shots", in: window)
        search.stringValue = "missing"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        let views = descendants(of: try XCTUnwrap(window.contentView))
        XCTAssertTrue(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue.hasPrefix("No matching shots") && !$0.isHidden })
        let reset = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Clear Filters" })
        XCTAssertFalse(reset.isHidden)
        reset.performClick(nil)
        XCTAssertEqual(search.stringValue, "")
        XCTAssertTrue(reset.isHidden)
    }

    @MainActor
    func testShotActionsFitSmallAndDefaultWindowWidths() async throws {
        let (_, controller, window, directory) = try shotsFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = try XCTUnwrap(window.contentView)
        for width in [640.0, 920.0] {
            window.setContentSize(NSSize(width: width, height: 620))
            content.layoutSubtreeIfNeeded()
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
            content.layoutSubtreeIfNeeded()
            let views = descendants(of: content)
            let preview = try XCTUnwrap(views.compactMap { $0 as? NSImageView }.first { $0.accessibilityLabel() == "Shot preview" })
            XCTAssertGreaterThan(preview.frame.height, 0)
            let detail = try XCTUnwrap(preview.superview)
            for button in views.compactMap({ $0 as? NSButton }) where ["Float Shot", "Annotate", "Copy", "Export", "Show in Finder", "Delete", "Refresh"].contains(button.title) {
                let frame = button.convert(button.bounds, to: detail)
                XCTAssertGreaterThanOrEqual(frame.minX, 0, button.title)
                XCTAssertLessThanOrEqual(frame.maxX, detail.bounds.width + 1, button.title)
            }
            let actions = views.compactMap { $0 as? NSButton }.filter { ["Float Shot", "Annotate", "Copy", "Export"].contains($0.title) }
            let rows = Set(actions.map { Int($0.convert($0.bounds, to: detail).minY.rounded()) })
            if width == 920 { XCTAssertLessThan(rows.count, actions.count, "Wide windows should group related actions into rows") }

        }
        withExtendedLifetime(controller) {}
    }

    @MainActor
    func testAnnotationFailedSaveKeepsChanges() async throws {
        _ = NSApplication.shared
        let shot = Shot(id: UUID(), title: "Test", assetFileName: "test.png")
        let editor = AnnotationEditorWindowController(shot: shot, baseImage: NSImage(size: NSSize(width: 320, height: 200)))
        let window = try XCTUnwrap(editor.window)
        let views = descendants(of: try XCTUnwrap(window.contentView))
        let canvas = try XCTUnwrap(views.compactMap { $0 as? AnnotationCanvasView }.first)
        let save = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first { $0.title == "Save" })
        let annotation = ShotAnnotation(style: .highlight, rect: ShotRect(x: 10, y: 10, width: 60, height: 30))
        canvas.onAnnotationsChange?([annotation])
        editor.onSave = { _, _ in false }
        save.performClick(nil)
        XCTAssertTrue(window.isDocumentEdited)
        XCTAssertTrue(save.isEnabled)
        editor.onSave = { _, _ in true }
        save.performClick(nil)
        XCTAssertFalse(window.isDocumentEdited)
        XCTAssertFalse(save.isEnabled)
    }
}
