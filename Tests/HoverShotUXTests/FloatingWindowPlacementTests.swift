import AppKit
import XCTest
@testable import FloatingShots
@testable import Library

final class FloatingWindowPlacementTests: XCTestCase {
    @MainActor
    func testRevealKeepsNewShotOnEveryConnectedCaptureScreen() async throws {
        _ = NSApplication.shared
        XCTAssertFalse(NSScreen.screens.isEmpty)
        var controllers: [FloatingShotWindowController] = []
        defer {
            for controller in controllers {
                controller.close()
                NSWindow.removeFrame(usingName: "shot-\(controller.shotID.uuidString)")
            }
        }
        for screen in NSScreen.screens {
            let image = NSImage(size: NSSize(width: 320, height: 200))
            let intendedFrame = FloatingShotPlacement.defaultInitialFrame(
                for: image.size,
                visibleFrame: screen.visibleFrame
            )
            let shot = Shot(
                id: UUID(), title: "HoverShot placement test", assetFileName: "fixture.png",
                floatingState: FloatingShotState(frame: ShotRect(intendedFrame))
            )
            let controller = FloatingShotWindowController(shot: shot, image: image)
            controllers.append(controller)
            let window = try XCTUnwrap(controller.window)
            controller.reveal()
            try await Task.sleep(for: .milliseconds(100))
            let actualScreen = window.screen
            let actualFrame = window.frame
            XCTAssertEqual(actualScreen, screen, "Showing the result must preserve its capture screen")
            XCTAssertEqual(actualFrame.origin.x, intendedFrame.origin.x, accuracy: 1)
            XCTAssertEqual(actualFrame.origin.y, intendedFrame.origin.y, accuracy: 1)
        }
    }

    @MainActor
    func testRepeatedRevealPreservesUserMovedFrame() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let image = NSImage(size: NSSize(width: 320, height: 200))
        let initialFrame = FloatingShotPlacement.defaultInitialFrame(for: image.size, visibleFrame: screen.visibleFrame)
        let shot = Shot(
            id: UUID(), title: "HoverShot placement test", assetFileName: "fixture.png",
            floatingState: FloatingShotState(frame: ShotRect(initialFrame))
        )
        let controller = FloatingShotWindowController(shot: shot, image: image)
        defer {
            controller.close()
            NSWindow.removeFrame(usingName: "shot-\(shot.id.uuidString)")
        }
        let window = try XCTUnwrap(controller.window)
        controller.reveal()
        let targetScreen = NSScreen.screens.last ?? screen
        var movedFrame = FloatingShotPlacement.defaultInitialFrame(for: image.size, visibleFrame: targetScreen.visibleFrame)
        movedFrame.origin.x += 80
        movedFrame.origin.y -= 60
        window.setFrame(movedFrame, display: false)
        try await Task.sleep(for: .milliseconds(100))
        controller.reveal()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(window.screen, targetScreen)
        XCTAssertEqual(window.frame, movedFrame, "Reopening a visible shot must keep the user's placement")
    }
}
