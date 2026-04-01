import AppKit
import CoreGraphics

public enum ShotRenderer {
    public static func renderedImage(for shot: Shot, using baseImage: NSImage) -> NSImage {
        guard shot.annotations.isEmpty == false else {
            return baseImage
        }

        let renderedImage = NSImage(size: baseImage.size)
        renderedImage.lockFocusFlipped(true)
        defer { renderedImage.unlockFocus() }

        let targetRect = NSRect(origin: .zero, size: baseImage.size)
        baseImage.draw(
            in: targetRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        drawAnnotations(shot.annotations, in: targetRect, sourceImageSize: baseImage.size)
        return renderedImage
    }

    public static func drawAnnotations(
        _ annotations: [ShotAnnotation],
        in targetRect: CGRect,
        sourceImageSize: CGSize
    ) {
        guard
            sourceImageSize.width > 0,
            sourceImageSize.height > 0,
            targetRect.width > 0,
            targetRect.height > 0
        else {
            return
        }

        let scaleX = targetRect.width / sourceImageSize.width
        let scaleY = targetRect.height / sourceImageSize.height

        for annotation in annotations {
            drawAnnotation(
                annotation,
                in: targetRect,
                sourceImageSize: sourceImageSize,
                scaleX: scaleX,
                scaleY: scaleY
            )
        }
    }

    private static func drawAnnotation(
        _ annotation: ShotAnnotation,
        in targetRect: CGRect,
        sourceImageSize: CGSize,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        switch annotation.style {
        case .highlight, .redaction:
            let sourceRect = annotation.rect.cgRect.standardized
            let scaledRect = CGRect(
                x: targetRect.minX + sourceRect.minX * scaleX,
                y: targetRect.minY + sourceRect.minY * scaleY,
                width: sourceRect.width * scaleX,
                height: sourceRect.height * scaleY
            )
            drawBoxAnnotation(annotation, in: scaledRect)
        case .arrow:
            drawArrowAnnotation(
                annotation,
                in: targetRect,
                sourceImageSize: sourceImageSize,
                scaleX: scaleX,
                scaleY: scaleY
            )
        case .step:
            let sourceRect = annotation.rect.cgRect.standardized
            let scaledRect = CGRect(
                x: targetRect.minX + sourceRect.minX * scaleX,
                y: targetRect.minY + sourceRect.minY * scaleY,
                width: sourceRect.width * scaleX,
                height: sourceRect.height * scaleY
            )
            drawStepAnnotation(annotation, in: scaledRect)
        case .text:
            let sourceRect = annotation.rect.cgRect.standardized
            let scaledRect = CGRect(
                x: targetRect.minX + sourceRect.minX * scaleX,
                y: targetRect.minY + sourceRect.minY * scaleY,
                width: sourceRect.width * scaleX,
                height: sourceRect.height * scaleY
            )
            drawTextAnnotation(annotation, in: scaledRect)
        }
    }

    private static func drawBoxAnnotation(_ annotation: ShotAnnotation, in rect: CGRect) {
        let rect = rect.standardized.integral.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let radius = min(max(min(rect.width, rect.height) * 0.08, 6), 16)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        switch annotation.style {
        case .highlight:
            NSColor.systemYellow.withAlphaComponent(0.22).setFill()
            path.fill()

            NSColor.systemOrange.withAlphaComponent(0.95).setStroke()
            path.lineWidth = max(3, min(rect.width, rect.height) * 0.025)
            path.stroke()
        case .redaction:
            NSColor.black.withAlphaComponent(0.94).setFill()
            path.fill()
        case .arrow, .step, .text:
            break
        }
    }

    private static func drawArrowAnnotation(
        _ annotation: ShotAnnotation,
        in targetRect: CGRect,
        sourceImageSize: CGSize,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        let start = annotation.startPoint?.cgPoint ?? annotation.rect.cgRect.origin
        let end = annotation.endPoint?.cgPoint ?? CGPoint(
            x: annotation.rect.cgRect.maxX,
            y: annotation.rect.cgRect.maxY
        )

        let scaledStart = CGPoint(
            x: targetRect.minX + start.x * scaleX,
            y: targetRect.minY + start.y * scaleY
        )
        let scaledEnd = CGPoint(
            x: targetRect.minX + end.x * scaleX,
            y: targetRect.minY + end.y * scaleY
        )

        let dx = scaledEnd.x - scaledStart.x
        let dy = scaledEnd.y - scaledStart.y
        let length = hypot(dx, dy)
        guard length >= 6 else {
            return
        }

        let arrowPath = NSBezierPath()
        arrowPath.move(to: scaledStart)
        arrowPath.line(to: scaledEnd)
        arrowPath.lineWidth = max(4, min(sourceImageSize.width, sourceImageSize.height) * 0.006)
        arrowPath.lineCapStyle = .round

        NSColor.systemRed.withAlphaComponent(0.96).setStroke()
        arrowPath.stroke()

        let unitX = dx / length
        let unitY = dy / length
        let headLength = max(12, min(28, length * 0.16))
        let headAngle = CGFloat.pi / 6

        let leftPoint = CGPoint(
            x: scaledEnd.x - headLength * (unitX * cos(headAngle) - unitY * sin(headAngle)),
            y: scaledEnd.y - headLength * (unitY * cos(headAngle) + unitX * sin(headAngle))
        )
        let rightPoint = CGPoint(
            x: scaledEnd.x - headLength * (unitX * cos(-headAngle) - unitY * sin(-headAngle)),
            y: scaledEnd.y - headLength * (unitY * cos(-headAngle) + unitX * sin(-headAngle))
        )

        let headPath = NSBezierPath()
        headPath.move(to: scaledEnd)
        headPath.line(to: leftPoint)
        headPath.line(to: rightPoint)
        headPath.close()
        NSColor.systemRed.withAlphaComponent(0.96).setFill()
        headPath.fill()
    }

    private static func drawStepAnnotation(_ annotation: ShotAnnotation, in rect: CGRect) {
        let rect = rect.standardized.integral
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let path = NSBezierPath(ovalIn: rect)
        NSColor.systemBlue.withAlphaComponent(0.98).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(13, rect.height * 0.45), weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let label = annotation.label ?? "1"
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let textRect = CGRect(
            x: rect.midX - attributed.size().width / 2,
            y: rect.midY - attributed.size().height / 2,
            width: attributed.size().width,
            height: attributed.size().height
        )
        attributed.draw(in: textRect)
    }

    private static func drawTextAnnotation(_ annotation: ShotAnnotation, in rect: CGRect) {
        let rect = rect.standardized.integral
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let path = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.28, alpha: 0.92).setFill()
        path.fill()

        NSColor.systemTeal.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2
        path.stroke()

        let insetRect = rect.insetBy(dx: 14, dy: 10)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.alignment = .left

        let fontSize = max(13, min(22, rect.height * 0.23))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let label = (annotation.label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? annotation.label!
            : "Text"
        let attributed = NSAttributedString(string: label, attributes: attributes)
        attributed.draw(with: insetRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    public static func previewStepRect(center: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        ).integral
    }

    public static func drawPreviewArrow(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length >= 6 else {
            return
        }

        let arrowPath = NSBezierPath()
        arrowPath.move(to: start)
        arrowPath.line(to: end)
        arrowPath.lineWidth = 4
        arrowPath.lineCapStyle = .round
        color.setStroke()
        arrowPath.stroke()

        let unitX = dx / length
        let unitY = dy / length
        let headLength: CGFloat = min(26, max(12, length * 0.18))
        let headAngle = CGFloat.pi / 6

        let leftPoint = CGPoint(
            x: end.x - headLength * (unitX * cos(headAngle) - unitY * sin(headAngle)),
            y: end.y - headLength * (unitY * cos(headAngle) + unitX * sin(headAngle))
        )
        let rightPoint = CGPoint(
            x: end.x - headLength * (unitX * cos(-headAngle) - unitY * sin(-headAngle)),
            y: end.y - headLength * (unitY * cos(-headAngle) + unitX * sin(-headAngle))
        )

        let headPath = NSBezierPath()
        headPath.move(to: end)
        headPath.line(to: leftPoint)
        headPath.line(to: rightPoint)
        headPath.close()
        color.setFill()
        headPath.fill()
    }

    public static func drawPreviewText(text: String, in rect: CGRect) {
        let annotation = ShotAnnotation(
            style: .text,
            rect: ShotRect(rect),
            label: text
        )
        drawTextAnnotation(annotation, in: rect)
    }
}
