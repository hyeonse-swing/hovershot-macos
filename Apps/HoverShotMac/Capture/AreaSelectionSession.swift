@preconcurrency import AppKit
import Foundation
import Library

@MainActor
final class AreaSelectionSession: NSObject {
    typealias Completion = (Result<CaptureArea, CaptureError>) -> Void

    private var windows: [AreaSelectionWindowController] = []
    private var keyMonitor: Any?

    private var activeDisplayID: CGDirectDisplayID?
    private var activeScreenFrame: CGRect?
    private var activeScaleFactor: CGFloat = 1
    private var selectionStartPoint: CGPoint?
    private var selectionCurrentPoint: CGPoint?

    private let completion: Completion

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func start() {
        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.compactMap { screen in
            guard screen.screenHoveringDisplayID != nil else {
                return nil
            }

            let controller = AreaSelectionWindowController(screen: screen)
            controller.delegate = self
            return controller
        }

        for controller in windows {
            controller.reveal()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if event.keyCode == 53 {
                self.finish(with: .failure(.selectionCancelled))
                return nil
            }

            return event
        }
    }

    private func updateSelection(globalPoint: CGPoint) {
        guard let activeScreenFrame else {
            return
        }

        selectionCurrentPoint = clamp(point: globalPoint, to: activeScreenFrame)
        refreshSelection()
    }

    private func refreshSelection() {
        let selectionRect = currentSelectionRect()

        for controller in windows {
            if controller.displayID == activeDisplayID {
                controller.updateSelection(globalRect: selectionRect)
            } else {
                controller.updateSelection(globalRect: nil)
            }
        }
    }

    private func currentSelectionRect() -> CGRect? {
        guard
            let start = selectionStartPoint,
            let current = selectionCurrentPoint
        else {
            return nil
        }

        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        ).integral
    }

    private func clamp(point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    private func finish(with result: Result<CaptureArea, CaptureError>) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        for controller in windows {
            controller.close()
        }
        windows.removeAll()

        completion(result)
    }
}

@MainActor
extension AreaSelectionSession: AreaSelectionWindowControllerDelegate {
    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didBeginSelectionAt globalPoint: CGPoint
    ) {
        activeDisplayID = controller.displayID
        activeScreenFrame = controller.screen.frame
        activeScaleFactor = controller.screen.backingScaleFactor
        selectionStartPoint = clamp(point: globalPoint, to: controller.screen.frame)
        selectionCurrentPoint = selectionStartPoint
        refreshSelection()
    }

    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didUpdateSelectionAt globalPoint: CGPoint
    ) {
        updateSelection(globalPoint: globalPoint)
    }

    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didFinishSelectionAt globalPoint: CGPoint
    ) {
        updateSelection(globalPoint: globalPoint)

        guard
            let activeDisplayID,
            let activeScreenFrame,
            let selectionRect = currentSelectionRect(),
            selectionRect.width >= 8,
            selectionRect.height >= 8
        else {
            finish(with: .failure(.selectionCancelled))
            return
        }

        let localRect = selectionRect.offsetBy(
            dx: -activeScreenFrame.minX,
            dy: -activeScreenFrame.minY
        )
        let pixelRect = CGRect(
            x: localRect.minX * activeScaleFactor,
            y: localRect.minY * activeScaleFactor,
            width: localRect.width * activeScaleFactor,
            height: localRect.height * activeScaleFactor
        ).integral

        let area = CaptureArea(
            displayID: activeDisplayID,
            rect: ShotRect(pixelRect)
        )
        finish(with: .success(area))
    }
}
