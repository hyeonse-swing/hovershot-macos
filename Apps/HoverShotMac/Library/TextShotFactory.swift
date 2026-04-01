import AppKit
import Foundation

public enum TextShotFactory {
    public static func makeImage(
        text: String,
        title: String,
        size: NSSize = NSSize(width: 520, height: 320)
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        defer {
            image.unlockFocus()
        }

        let bounds = NSRect(origin: .zero, size: size)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.86, alpha: 1.0),
            NSColor(calibratedRed: 0.93, green: 0.90, blue: 0.78, alpha: 1.0)
        ])
        gradient?.draw(in: bounds, angle: 90)

        let paperBounds = bounds.insetBy(dx: 28, dy: 28)
        let paperPath = NSBezierPath(roundedRect: paperBounds, xRadius: 22, yRadius: 22)
        NSColor.white.withAlphaComponent(0.84).setFill()
        paperPath.fill()

        NSColor.black.withAlphaComponent(0.08).setStroke()
        paperPath.lineWidth = 1
        paperPath.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0)
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1.0)
        ]
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.36, alpha: 1.0)
        ]

        title.draw(
            in: NSRect(x: paperBounds.minX + 22, y: paperBounds.maxY - 54, width: paperBounds.width - 44, height: 28),
            withAttributes: titleAttributes
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 4

        let attributedText = NSAttributedString(
            string: normalizedPreviewText(text),
            attributes: bodyAttributes.merging([.paragraphStyle: paragraphStyle]) { _, rhs in rhs }
        )
        attributedText.draw(
            in: NSRect(x: paperBounds.minX + 22, y: paperBounds.minY + 42, width: paperBounds.width - 44, height: paperBounds.height - 108)
        )

        "Imported from clipboard".draw(
            in: NSRect(x: paperBounds.minX + 22, y: paperBounds.minY + 16, width: paperBounds.width - 44, height: 16),
            withAttributes: footerAttributes
        )

        return image
    }

    private static func normalizedPreviewText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return "Empty clipboard text"
        }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .prefix(14)

        return lines.joined(separator: "\n")
    }
}
