import AppKit
import Foundation

@MainActor
final class TimedCaptureCountdownWindowController: NSWindowController {
    private let titleField = NSTextField(labelWithString: "Timed Capture")
    private let countdownField = NSTextField(labelWithString: "")

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .statusBar
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.ignoresMouseEvents = true
        window.center()

        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show(remainingSeconds: Int) {
        titleField.stringValue = "Timed Capture"
        countdownField.stringValue = "\(remainingSeconds)"
        centerWindow()
        window?.orderFrontRegardless()
    }

    func closeOverlay() {
        guard let window else {
            return
        }

        window.orderOut(nil)
        NSApp.updateWindows()
        close()
    }

    private func configureWindow() {
        guard let window else {
            return
        }

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 28
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        titleField.font = .systemFont(ofSize: 18, weight: .semibold)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.translatesAutoresizingMaskIntoConstraints = false

        countdownField.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        countdownField.textColor = .white
        countdownField.alignment = .center
        countdownField.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleField)
        contentView.addSubview(countdownField)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            titleField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            countdownField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 14),
            countdownField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            countdownField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            countdownField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -28)
        ])
    }

    private func centerWindow() {
        guard
            let screen = NSScreen.main ?? NSScreen.screens.first,
            let window
        else {
            return
        }

        let frame = window.frame
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - (frame.width / 2),
            y: visibleFrame.midY - (frame.height / 2)
        )
        window.setFrameOrigin(origin)
    }
}
