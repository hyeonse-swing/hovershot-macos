import AppKit
import Foundation

public enum DemoShotFactory {
    public static func makeImage(
        title: String,
        subtitle: String,
        size: NSSize = NSSize(width: 420, height: 260)
    ) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        defer {
            image.unlockFocus()
        }

        let bounds = NSRect(origin: .zero, size: size)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.15, green: 0.18, blue: 0.28, alpha: 1.0),
            NSColor(calibratedRed: 0.10, green: 0.39, blue: 0.64, alpha: 1.0),
            NSColor(calibratedRed: 0.22, green: 0.62, blue: 0.55, alpha: 1.0)
        ])

        gradient?.draw(in: bounds, angle: 125)

        let cardBounds = bounds.insetBy(dx: 24, dy: 24)
        let cardPath = NSBezierPath(roundedRect: cardBounds, xRadius: 22, yRadius: 22)
        NSColor.white.withAlphaComponent(0.14).setFill()
        cardPath.fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        let accentRect = NSRect(x: cardBounds.minX + 24, y: cardBounds.maxY - 56, width: 72, height: 8)
        let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.8).setFill()
        accentPath.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]
        let footnoteAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72)
        ]

        title.draw(
            in: NSRect(x: cardBounds.minX + 24, y: cardBounds.midY + 18, width: cardBounds.width - 48, height: 40),
            withAttributes: titleAttributes
        )

        subtitle.draw(
            in: NSRect(x: cardBounds.minX + 24, y: cardBounds.midY - 18, width: cardBounds.width - 48, height: 42),
            withAttributes: subtitleAttributes
        )

        "Scroll over the shot to change opacity".draw(
            in: NSRect(x: cardBounds.minX + 24, y: cardBounds.minY + 20, width: cardBounds.width - 48, height: 20),
            withAttributes: footnoteAttributes
        )

        return image
    }
}
