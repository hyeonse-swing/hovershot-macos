@preconcurrency import AppKit

@MainActor
protocol AreaSelectionWindowControllerDelegate: AnyObject {
    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didBeginSelectionAt globalPoint: CGPoint
    )

    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didUpdateSelectionAt globalPoint: CGPoint
    )

    func areaSelectionWindowController(
        _ controller: AreaSelectionWindowController,
        didFinishSelectionAt globalPoint: CGPoint
    )
}

final class AreaSelectionWindowController: NSWindowController {
    let screen: NSScreen
    let displayID: CGDirectDisplayID

    weak var delegate: AreaSelectionWindowControllerDelegate?

    private let selectionView = AreaSelectionView(frame: .zero)

    init(screen: NSScreen) {
        self.screen = screen
        self.displayID = screen.screenHoveringDisplayID ?? 0

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.hasShadow = false

        super.init(window: window)

        selectionView.frame = CGRect(origin: .zero, size: screen.frame.size)
        selectionView.autoresizingMask = [.width, .height]
        selectionView.onMouseDownAtPoint = { [weak self] point in
            guard let self else {
                return
            }

            delegate?.areaSelectionWindowController(
                self,
                didBeginSelectionAt: globalPoint(fromWindowPoint: point)
            )
        }
        selectionView.onMouseDraggedToPoint = { [weak self] point in
            guard let self else {
                return
            }

            delegate?.areaSelectionWindowController(
                self,
                didUpdateSelectionAt: globalPoint(fromWindowPoint: point)
            )
        }
        selectionView.onMouseUpAtPoint = { [weak self] point in
            guard let self else {
                return
            }

            delegate?.areaSelectionWindowController(
                self,
                didFinishSelectionAt: globalPoint(fromWindowPoint: point)
            )
        }

        window.contentView = selectionView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func reveal() {
        guard let window else {
            return
        }

        window.orderFrontRegardless()
    }

    func updateSelection(globalRect: CGRect?) {
        guard let globalRect else {
            selectionView.selectionRect = nil
            return
        }

        let localRect = globalRect.offsetBy(
            dx: -screen.frame.minX,
            dy: -screen.frame.minY
        )
        selectionView.selectionRect = localRect
    }

    private func globalPoint(fromWindowPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: screen.frame.minX + point.x,
            y: screen.frame.minY + point.y
        )
    }
}
