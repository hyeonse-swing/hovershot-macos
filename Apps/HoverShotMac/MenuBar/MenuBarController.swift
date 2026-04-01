@preconcurrency import AppKit
import Shared

@MainActor
public protocol MenuBarControllerDelegate: AnyObject {
    func menuBarController(_ controller: MenuBarController, didSelectBringShotToFrontWithID shotID: UUID)
    func menuBarController(_ controller: MenuBarController, didSelectToggleIgnoreMouseClicksForShotWithID shotID: UUID)
    func menuBarControllerDidSelectOpenSettings(_ controller: MenuBarController)
    func menuBarControllerDidSelectOpenShotsBrowser(_ controller: MenuBarController)
    func menuBarControllerDidSelectOpenRecordingsBrowser(_ controller: MenuBarController)
    func menuBarControllerDidSelectCaptureArea(_ controller: MenuBarController)
    func menuBarControllerDidSelectCaptureWindow(_ controller: MenuBarController)
    func menuBarControllerDidSelectRecaptureLastArea(_ controller: MenuBarController)
    func menuBarController(_ controller: MenuBarController, didSelectTimedCaptureWithDelay delayInSeconds: Int)
    func menuBarControllerDidSelectImportFromClipboard(_ controller: MenuBarController)
    func menuBarControllerDidSelectRecordArea(_ controller: MenuBarController)
    func menuBarControllerDidSelectRecordWindow(_ controller: MenuBarController)
    func menuBarControllerDidSelectPauseRecording(_ controller: MenuBarController)
    func menuBarControllerDidSelectResumeRecording(_ controller: MenuBarController)
    func menuBarControllerDidSelectAddEditMarker(_ controller: MenuBarController)
    func menuBarControllerDidSelectStopRecording(_ controller: MenuBarController)
    func menuBarControllerDidSelectCreateDemoShot(_ controller: MenuBarController)
    func menuBarControllerDidSelectRestoreShots(_ controller: MenuBarController)
    func menuBarControllerDidSelectDisableClickThrough(_ controller: MenuBarController)
    func menuBarControllerDidSelectRequestScreenCapturePermission(_ controller: MenuBarController)
    func menuBarControllerDidSelectRequestMicrophonePermission(_ controller: MenuBarController)
    func menuBarControllerDidSelectOpenScreenCaptureSettings(_ controller: MenuBarController)
    func menuBarControllerDidSelectOpenMicrophoneSettings(_ controller: MenuBarController)
    func menuBarControllerDidSelectQuit(_ controller: MenuBarController)
}

@MainActor
public final class MenuBarController: NSObject {
    public struct FloatingShotMenuState {
        public let id: UUID
        public let title: String
        public let ignoresMouseEvents: Bool

        public init(id: UUID, title: String, ignoresMouseEvents: Bool) {
            self.id = id
            self.title = title
            self.ignoresMouseEvents = ignoresMouseEvents
        }
    }

    public weak var delegate: MenuBarControllerDelegate?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let screenPermissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let microphonePermissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let floatingShotsItem = NSMenuItem(title: "Floating Shots", action: nil, keyEquivalent: "")
    private let floatingShotsMenu = NSMenu(title: "Floating Shots")
    private let recordingStatusItem = NSMenuItem(title: "Recording: Idle", action: nil, keyEquivalent: "")
    private let recordAreaItem = NSMenuItem(title: "Record Area", action: nil, keyEquivalent: "")
    private let recordWindowItem = NSMenuItem(title: "Record Window", action: nil, keyEquivalent: "")
    private let pauseRecordingItem = NSMenuItem(title: "Pause Recording", action: nil, keyEquivalent: "")
    private let resumeRecordingItem = NSMenuItem(title: "Resume Recording", action: nil, keyEquivalent: "")
    private let addEditMarkerItem = NSMenuItem(title: "Add Edit Marker", action: nil, keyEquivalent: "")
    private let stopRecordingItem = NSMenuItem(title: "Stop Recording", action: nil, keyEquivalent: "")

    public override init() {
        super.init()
        configureStatusItem()
        configureMenu()
    }

    public func setPermissionSnapshot(_ snapshot: PermissionSnapshot) {
        screenPermissionItem.title = "Screen Recording: \(label(for: snapshot.screenCapture))"
        microphonePermissionItem.title = "Microphone: \(label(for: snapshot.microphone))"
    }

    public func setRecordingStatus(
        label: String,
        canStart: Bool,
        canPause: Bool,
        canResume: Bool,
        canStop: Bool,
        canAddMarker: Bool
    ) {
        recordingStatusItem.title = label
        recordAreaItem.isEnabled = canStart
        recordWindowItem.isEnabled = canStart
        pauseRecordingItem.isEnabled = canPause
        resumeRecordingItem.isEnabled = canResume
        addEditMarkerItem.isEnabled = canAddMarker
        stopRecordingItem.isEnabled = canStop
    }

    public func setFloatingShotStates(_ states: [FloatingShotMenuState]) {
        floatingShotsMenu.removeAllItems()

        guard states.isEmpty == false else {
            let emptyItem = NSMenuItem(title: "No Floating Shots", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            floatingShotsMenu.addItem(emptyItem)
            floatingShotsItem.isEnabled = false
            return
        }

        floatingShotsItem.isEnabled = true

        for state in states.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            let shotItem = NSMenuItem(title: state.title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: state.title)

            let bringToFrontItem = NSMenuItem(
                title: "Bring to Front",
                action: #selector(handleBringShotToFront(_:)),
                keyEquivalent: ""
            )
            bringToFrontItem.target = self
            bringToFrontItem.representedObject = state.id
            submenu.addItem(bringToFrontItem)

            let ignoreItem = NSMenuItem(
                title: "Ignore Mouse Clicks",
                action: #selector(handleToggleIgnoreMouseClicksForShot(_:)),
                keyEquivalent: ""
            )
            ignoreItem.target = self
            ignoreItem.representedObject = state.id
            ignoreItem.state = state.ignoresMouseEvents ? .on : .off
            submenu.addItem(ignoreItem)

            shotItem.submenu = submenu
            floatingShotsMenu.addItem(shotItem)
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle.angled", accessibilityDescription: "HoverShot")
            button.imagePosition = .imageOnly
        }
    }

    private func configureMenu() {
        menu.autoenablesItems = false

        menu.addItem(makeItem(
            title: "Settings...",
            action: #selector(handleOpenSettings)
        ))
        menu.addItem(makeItem(
            title: "Open Shots Browser",
            action: #selector(handleOpenShotsBrowser)
        ))
        menu.addItem(makeItem(
            title: "Open Recordings Browser",
            action: #selector(handleOpenRecordingsBrowser)
        ))
        menu.addItem(makeItem(
            title: "Import From Clipboard",
            action: #selector(handleImportFromClipboard)
        ))
        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: "Capture Area",
            action: #selector(handleCaptureArea)
        ))
        menu.addItem(makeItem(
            title: "Capture Window",
            action: #selector(handleCaptureWindow)
        ))
        menu.addItem(makeItem(
            title: "Re-capture Last Area",
            action: #selector(handleRecaptureLastArea)
        ))
        menu.addItem(makeTimedCaptureMenuItem())
        menu.addItem(.separator())
        recordingStatusItem.isEnabled = false
        menu.addItem(recordingStatusItem)
        recordAreaItem.target = self
        recordAreaItem.action = #selector(handleRecordArea)
        menu.addItem(recordAreaItem)
        recordWindowItem.target = self
        recordWindowItem.action = #selector(handleRecordWindow)
        menu.addItem(recordWindowItem)
        pauseRecordingItem.target = self
        pauseRecordingItem.action = #selector(handlePauseRecording)
        pauseRecordingItem.isEnabled = false
        menu.addItem(pauseRecordingItem)
        resumeRecordingItem.target = self
        resumeRecordingItem.action = #selector(handleResumeRecording)
        resumeRecordingItem.isEnabled = false
        menu.addItem(resumeRecordingItem)
        addEditMarkerItem.target = self
        addEditMarkerItem.action = #selector(handleAddEditMarker)
        addEditMarkerItem.isEnabled = false
        menu.addItem(addEditMarkerItem)
        stopRecordingItem.target = self
        stopRecordingItem.action = #selector(handleStopRecording)
        stopRecordingItem.isEnabled = false
        menu.addItem(stopRecordingItem)
        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: "Create Demo Shot",
            action: #selector(handleCreateDemoShot)
        ))
        menu.addItem(makeItem(
            title: "Restore Saved Shots",
            action: #selector(handleRestoreShots)
        ))
        menu.addItem(makeItem(
            title: "Disable Click-Through on All Shots",
            action: #selector(handleDisableClickThrough)
        ))
        floatingShotsItem.submenu = floatingShotsMenu
        floatingShotsItem.isEnabled = false
        menu.addItem(floatingShotsItem)

        menu.addItem(.separator())

        screenPermissionItem.isEnabled = false
        microphonePermissionItem.isEnabled = false
        menu.addItem(screenPermissionItem)
        menu.addItem(makeItem(
            title: "Request Screen Recording Permission",
            action: #selector(handleRequestScreenCapturePermission)
        ))
        menu.addItem(makeItem(
            title: "Open Screen Recording Settings",
            action: #selector(handleOpenScreenCaptureSettings)
        ))
        menu.addItem(microphonePermissionItem)
        menu.addItem(makeItem(
            title: "Request Microphone Permission",
            action: #selector(handleRequestMicrophonePermission)
        ))
        menu.addItem(makeItem(
            title: "Open Microphone Settings",
            action: #selector(handleOpenMicrophoneSettings)
        ))

        menu.addItem(.separator())
        menu.addItem(makeItem(
            title: "Quit",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    private func makeItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func makeTimedCaptureMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Timed Capture", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Timed Capture")

        [3, 5, 10].forEach { delay in
            let menuItem = NSMenuItem(
                title: "\(delay) Seconds",
                action: #selector(handleTimedCapture(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.tag = delay
            submenu.addItem(menuItem)
        }

        item.submenu = submenu
        return item
    }

    private func label(for state: AppPermissionState) -> String {
        switch state {
        case .notDetermined:
            return "Not Requested"
        case .denied:
            return "Denied"
        case .authorized:
            return "Granted"
        }
    }

    @objc
    private func handleBringShotToFront(_ sender: NSMenuItem) {
        guard let shotID = sender.representedObject as? UUID else {
            return
        }

        delegate?.menuBarController(self, didSelectBringShotToFrontWithID: shotID)
    }

    @objc
    private func handleToggleIgnoreMouseClicksForShot(_ sender: NSMenuItem) {
        guard let shotID = sender.representedObject as? UUID else {
            return
        }

        delegate?.menuBarController(self, didSelectToggleIgnoreMouseClicksForShotWithID: shotID)
    }

    @objc
    private func handleOpenShotsBrowser() {
        RuntimeTrace.log("menu action open shots browser")
        delegate?.menuBarControllerDidSelectOpenShotsBrowser(self)
    }

    @objc
    private func handleOpenSettings() {
        delegate?.menuBarControllerDidSelectOpenSettings(self)
    }

    @objc
    private func handleOpenRecordingsBrowser() {
        RuntimeTrace.log("menu action open recordings browser")
        delegate?.menuBarControllerDidSelectOpenRecordingsBrowser(self)
    }

    @objc
    private func handleImportFromClipboard() {
        delegate?.menuBarControllerDidSelectImportFromClipboard(self)
    }

    @objc
    private func handleCaptureArea() {
        delegate?.menuBarControllerDidSelectCaptureArea(self)
    }

    @objc
    private func handleCaptureWindow() {
        delegate?.menuBarControllerDidSelectCaptureWindow(self)
    }

    @objc
    private func handleRecaptureLastArea() {
        delegate?.menuBarControllerDidSelectRecaptureLastArea(self)
    }

    @objc
    private func handleTimedCapture(_ sender: NSMenuItem) {
        delegate?.menuBarController(self, didSelectTimedCaptureWithDelay: sender.tag)
    }

    @objc
    private func handleRecordArea() {
        delegate?.menuBarControllerDidSelectRecordArea(self)
    }

    @objc
    private func handleRecordWindow() {
        delegate?.menuBarControllerDidSelectRecordWindow(self)
    }

    @objc
    private func handlePauseRecording() {
        delegate?.menuBarControllerDidSelectPauseRecording(self)
    }

    @objc
    private func handleResumeRecording() {
        delegate?.menuBarControllerDidSelectResumeRecording(self)
    }

    @objc
    private func handleAddEditMarker() {
        delegate?.menuBarControllerDidSelectAddEditMarker(self)
    }

    @objc
    private func handleStopRecording() {
        delegate?.menuBarControllerDidSelectStopRecording(self)
    }

    @objc
    private func handleCreateDemoShot() {
        delegate?.menuBarControllerDidSelectCreateDemoShot(self)
    }

    @objc
    private func handleRestoreShots() {
        delegate?.menuBarControllerDidSelectRestoreShots(self)
    }

    @objc
    private func handleDisableClickThrough() {
        delegate?.menuBarControllerDidSelectDisableClickThrough(self)
    }

    @objc
    private func handleRequestScreenCapturePermission() {
        delegate?.menuBarControllerDidSelectRequestScreenCapturePermission(self)
    }

    @objc
    private func handleRequestMicrophonePermission() {
        delegate?.menuBarControllerDidSelectRequestMicrophonePermission(self)
    }

    @objc
    private func handleOpenScreenCaptureSettings() {
        delegate?.menuBarControllerDidSelectOpenScreenCaptureSettings(self)
    }

    @objc
    private func handleOpenMicrophoneSettings() {
        delegate?.menuBarControllerDidSelectOpenMicrophoneSettings(self)
    }

    @objc
    private func handleQuit() {
        delegate?.menuBarControllerDidSelectQuit(self)
    }
}
