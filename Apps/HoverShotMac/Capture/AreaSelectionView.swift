@preconcurrency import AppKit

final class AreaSelectionView: NSView {
    var onMouseDownAtPoint: ((CGPoint) -> Void)?
    var onMouseDraggedToPoint: ((CGPoint) -> Void)?
    var onMouseUpAtPoint: ((CGPoint) -> Void)?

    var selectionRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDownAtPoint?(event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDraggedToPoint?(event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUpAtPoint?(event.locationInWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let overlayPath = NSBezierPath(rect: bounds)
        if let selectionRect {
            overlayPath.append(NSBezierPath(rect: selectionRect))
            overlayPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.42).setFill()
        overlayPath.fill()

        guard let selectionRect else {
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        NSBezierPath(rect: selectionRect).fill()

        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 2
        NSColor.white.setStroke()
        borderPath.stroke()

        let sizeLabel = "\(Int(selectionRect.width.rounded())) × \(Int(selectionRect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let labelSize = sizeLabel.size(withAttributes: attributes)
        let labelRect = NSRect(
            x: selectionRect.minX,
            y: max(selectionRect.minY - 28, 12),
            width: labelSize.width + 14,
            height: 22
        )

        let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 11, yRadius: 11)
        NSColor.black.withAlphaComponent(0.72).setFill()
        labelPath.fill()

        sizeLabel.draw(
            in: labelRect.insetBy(dx: 7, dy: 4),
            withAttributes: attributes
        )
    }
}
