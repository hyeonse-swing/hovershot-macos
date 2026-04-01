import AppKit
import ScreenCaptureKit

@MainActor
final class WindowPicker {
    func chooseWindow(from windows: [SCWindow], purpose: String = "Capture Window") -> SCWindow? {
        guard windows.isEmpty == false else {
            return nil
        }

        let popupButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 28), pullsDown: false)
        popupButton.autoenablesItems = false

        for (index, window) in windows.enumerated() {
            popupButton.addItem(withTitle: label(for: window))
            popupButton.itemArray[index].tag = Int(window.windowID)
        }

        let messageLabel = NSTextField(wrappingLabelWithString: "Choose a window to capture. Hidden, desktop, and tiny utility windows are filtered out.")
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 420

        let stackView = NSStackView(views: [messageLabel, popupButton])
        stackView.orientation = .vertical
        stackView.spacing = 12
        stackView.alignment = .leading

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 72))
        stackView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = purpose
        alert.informativeText = "Select one of the currently shareable windows."
        alert.accessoryView = container
        alert.addButton(withTitle: actionTitle(for: purpose))
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return windows[safe: popupButton.indexOfSelectedItem]
    }

    private func actionTitle(for purpose: String) -> String {
        if purpose.localizedCaseInsensitiveContains("record") {
            return "Record"
        }

        return "Capture"
    }

    private func label(for window: SCWindow) -> String {
        let title = sanitizedTitle(window.title)
        let appName = window.owningApplication?.applicationName ?? "Unknown App"
        let width = Int(window.frame.width.rounded())
        let height = Int(window.frame.height.rounded())
        return "\(appName) - \(title) (\(width)x\(height))"
    }

    private func sanitizedTitle(_ title: String?) -> String {
        guard let title, title.isEmpty == false else {
            return "Untitled Window"
        }

        return title
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
