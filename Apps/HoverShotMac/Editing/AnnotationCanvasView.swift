import AppKit
import Library

final class AnnotationCanvasView: NSView {
    private let minimumBoxSize: CGFloat = 8
    private let minimumArrowLength: CGFloat = 10
    private let stepDiameterInImageSpace: CGFloat = 42
    private let minimumTextWidth: CGFloat = 96
    private let minimumTextHeight: CGFloat = 42
    private let defaultTextBoxSize = CGSize(width: 190, height: 74)

    override var isFlipped: Bool {
        true
    }

    var baseImage: NSImage? {
        didSet {
            needsDisplay = true
        }
    }

    var annotations: [ShotAnnotation] = [] {
        didSet {
            needsDisplay = true
        }
    }

    var currentStyle: ShotAnnotationStyle = .highlight
    var currentText: String = "Note"
    var onAnnotationsChange: (([ShotAnnotation]) -> Void)?

    private var dragStartPoint: CGPoint?
    private var dragCurrentPoint: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()

        guard let baseImage else {
            return
        }

        let imageFrame = imageFrame(for: baseImage.size)
        let cardPath = NSBezierPath(roundedRect: imageFrame, xRadius: 18, yRadius: 18)
        NSColor.windowBackgroundColor.setFill()
        cardPath.fill()

        baseImage.draw(
            in: imageFrame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        ShotRenderer.drawAnnotations(annotations, in: imageFrame, sourceImageSize: baseImage.size)

        if let preview = previewShape() {
            drawPreview(preview)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let baseImage else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let imageFrame = imageFrame(for: baseImage.size)
        guard imageFrame.contains(point) else {
            return
        }

        let clampedPoint = clamp(point, to: imageFrame)
        dragStartPoint = clampedPoint
        dragCurrentPoint = clampedPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint, let baseImage else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        dragCurrentPoint = clamp(point, to: imageFrame(for: baseImage.size))
        if dragStartPoint != dragCurrentPoint {
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard
            let baseImage,
            let dragStartPoint
        else {
            return
        }

        let imageFrame = imageFrame(for: baseImage.size)
        let point = clamp(convert(event.locationInWindow, from: nil), to: imageFrame)
        let viewRect = CGRect(
            x: min(dragStartPoint.x, point.x),
            y: min(dragStartPoint.y, point.y),
            width: abs(dragStartPoint.x - point.x),
            height: abs(dragStartPoint.y - point.y)
        )

        self.dragStartPoint = nil
        dragCurrentPoint = nil

        switch currentStyle {
        case .highlight, .redaction:
            guard viewRect.width >= minimumBoxSize, viewRect.height >= minimumBoxSize else {
                needsDisplay = true
                return
            }

            let imageRect = viewRectToImageRect(viewRect, imageFrame: imageFrame, imageSize: baseImage.size)
            annotations.append(
                ShotAnnotation(
                    style: currentStyle,
                    rect: ShotRect(imageRect)
                )
            )
        case .arrow:
            let length = hypot(point.x - dragStartPoint.x, point.y - dragStartPoint.y)
            guard length >= minimumArrowLength else {
                needsDisplay = true
                return
            }

            let imageStart = viewPointToImagePoint(dragStartPoint, imageFrame: imageFrame, imageSize: baseImage.size)
            let imageEnd = viewPointToImagePoint(point, imageFrame: imageFrame, imageSize: baseImage.size)
            let imageRect = CGRect(
                x: min(imageStart.x, imageEnd.x),
                y: min(imageStart.y, imageEnd.y),
                width: abs(imageStart.x - imageEnd.x),
                height: abs(imageStart.y - imageEnd.y)
            ).integral

            annotations.append(
                ShotAnnotation(
                    style: .arrow,
                    rect: ShotRect(imageRect),
                    startPoint: ShotPoint(imageStart),
                    endPoint: ShotPoint(imageEnd)
                )
            )
        case .step:
            let imagePoint = viewPointToImagePoint(point, imageFrame: imageFrame, imageSize: baseImage.size)
            let diameter = stepDiameterInImageSpace
            let imageRect = CGRect(
                x: imagePoint.x - diameter / 2,
                y: imagePoint.y - diameter / 2,
                width: diameter,
                height: diameter
            ).integral

            annotations.append(
                ShotAnnotation(
                    style: .step,
                    rect: ShotRect(imageRect),
                    label: nextStepNumber()
                )
            )
        case .text:
            let effectiveViewRect: CGRect
            if viewRect.width >= minimumTextWidth, viewRect.height >= minimumTextHeight {
                effectiveViewRect = viewRect
            } else {
                effectiveViewRect = defaultTextRect(around: point, imageFrame: imageFrame)
            }

            let imageRect = viewRectToImageRect(
                effectiveViewRect,
                imageFrame: imageFrame,
                imageSize: baseImage.size
            )
            annotations.append(
                ShotAnnotation(
                    style: .text,
                    rect: ShotRect(imageRect),
                    label: effectiveText()
                )
            )
        }
        onAnnotationsChange?(annotations)
        needsDisplay = true
    }

    func undoLastAnnotation() {
        guard annotations.isEmpty == false else {
            return
        }

        annotations.removeLast()
        onAnnotationsChange?(annotations)
    }

    func clearAnnotations() {
        guard annotations.isEmpty == false else {
            return
        }

        annotations = []
        onAnnotationsChange?(annotations)
    }

    private func previewShape() -> PreviewShape? {
        guard
            let dragStartPoint,
            let dragCurrentPoint
        else {
            return nil
        }

        let rect = CGRect(
            x: min(dragStartPoint.x, dragCurrentPoint.x),
            y: min(dragStartPoint.y, dragCurrentPoint.y),
            width: abs(dragStartPoint.x - dragCurrentPoint.x),
            height: abs(dragStartPoint.y - dragCurrentPoint.y)
        )

        switch currentStyle {
        case .highlight, .redaction:
            return .rect(rect)
        case .arrow:
            return .arrow(start: dragStartPoint, end: dragCurrentPoint)
        case .step:
            return .step(center: dragCurrentPoint)
        case .text:
            let textRect: CGRect
            if rect.width >= minimumTextWidth, rect.height >= minimumTextHeight {
                textRect = rect
            } else {
                textRect = defaultTextRect(around: dragCurrentPoint, imageFrame: imageFrame(for: baseImage?.size ?? .zero))
            }
            return .text(rect: textRect, text: effectiveText())
        }
    }

    private func drawPreview(_ previewShape: PreviewShape) {
        switch previewShape {
        case let .rect(rect):
            let rect = rect.standardized.integral.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

            switch currentStyle {
            case .highlight:
                NSColor.systemYellow.withAlphaComponent(0.16).setFill()
                path.fill()
                NSColor.systemOrange.withAlphaComponent(0.95).setStroke()
            case .redaction:
                NSColor.black.withAlphaComponent(0.28).setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.9).setStroke()
            case .arrow, .step, .text:
                break
            }

            let dashPattern: [CGFloat] = [8, 6]
            path.lineWidth = 3
            path.setLineDash(dashPattern, count: dashPattern.count, phase: 0)
            path.stroke()
        case let .arrow(start, end):
            ShotRenderer.drawPreviewArrow(
                from: start,
                to: end,
                color: NSColor.systemRed.withAlphaComponent(0.96)
            )
        case let .step(center):
            let rect = ShotRenderer.previewStepRect(center: center, diameter: 34)
            let path = NSBezierPath(ovalIn: rect)
            NSColor.systemBlue.withAlphaComponent(0.86).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 2
            path.stroke()

            let label = nextStepNumber()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let attributed = NSAttributedString(string: label, attributes: attributes)
            let size = attributed.size()
            attributed.draw(in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            ))
        case let .text(rect, text):
            ShotRenderer.drawPreviewText(text: text, in: rect.standardized.integral)
        }
    }

    private func imageFrame(for imageSize: NSSize) -> CGRect {
        let availableRect = bounds.insetBy(dx: 24, dy: 24)
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            availableRect.width > 0,
            availableRect.height > 0
        else {
            return availableRect
        }

        let scale = min(availableRect.width / imageSize.width, availableRect.height / imageSize.height)
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: availableRect.midX - size.width / 2,
            y: availableRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    private func viewRectToImageRect(
        _ viewRect: CGRect,
        imageFrame: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let scaleX = imageSize.width / imageFrame.width
        let scaleY = imageSize.height / imageFrame.height
        let rect = viewRect.standardized

        return CGRect(
            x: (rect.minX - imageFrame.minX) * scaleX,
            y: (rect.minY - imageFrame.minY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
    }

    private func viewPointToImagePoint(
        _ point: CGPoint,
        imageFrame: CGRect,
        imageSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (point.x - imageFrame.minX) * (imageSize.width / imageFrame.width),
            y: (point.y - imageFrame.minY) * (imageSize.height / imageFrame.height)
        )
    }

    private func nextStepNumber() -> String {
        let numbers = annotations.compactMap { annotation -> Int? in
            guard annotation.style == .step else {
                return nil
            }

            return Int(annotation.label ?? "")
        }

        return String((numbers.max() ?? 0) + 1)
    }

    private func effectiveText() -> String {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Text" : trimmed
    }

    private func defaultTextRect(around point: CGPoint, imageFrame: CGRect) -> CGRect {
        let proposed = CGRect(
            x: point.x - defaultTextBoxSize.width / 2,
            y: point.y - defaultTextBoxSize.height / 2,
            width: defaultTextBoxSize.width,
            height: defaultTextBoxSize.height
        )

        return clamp(rect: proposed, to: imageFrame)
    }

    private func clamp(rect: CGRect, to bounds: CGRect) -> CGRect {
        var rect = rect.standardized

        if rect.width > bounds.width {
            rect.size.width = bounds.width
        }
        if rect.height > bounds.height {
            rect.size.height = bounds.height
        }

        rect.origin.x = min(max(rect.origin.x, bounds.minX), bounds.maxX - rect.width)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), bounds.maxY - rect.height)
        return rect.integral
    }
}

private enum PreviewShape {
    case rect(CGRect)
    case arrow(start: CGPoint, end: CGPoint)
    case step(center: CGPoint)
    case text(rect: CGRect, text: String)
}
