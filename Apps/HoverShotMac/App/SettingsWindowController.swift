@preconcurrency import AppKit
import Carbon
import Shared

@MainActor
final class SettingsWindowController: NSWindowController {
    var onDidUpdateShortcuts: (([HotKeyAction: HotKeyShortcut]) -> Void)?

    private static let preferredWindowSize = NSSize(width: 760, height: 680)

    private struct RowControls {
        let recordButton: NSButton
        let clearButton: NSButton
    }

    private let store: HotKeyPreferencesStore
    private var shortcuts: [HotKeyAction: HotKeyShortcut]
    private var rows: [HotKeyAction: RowControls] = [:]
    private var activeRecordingAction: HotKeyAction?
    private var keyMonitor: Any?

    private let statusField = NSTextField(labelWithString: "Choose global shortcuts for the actions you use most. Changes apply immediately.")
    private let noteField = NSTextField(labelWithString: "Press a shortcut with at least one modifier. Press Esc to cancel recording. Assigning an existing shortcut moves it from the previous action.")

    init(store: HotKeyPreferencesStore) {
        self.store = store
        self.shortcuts = store.load()

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 280, y: 220), size: Self.preferredWindowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("hovershot-settings")
        window.setFrameAutosaveName("HoverShotSettings")
        window.minSize = NSSize(width: 640, height: 520)

        super.init(window: window)

        configureWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(cancelRecordingForWindowChange), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowWillClose), name: NSWindow.willCloseNotification, object: window)
        installKeyMonitor()
        refreshRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func present() {
        statusField.stringValue = "Choose global shortcuts for the actions you use most. Changes apply immediately."
        installKeyMonitor()
        showWindow(nil)
        if let window {
            BrowserWindowFrameHelper.normalizeFrame(of: window, preferredSize: Self.preferredWindowSize)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureWindow() {
        guard let window else {
            return
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        statusField.font = .systemFont(ofSize: 14, weight: .semibold)
        statusField.textColor = .labelColor
        statusField.lineBreakMode = .byWordWrapping
        statusField.maximumNumberOfLines = 2
        statusField.translatesAutoresizingMaskIntoConstraints = false

        noteField.font = .systemFont(ofSize: 12, weight: .regular)
        noteField.textColor = .secondaryLabelColor
        noteField.lineBreakMode = .byWordWrapping
        noteField.maximumNumberOfLines = 0
        noteField.translatesAutoresizingMaskIntoConstraints = false

        let rowsStack = NSStackView()
        rowsStack.orientation = .vertical
        rowsStack.spacing = 10
        rowsStack.alignment = .leading
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        for action in HotKeyAction.allCases {
            let row = makeRow(for: action)
            rowsStack.addArrangedSubview(row)
        }

        let rowsContainer = NSView()
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        rowsContainer.addSubview(rowsStack)

        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: rowsContainer.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: rowsContainer.leadingAnchor),
            rowsStack.trailingAnchor.constraint(equalTo: rowsContainer.trailingAnchor),
            rowsStack.bottomAnchor.constraint(equalTo: rowsContainer.bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rowsContainer.widthAnchor)
        ])

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = rowsContainer

        let resetButton = NSButton(title: "Restore Defaults", target: self, action: #selector(handleRestoreDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let doneButton = NSButton(title: "Done", target: self, action: #selector(handleDone))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonRow = NSStackView(views: [resetButton, NSView(), doneButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(statusField)
        contentView.addSubview(noteField)
        contentView.addSubview(scrollView)
        contentView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            statusField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            statusField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            noteField.topAnchor.constraint(equalTo: statusField.bottomAnchor, constant: 6),
            noteField.leadingAnchor.constraint(equalTo: statusField.leadingAnchor),
            noteField.trailingAnchor.constraint(equalTo: statusField.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: noteField.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -16),

            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            buttonRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    private func makeRow(for action: HotKeyAction) -> NSView {
        let titleField = NSTextField(labelWithString: action.displayName)
        titleField.font = .systemFont(ofSize: 13, weight: .medium)
        titleField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(equalToConstant: 210).isActive = true

        let recordButton = NSButton(title: "", target: self, action: #selector(handleRecordShortcut(_:)))
        recordButton.bezelStyle = .rounded
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.widthAnchor.constraint(equalToConstant: 180).isActive = true
        recordButton.identifier = NSUserInterfaceItemIdentifier(action.rawValue)

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(handleClearShortcut(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        clearButton.setAccessibilityLabel("Clear shortcut for \(action.displayName)")

        let row = NSStackView(views: [titleField, recordButton, clearButton])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        rows[action] = RowControls(recordButton: recordButton, clearButton: clearButton)
        return row
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else {
            return
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            return self.handleKeyDown(event)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let action = activeRecordingAction,
              let window,
              window.isKeyWindow,
              event.window === window else {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape) {
            activeRecordingAction = nil
            statusField.stringValue = "Shortcut recording cancelled."
            refreshRows()
            return nil
        }

        if HotKeyShortcut.isModifierOnlyKeyCode(UInt32(event.keyCode)) {
            return nil
        }

        guard let shortcut = HotKeyShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        ) else {
            NSSound.beep()
            statusField.stringValue = "Include Command, Control, Option, or Shift with the key for \(action.displayName)."
            return nil
        }

        assignShortcut(shortcut, to: action)
        return nil
    }

    private func assignShortcut(_ shortcut: HotKeyShortcut, to action: HotKeyAction) {
        var reassignedFrom: HotKeyAction?
        for (otherAction, otherShortcut) in shortcuts where otherAction != action && otherShortcut == shortcut {
            shortcuts.removeValue(forKey: otherAction)
            reassignedFrom = otherAction
        }

        shortcuts[action] = shortcut
        activeRecordingAction = nil
        persistChanges()
        if let reassignedFrom {
            statusField.stringValue = "\(shortcut.displayString) saved for \(action.displayName); removed from \(reassignedFrom.displayName)."
        } else {
            statusField.stringValue = "\(shortcut.displayString) saved for \(action.displayName)."
        }
        refreshRows()
    }

    private func persistChanges() {
        store.save(shortcuts)
        onDidUpdateShortcuts?(shortcuts)
    }

    private func refreshRows() {
        for action in HotKeyAction.allCases {
            guard let row = rows[action] else {
                continue
            }

            if activeRecordingAction == action {
                row.recordButton.title = "Type Shortcut..."
                row.recordButton.state = .on
                row.recordButton.setAccessibilityLabel("Recording shortcut for \(action.displayName)")
            } else {
                row.recordButton.title = HotKeyFormatter.string(for: shortcuts[action])
                row.recordButton.state = .off
                row.recordButton.setAccessibilityLabel("Record shortcut for \(action.displayName), current \(row.recordButton.title)")
            }

            row.clearButton.isEnabled = shortcuts[action] != nil
        }
    }

    @objc
    private func handleRecordShortcut(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let action = HotKeyAction(rawValue: rawValue)
        else {
            return
        }

        if activeRecordingAction == action {
            activeRecordingAction = nil
            statusField.stringValue = "Shortcut recording cancelled."
        } else {
            activeRecordingAction = action
            statusField.stringValue = "Type a shortcut for \(action.displayName). Press Esc to cancel."
        }
        refreshRows()
    }

    @objc
    private func handleClearShortcut(_ sender: NSButton) {
        guard
            let rawValue = sender.identifier?.rawValue,
            let action = HotKeyAction(rawValue: rawValue)
        else {
            return
        }

        shortcuts.removeValue(forKey: action)
        activeRecordingAction = nil
        persistChanges()
        statusField.stringValue = "Shortcut cleared for \(action.displayName)."
        refreshRows()
    }

    @objc
    private func handleRestoreDefaults() {
        shortcuts = store.resetToDefaults()
        activeRecordingAction = nil
        onDidUpdateShortcuts?(shortcuts)
        statusField.stringValue = "Default shortcuts restored."
        refreshRows()
    }

    @objc
    private func handleDone() {
        activeRecordingAction = nil
        refreshRows()
        close()
    }

    @objc
    private func cancelRecordingForWindowChange() {
        guard activeRecordingAction != nil else {
            return
        }

        activeRecordingAction = nil
        statusField.stringValue = "Shortcut recording cancelled."
        refreshRows()
    }

    @objc
    private func handleWindowWillClose() {
        cancelRecordingForWindowChange()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
