@preconcurrency import AppKit
import Capture
import Editing
import Export
import FloatingShots
import Library
import MenuBar
import Shared

@MainActor
final class AppCoordinator: NSObject {
    private enum SystemSettingsDestination {
        case screenCapture
        case microphone

        var url: URL? {
            switch self {
            case .screenCapture:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            }
        }
    }

    private let permissionService: PermissionService
    private let shotStore: ShotStore
    private let recordingStore: RecordingStore
    private let captureService: CaptureService
    private let recordingService: RecordingService
    private let exportService: ExportService
    private let hotKeyService: GlobalHotKeyService
    private let hotKeyStore: HotKeyPreferencesStore
    private let floatingWindowCoordinator: FloatingWindowCoordinator
    private let menuBarController: MenuBarController
    private let clipboardImportService: ClipboardImportService
    private var annotationEditorControllers: [UUID: AnnotationEditorWindowController] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    private lazy var shotsBrowserWindowController: ShotsBrowserWindowController = {
        makeShotsBrowserWindowController()
    }()

    private func makeShotsBrowserWindowController() -> ShotsBrowserWindowController {
        let controller = ShotsBrowserWindowController(shotStore: shotStore)
        controller.delegate = self
        return controller
    }
    private lazy var settingsWindowController: SettingsWindowController = {
        makeSettingsWindowController()
    }()
    private lazy var recordingsBrowserWindowController = RecordingsBrowserWindowController(
        recordingStore: recordingStore
    )

    init(
        permissionService: PermissionService = PermissionService(),
        shotStore: ShotStore = ShotStore(),
        hotKeyService: GlobalHotKeyService = GlobalHotKeyService()
    ) {
        let menuBarController = MenuBarController()

        self.permissionService = permissionService
        self.shotStore = shotStore
        self.recordingStore = RecordingStore()
        self.captureService = CaptureService(
            permissionService: permissionService,
            shotStore: shotStore
        )
        self.recordingService = RecordingService(
            permissionService: permissionService,
            recordingStore: recordingStore
        )
        self.exportService = ExportService(shotStore: shotStore)
        self.hotKeyService = hotKeyService
        self.hotKeyStore = HotKeyPreferencesStore()
        self.floatingWindowCoordinator = FloatingWindowCoordinator(shotStore: shotStore)
        self.menuBarController = menuBarController
        self.clipboardImportService = ClipboardImportService(
            shotStore: shotStore,
            recordingStore: recordingStore
        )
        super.init()
        self.menuBarController.delegate = self
        self.recordingService.onStateChange = { [weak self] state in
            self?.updateRecordingMenu(for: state)
        }
        self.recordingService.onFinish = { [weak self] outputURL in
            self?.handleRecordingFinished(at: outputURL)
        }
        self.recordingService.onPause = { [weak self] _ in
            self?.recordingsBrowserWindowController.reloadRecordings()
        }
        self.recordingService.onError = { [weak self] error in
            self?.presentErrorAlert(message: "Recording failed.", detail: error.localizedDescription)
        }
        self.floatingWindowCoordinator.onAnnotateRequested = { [weak self] shotID in
            self?.annotateShot(withID: shotID)
        }
        self.floatingWindowCoordinator.onCopyImageRequested = { [weak self] shotID in
            self?.copyShot(withID: shotID)
        }
        self.floatingWindowCoordinator.onExportRequested = { [weak self] shotID in
            self?.exportShot(withID: shotID)
        }
        self.floatingWindowCoordinator.onRevealInFinderRequested = { [weak self] shotID in
            self?.revealShotInFinder(withID: shotID)
        }
        self.floatingWindowCoordinator.onDragFileURLRequested = { [weak self] shotID in
            self?.dragFileURL(for: shotID)
        }

        let center = NotificationCenter.default
        let didBecomeActiveObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }

        let shotStoreObserver = center.addObserver(
            forName: .shotStoreDidChange,
            object: shotStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFloatingShotsMenu()
            }
        }

        notificationObservers = [didBecomeActiveObserver, shotStoreObserver]
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        RuntimeTrace.log("app start")
        refreshPermissions()
        refreshFloatingShotsMenu()
        updateRecordingMenu(for: recordingService.state)
        restoreVisibleShotsOnLaunch()
        registerConfiguredHotKeys()
        if ProcessInfo.processInfo.environment["HOVERSHOT_DEBUG_OPEN_SHOTS_BROWSER"] == "1" {
            openShotsBrowser()
        }
        if ProcessInfo.processInfo.environment["HOVERSHOT_DEBUG_CREATE_DEMO_SHOT"] == "1" {
            createDemoShot()
        }
    }

    private func refreshPermissions() {
        menuBarController.setPermissionSnapshot(permissionService.currentSnapshot())
    }

    private func refreshFloatingShotsMenu() {
        let visibleShots = (try? shotStore.loadShots())?.filter { $0.floatingState.isVisible } ?? []
        let states = visibleShots.map {
                MenuBarController.FloatingShotMenuState(
                    id: $0.id,
                    title: $0.title,
                    ignoresMouseEvents: $0.floatingState.ignoresMouseEvents
                )
            }

        menuBarController.setFloatingShotStates(states)
    }

    private func createDemoShot() {
        do {
            let index = try shotStore.loadShots().count + 1
            let shot = try shotStore.createDemoShot(index: index)
            try floatingWindowCoordinator.present(shot)
            shotsBrowserWindowController.reloadShots()
        } catch {
            NSLog("Failed to create demo shot: \(error.localizedDescription)")
        }
    }

    private func restoreSavedShots() {
        do {
            try floatingWindowCoordinator.restoreAllShots()
        } catch {
            NSLog("Failed to restore shots: \(error.localizedDescription)")
        }
    }

    private func restoreVisibleShotsOnLaunch() {
        do {
            try floatingWindowCoordinator.restoreVisibleShots()
        } catch {
            NSLog("Failed to restore visible shots on launch: \(error.localizedDescription)")
        }
    }

    private func captureArea() {
        captureService.startInteractiveCapture { [weak self] result in
            self?.handleCaptureResult(result)
        }
    }

    private func captureWindow() {
        captureService.startWindowCapture { [weak self] result in
            self?.handleCaptureResult(result)
        }
    }

    private func recaptureLastArea() {
        captureService.recaptureLastArea { [weak self] result in
            self?.handleCaptureResult(result)
        }
    }

    private func captureArea(after delayInSeconds: Int) {
        captureService.startTimedInteractiveCapture(delayInSeconds: delayInSeconds) { [weak self] result in
            self?.handleCaptureResult(result)
        }
    }

    private func disableClickThroughForAllShots() {
        floatingWindowCoordinator.disableClickThroughForAllShots()
        shotsBrowserWindowController.reloadShots()
    }

    private func recordArea() {
        recordingService.startAreaRecording { [weak self] result in
            if case let .failure(error) = result,
               (error as? RecordingError) != .selectionCancelled {
                self?.presentOperationalError(message: "Could not start recording.", error: error)
            }
        }
    }

    private func recordWindow() {
        recordingService.startWindowRecording { [weak self] result in
            if case let .failure(error) = result,
               (error as? RecordingError) != .windowSelectionCancelled {
                self?.presentOperationalError(message: "Could not start recording.", error: error)
            }
        }
    }

    private func addRecordingEditMarker() {
        recordingService.addEditMarker { [weak self] result in
            switch result {
            case .success:
                self?.recordingsBrowserWindowController.reloadRecordings()
            case let .failure(error):
                self?.presentErrorAlert(message: "Could not add edit marker.", detail: error.localizedDescription)
            }
        }
    }

    private func stopRecording() {
        recordingService.stopRecording { [weak self] result in
            if case let .failure(error) = result {
                self?.presentErrorAlert(message: "Could not stop recording.", detail: error.localizedDescription)
            }
        }
    }

    private func pauseRecording() {
        recordingService.pauseRecording { [weak self] result in
            if case let .failure(error) = result {
                self?.presentErrorAlert(message: "Could not pause recording.", detail: error.localizedDescription)
            }
        }
    }

    private func resumeRecording() {
        recordingService.resumeRecording { [weak self] result in
            if case let .failure(error) = result {
                self?.presentErrorAlert(message: "Could not resume recording.", detail: error.localizedDescription)
            }
        }
    }

    private func annotateShot(withID shotID: UUID) {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            try presentAnnotationEditor(for: shot)
        } catch {
            presentErrorAlert(message: "Failed to open annotation editor.", detail: error.localizedDescription)
        }
    }

    private func copyShot(withID shotID: UUID) {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            try exportService.copyImage(for: shot)
        } catch {
            presentErrorAlert(message: "Failed to copy shot.", detail: error.localizedDescription)
        }
    }

    private func exportShot(withID shotID: UUID) {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            try exportService.exportInteractively(for: shot)
        } catch {
            presentErrorAlert(message: "Failed to export shot.", detail: error.localizedDescription)
        }
    }

    private func revealShotInFinder(withID shotID: UUID) {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            exportService.revealInFinder(for: shot)
        } catch {
            presentErrorAlert(message: "Failed to reveal shot.", detail: error.localizedDescription)
        }
    }

    private func dragFileURL(for shotID: UUID) -> URL? {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            return try exportService.dragFileURL(for: shot)
        } catch {
            NSLog("Failed to prepare drag file for shot \(shotID): \(error.localizedDescription)")
            return nil
        }
    }

    private func openShotsBrowser() {
        RuntimeTrace.log("openShotsBrowser begin existingVisible=\(shotsBrowserWindowController.window?.isVisible == true)")
        if shotsBrowserWindowController.window?.isVisible != true {
            shotsBrowserWindowController.close()
            shotsBrowserWindowController = makeShotsBrowserWindowController()
            RuntimeTrace.log("openShotsBrowser recreated controller")
        }

        shotsBrowserWindowController.present()
        RuntimeTrace.log("openShotsBrowser end windowVisible=\(shotsBrowserWindowController.window?.isVisible == true)")
    }

    private func openRecordingsBrowser() {
        recordingsBrowserWindowController.present()
        RuntimeTrace.log("openRecordingsBrowser end windowVisible=\(recordingsBrowserWindowController.window?.isVisible == true)")
    }

    private func openSettings() {
        settingsWindowController.present()
    }

    private func importFromClipboard() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await clipboardImportService.importFromClipboard()
                switch result {
                case let .shot(shot):
                    try floatingWindowCoordinator.present(shot)
                    shotsBrowserWindowController.reloadShots()
                case let .recording(url):
                    recordingsBrowserWindowController.reloadRecordings()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                presentErrorAlert(message: "Failed to import from clipboard.", detail: error.localizedDescription)
            }
        }
    }

    private func updateRecordingMenu(for state: RecordingState) {
        switch state {
        case .idle:
            menuBarController.setRecordingStatus(
                label: "Recording: Idle",
                canStart: true,
                canPause: false,
                canResume: false,
                canStop: false,
                canAddMarker: false
            )
        case .selectingArea:
            menuBarController.setRecordingStatus(
                label: "Recording: Select an area",
                canStart: false,
                canPause: false,
                canResume: false,
                canStop: false,
                canAddMarker: false
            )
        case let .starting(outputURL):
            menuBarController.setRecordingStatus(
                label: "Recording: Starting \(outputURL.lastPathComponent)",
                canStart: false,
                canPause: false,
                canResume: false,
                canStop: false,
                canAddMarker: false
            )
        case let .recording(outputURL):
            menuBarController.setRecordingStatus(
                label: "Recording: \(outputURL.lastPathComponent)",
                canStart: false,
                canPause: true,
                canResume: false,
                canStop: true,
                canAddMarker: true
            )
        case let .paused(prefix):
            menuBarController.setRecordingStatus(
                label: "Recording: Paused \(prefix)",
                canStart: false,
                canPause: false,
                canResume: true,
                canStop: true,
                canAddMarker: false
            )
        case let .stopping(outputURL):
            menuBarController.setRecordingStatus(
                label: "Recording: Finishing \(outputURL.lastPathComponent)",
                canStart: false,
                canPause: false,
                canResume: false,
                canStop: false,
                canAddMarker: false
            )
        }
    }

    private func handleRecordingFinished(at outputURL: URL) {
        recordingsBrowserWindowController.reloadRecordings()
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func presentAnnotationEditor(for shot: Shot) throws {
        if let existing = annotationEditorControllers[shot.id] {
            existing.present()
            return
        }

        guard let image = shotStore.loadImage(for: shot) else {
            throw ExportError.imageUnavailable
        }

        let controller = AnnotationEditorWindowController(shot: shot, baseImage: image)
        controller.onSave = { [weak self] shotID, annotations in
            self?.saveAnnotations(for: shotID, annotations: annotations)
        }
        controller.onClose = { [weak self] shotID in
            self?.annotationEditorControllers[shotID] = nil
        }
        annotationEditorControllers[shot.id] = controller
        controller.present()
    }

    private func saveAnnotations(for shotID: UUID, annotations: [ShotAnnotation]) {
        do {
            try shotStore.updateAnnotations(for: shotID, to: annotations)
            floatingWindowCoordinator.refreshShotIfPresented(withID: shotID)
            shotsBrowserWindowController.reloadShots()
        } catch {
            presentErrorAlert(message: "Failed to save annotations.", detail: error.localizedDescription)
        }
    }

    private func handleCaptureResult(_ result: Result<Shot, Error>) {
        switch result {
        case let .success(shot):
            do {
                try floatingWindowCoordinator.present(shot)
                shotsBrowserWindowController.reloadShots()
            } catch {
                presentErrorAlert(message: "Failed to show captured shot.", detail: error.localizedDescription)
            }
        case let .failure(error):
            guard let captureError = error as? CaptureError, captureError == .selectionCancelled else {
                presentOperationalError(message: "Capture failed.", error: error)
                return
            }
        }
    }

    private func presentOperationalError(message: String, error: Error) {
        if isScreenCapturePermissionError(error) {
            presentScreenCapturePermissionAlert()
            return
        }

        presentErrorAlert(message: message, detail: error.localizedDescription)
    }

    private func isScreenCapturePermissionError(_ error: Error) -> Bool {
        if let captureError = error as? CaptureError {
            return captureError == .screenRecordingPermissionRequired || captureError == .screenRecordingPermissionDenied
        }

        if let recordingError = error as? RecordingError {
            return recordingError == .screenRecordingPermissionRequired || recordingError == .screenRecordingPermissionDenied
        }

        return false
    }

    private func presentScreenCapturePermissionAlert() {
        let detail = """
        Allow HoverShot in System Settings > Privacy & Security > Screen Recording, then close and reopen the app.

        If you previously tested with `swift run`, grant permission to HoverShot.app instead of Terminal.
        """
        presentPermissionAlert(
            message: "Screen Recording Permission Needed",
            detail: detail,
            destination: .screenCapture
        )
    }

    private func presentErrorAlert(message: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    private func presentPermissionAlert(
        message: String,
        detail: String,
        destination: SystemSettingsDestination
    ) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings(destination)
        }
    }

    private func openSystemSettings(_ destination: SystemSettingsDestination) {
        if let url = destination.url, NSWorkspace.shared.open(url) {
            return
        }

        if let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            _ = NSWorkspace.shared.open(fallbackURL)
        }
    }

    private func makeSettingsWindowController() -> SettingsWindowController {
        let controller = SettingsWindowController(store: hotKeyStore)
        controller.onDidUpdateShortcuts = { [weak self] shortcuts in
            Task { @MainActor [weak self] in
                self?.applyHotKeys(shortcuts)
            }
        }
        return controller
    }

    private func registerConfiguredHotKeys() {
        applyHotKeys(hotKeyStore.load())
    }

    private func applyHotKeys(_ shortcuts: [HotKeyAction: HotKeyShortcut]) {
        hotKeyService.registerHotKeys(shortcuts) { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotKeyAction(action)
            }
        }
    }

    private func handleHotKeyAction(_ action: HotKeyAction) {
        switch action {
        case .captureArea:
            captureArea()
        case .captureWindow:
            captureWindow()
        case .recaptureLastArea:
            recaptureLastArea()
        case .timedCapture3Seconds:
            captureArea(after: 3)
        case .openShotsBrowser:
            openShotsBrowser()
        case .openRecordingsBrowser:
            openRecordingsBrowser()
        case .importFromClipboard:
            importFromClipboard()
        case .recordArea:
            recordArea()
        case .recordWindow:
            recordWindow()
        case .pauseRecording:
            pauseRecording()
        case .resumeRecording:
            resumeRecording()
        case .addEditMarker:
            addRecordingEditMarker()
        case .stopRecording:
            stopRecording()
        }
    }
}

extension AppCoordinator: MenuBarControllerDelegate {
    func menuBarController(_ controller: MenuBarController, didSelectBringShotToFrontWithID shotID: UUID) {
        do {
            let shot = try shotStore.loadShot(withID: shotID)
            try floatingWindowCoordinator.present(shot)
        } catch {
            presentErrorAlert(message: "Failed to bring shot to front.", detail: error.localizedDescription)
        }
    }

    func menuBarController(_ controller: MenuBarController, didSelectToggleIgnoreMouseClicksForShotWithID shotID: UUID) {
        do {
            var shot = try shotStore.loadShot(withID: shotID)
            shot.floatingState.ignoresMouseEvents.toggle()
            try shotStore.upsert(shot)
            floatingWindowCoordinator.refreshShotIfPresented(withID: shotID)
        } catch {
            presentErrorAlert(message: "Failed to update shot interaction mode.", detail: error.localizedDescription)
        }
    }

    func menuBarControllerDidSelectOpenSettings(_ controller: MenuBarController) {
        openSettings()
    }

    func menuBarControllerDidSelectOpenShotsBrowser(_ controller: MenuBarController) {
        openShotsBrowser()
    }

    func menuBarControllerDidSelectOpenRecordingsBrowser(_ controller: MenuBarController) {
        openRecordingsBrowser()
    }

    func menuBarControllerDidSelectImportFromClipboard(_ controller: MenuBarController) {
        importFromClipboard()
    }

    func menuBarControllerDidSelectCaptureArea(_ controller: MenuBarController) {
        captureArea()
    }

    func menuBarControllerDidSelectCaptureWindow(_ controller: MenuBarController) {
        captureWindow()
    }

    func menuBarControllerDidSelectRecaptureLastArea(_ controller: MenuBarController) {
        recaptureLastArea()
    }

    func menuBarController(_ controller: MenuBarController, didSelectTimedCaptureWithDelay delayInSeconds: Int) {
        captureArea(after: delayInSeconds)
    }

    func menuBarControllerDidSelectRecordArea(_ controller: MenuBarController) {
        recordArea()
    }

    func menuBarControllerDidSelectRecordWindow(_ controller: MenuBarController) {
        recordWindow()
    }

    func menuBarControllerDidSelectPauseRecording(_ controller: MenuBarController) {
        pauseRecording()
    }

    func menuBarControllerDidSelectResumeRecording(_ controller: MenuBarController) {
        resumeRecording()
    }

    func menuBarControllerDidSelectStopRecording(_ controller: MenuBarController) {
        stopRecording()
    }

    func menuBarControllerDidSelectAddEditMarker(_ controller: MenuBarController) {
        addRecordingEditMarker()
    }

    func menuBarControllerDidSelectCreateDemoShot(_ controller: MenuBarController) {
        createDemoShot()
    }

    func menuBarControllerDidSelectRestoreShots(_ controller: MenuBarController) {
        restoreSavedShots()
    }

    func menuBarControllerDidSelectDisableClickThrough(_ controller: MenuBarController) {
        disableClickThroughForAllShots()
    }

    func menuBarControllerDidSelectRequestScreenCapturePermission(_ controller: MenuBarController) {
        switch permissionService.currentSnapshot().screenCapture {
        case .authorized:
            refreshPermissions()
        case .notDetermined:
            _ = permissionService.requestScreenCaptureAccess()
            presentScreenCapturePermissionAlert()
            refreshPermissions()
        case .denied:
            presentScreenCapturePermissionAlert()
            refreshPermissions()
        }
    }

    func menuBarControllerDidSelectRequestMicrophonePermission(_ controller: MenuBarController) {
        permissionService.requestMicrophoneAccess { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    func menuBarControllerDidSelectOpenScreenCaptureSettings(_ controller: MenuBarController) {
        openSystemSettings(.screenCapture)
    }

    func menuBarControllerDidSelectOpenMicrophoneSettings(_ controller: MenuBarController) {
        openSystemSettings(.microphone)
    }

    func menuBarControllerDidSelectQuit(_ controller: MenuBarController) {
        NSApp.terminate(nil)
    }
}

extension AppCoordinator: ShotsBrowserWindowControllerDelegate {
    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestOpen shot: Shot
    ) {
        do {
            try floatingWindowCoordinator.present(shot)
            controller.reloadShots()
        } catch {
            presentErrorAlert(message: "Failed to open shot.", detail: error.localizedDescription)
        }
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestAnnotate shot: Shot
    ) {
        do {
            try presentAnnotationEditor(for: shot)
        } catch {
            presentErrorAlert(message: "Failed to open annotation editor.", detail: error.localizedDescription)
        }
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestCopy shot: Shot
    ) throws {
        try exportService.copyImage(for: shot)
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestExport shot: Shot
    ) throws {
        try exportService.exportInteractively(for: shot)
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestRevealInFinder shot: Shot
    ) {
        exportService.revealInFinder(for: shot)
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestDelete shot: Shot
    ) throws {
        floatingWindowCoordinator.closeShot(withID: shot.id)
        _ = try shotStore.deleteShot(withID: shot.id)
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestDelete shots: [Shot]
    ) throws {
        for shot in shots {
            try shotsBrowserWindowController(controller, didRequestDelete: shot)
        }
    }

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestUpdateMetadataFor shot: Shot,
        title: String,
        notes: String?,
        tags: [String],
        isFavorite: Bool
    ) throws {
        try shotStore.updateMetadata(
            for: shot.id,
            title: title,
            notes: notes,
            tags: tags,
            isFavorite: isFavorite
        )
    }
}
