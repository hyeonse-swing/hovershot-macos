import CoreGraphics
import XCTest
@testable import Capture
@testable import Library

final class CapturePlacementTests: XCTestCase {
    private let center = CapturePlacement.Display(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))

    func testWindowOnDisplaysInEveryDirection() {
        let displays = [
            center,
            CapturePlacement.Display(id: 2, bounds: CGRect(x: -1000, y: 0, width: 1000, height: 800)),
            CapturePlacement.Display(id: 3, bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800)),
            CapturePlacement.Display(id: 4, bounds: CGRect(x: 0, y: -800, width: 1000, height: 800)),
            CapturePlacement.Display(id: 5, bounds: CGRect(x: 0, y: 800, width: 1000, height: 800))
        ]
        let windows: [(CGRect, CGDirectDisplayID)] = [
            (CGRect(x: -900, y: 100, width: 400, height: 300), 2),
            (CGRect(x: 1200, y: 100, width: 400, height: 300), 3),
            (CGRect(x: 200, y: -700, width: 400, height: 300), 4),
            (CGRect(x: 200, y: 900, width: 400, height: 300), 5)
        ]
        for (window, expectedID) in windows {
            XCTAssertEqual(CapturePlacement.displayID(for: window, displays: displays), expectedID)
        }
    }

    func testWindowSpanningDisplaysSelectsLargestOverlap() {
        let right = CapturePlacement.Display(id: 2, bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let window = CGRect(x: 800, y: 100, width: 700, height: 400)
        XCTAssertEqual(CapturePlacement.displayID(for: window, displays: [center, right]), right.id)
    }

    func testWindowWithoutOverlapOrAreaFallsBack() {
        XCTAssertNil(CapturePlacement.displayID(for: CGRect(x: 2000, y: 0, width: 200, height: 200), displays: [center]))
        XCTAssertNil(CapturePlacement.displayID(for: .zero, displays: [center]))
        XCTAssertNil(CapturePlacement.displayID(for: CGRect(x: 10, y: 10, width: 100, height: 100), displays: []))
    }

    func testInitialFrameFitsSelectedVisibleBounds() {
        let selectedVisibleFrame = CGRect(x: -1440, y: 120, width: 1320, height: 820)
        let frame = FloatingShotPlacement.defaultInitialFrame(
            for: CGSize(width: 3000, height: 2000),
            visibleFrame: selectedVisibleFrame
        )
        XCTAssertGreaterThanOrEqual(frame.minX, selectedVisibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, selectedVisibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, selectedVisibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, selectedVisibleFrame.maxY)
        XCTAssertLessThan(frame.midX, 0)
    }
}
