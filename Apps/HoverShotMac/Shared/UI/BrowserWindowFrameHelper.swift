@preconcurrency import AppKit
import CoreGraphics

@MainActor
public enum BrowserWindowFrameHelper {
    private static let outerMargin: CGFloat = 24

    public static func prepareForStandardBrowserBehavior(_ window: NSWindow) {
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.collectionBehavior.insert(.moveToActiveSpace)
        RuntimeTrace.log("prepare browser window title=\(window.title) behavior=\(window.collectionBehavior.rawValue)")
    }

    public static func normalizeFrame(
        of window: NSWindow,
        preferredSize: NSSize
    ) {
        let targetScreen = preferredScreen(for: window)
        let visibleFrame = targetScreen.visibleFrame.insetBy(dx: outerMargin, dy: outerMargin)
        RuntimeTrace.log("normalize begin title=\(window.title) current=\(NSStringFromRect(window.frame)) targetVisible=\(NSStringFromRect(visibleFrame))")
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return
        }

        let minimumWidth = max(window.minSize.width, 640)
        let minimumHeight = max(window.minSize.height, 420)
        let targetWidth = min(max(preferredSize.width, minimumWidth), visibleFrame.width)
        let targetHeight = min(max(preferredSize.height, minimumHeight), visibleFrame.height)

        var frame = window.frame
        let hasUsableFrame =
            frame.width >= minimumWidth &&
            frame.height >= minimumHeight &&
            frame.intersects(targetScreen.visibleFrame)

        if hasUsableFrame == false {
            frame = NSRect(
                x: visibleFrame.midX - (targetWidth / 2),
                y: visibleFrame.midY - (targetHeight / 2),
                width: targetWidth,
                height: targetHeight
            ).integral
            window.setFrame(frame, display: false)
            RuntimeTrace.log("normalize replaced title=\(window.title) frame=\(NSStringFromRect(frame))")
            return
        }

        frame.size.width = min(frame.width, visibleFrame.width)
        frame.size.height = min(frame.height, visibleFrame.height)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)

        if frame.equalTo(window.frame) == false {
            window.setFrame(frame.integral, display: false)
            RuntimeTrace.log("normalize adjusted title=\(window.title) frame=\(NSStringFromRect(frame.integral))")
        }
    }

    private static func preferredScreen(for window: NSWindow) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }

        if let screen = NSScreen.main {
            return screen
        }

        if let screen = window.screen {
            return screen
        }

        return NSScreen.screens.first ?? NSScreen()
    }

    public static func bringAppAndWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFront(nil)
        RuntimeTrace.log("bring front title=\(window.title) frame=\(NSStringFromRect(window.frame)) visible=\(window.isVisible) key=\(window.isKeyWindow)")
    }
}
