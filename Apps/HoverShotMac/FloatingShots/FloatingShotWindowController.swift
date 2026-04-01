@preconcurrency import AppKit
import Library

final class FloatingShotWindowController: NSWindowController {
    private enum MenuItemID {
        static let fitToScreen = NSUserInterfaceItemIdentifier("fit-to-screen")
        static let resetSize = NSUserInterfaceItemIdentifier("reset-size")
        static let visibilityEverywhere = NSUserInterfaceItemIdentifier("visibility-everywhere")
        static let visibilityCurrentSpace = NSUserInterfaceItemIdentifier("visibility-current-space")
        static let visibilityCurrentApp = NSUserInterfaceItemIdentifier("visibility-current-app")
        static let ignoreMouseClicks = NSUserInterfaceItemIdentifier("ignore-mouse-clicks")
        static let opacitySubmenu = NSUserInterfaceItemIdentifier("opacity-submenu")
    }

    private enum Layout {
        static let horizontalChrome: CGFloat = 24
        static let verticalChrome: CGFloat = 74
        static let outerMargin: CGFloat = 40
        static let maxWidthRatio: CGFloat = 0.36
        static let maxHeightRatio: CGFloat = 0.55
        static let maxWidthCap: CGFloat = 820
        static let maxHeightCap: CGFloat = 760
        static let minimumImageWidth: CGFloat = 48
        static let minimumImageHeight: CGFloat = 48
    }

    let shotID: UUID

    var onStateChange: ((UUID, FloatingShotState) -> Void)?
    var onAnnotateRequested: ((UUID) -> Void)?
    var onCopyImageRequested: ((UUID) -> Void)?
    var onExportRequested: ((UUID) -> Void)?
    var onRevealInFinderRequested: ((UUID) -> Void)?
    var onDragFileURLRequested: ((UUID) -> URL?)?

    private let contentView = FloatingShotContentView()
    private var imageSize: NSSize
    private var state: FloatingShotState
    private var windowObservers: [NSObjectProtocol] = []
    private var localScrollMonitor: Any?

    init(shot: Shot, image: NSImage) {
        self.shotID = shot.id
        self.imageSize = image.size
        self.state = shot.floatingState

        let initialFrame = shot.floatingState.frame?.cgRect
            ?? Self.defaultInitialFrame(for: image.size)

        let panel = FloatingShotPanel(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = Self.collectionBehavior(for: shot.floatingState.visibilityMode)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.alphaValue = shot.floatingState.opacity
        panel.ignoresMouseEvents = shot.floatingState.ignoresMouseEvents
        panel.contentMinSize = NSSize(width: 160, height: 220)

        super.init(window: panel)

        panel.onCopyRequested = { [weak self] in
            guard let self else {
                return
            }

            self.onCopyImageRequested?(self.shotID)
        }

        contentView.titleField.stringValue = shot.title
        contentView.imageView.image = image
        contentView.imageView.draggingPasteboardWriterProvider = { [weak self] in
            guard let url = self?.onDragFileURLRequested?(shot.id) else {
                return nil
            }

            return url as NSURL
        }

        panel.contentView = contentView
        configureSizing(for: panel, imageSize: image.size)
        clampWindowFrameToVisibleScreen(for: panel, animated: false)
        refreshContextMenus()
        installWindowObservers(for: panel)
        installScrollMonitor(for: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func reveal() {
        window?.setFrameAutosaveName("shot-\(shotID.uuidString)")
        if let window {
            clampWindowFrameToVisibleScreen(for: window, animated: false)
        }
        showWindow(nil)
        window?.orderFrontRegardless()
    }

    func update(shot: Shot, image: NSImage) {
        imageSize = image.size
        state = shot.floatingState
        contentView.titleField.stringValue = shot.title
        contentView.imageView.image = image
        if let window {
            configureSizing(for: window, imageSize: image.size)
            clampWindowFrameToVisibleScreen(for: window, animated: false)
        }
        applyStateToWindow()
        refreshContextMenus()
    }

    func disableClickThrough() {
        guard state.ignoresMouseEvents else {
            return
        }

        state.ignoresMouseEvents = false
        applyStateToWindow()
        persistState()
        refreshContextMenus()
    }

    private func adjustOpacity(by delta: Double) {
        state.opacity = min(max(state.opacity + delta, 0.25), 1.0)
        applyStateToWindow()
        persistState()
    }

    private func persistCurrentFrame() {
        guard let frame = window?.frame else {
            return
        }

        state.frame = ShotRect(frame)
        persistState()
    }

    private func persistState() {
        onStateChange?(shotID, state)
    }

    private func applyStateToWindow() {
        window?.alphaValue = state.opacity
        window?.ignoresMouseEvents = state.ignoresMouseEvents
        window?.collectionBehavior = Self.collectionBehavior(for: state.visibilityMode)
    }

    private func refreshContextMenus() {
        contentView.menu = makeContextMenu()
        contentView.imageView.menu = makeContextMenu()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Image", action: #selector(handleCopyImage), keyEquivalent: "")
        menu.addItem(withTitle: "Export…", action: #selector(handleExport), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(handleRevealInFinder), keyEquivalent: "")
        menu.addItem(withTitle: "Annotate…", action: #selector(handleAnnotate), keyEquivalent: "")
        menu.addItem(.separator())
        let fitToScreenItem = NSMenuItem(title: "Fit to Screen", action: #selector(handleFitToScreen), keyEquivalent: "")
        fitToScreenItem.identifier = MenuItemID.fitToScreen
        menu.addItem(fitToScreenItem)
        let resetSizeItem = NSMenuItem(title: "Reset Size", action: #selector(handleResetSize), keyEquivalent: "")
        resetSizeItem.identifier = MenuItemID.resetSize
        menu.addItem(resetSizeItem)
        menu.addItem(.separator())
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.identifier = MenuItemID.opacitySubmenu
        opacityItem.submenu = makeOpacitySubmenu()
        menu.addItem(opacityItem)
        let everywhereItem = NSMenuItem(title: "Everywhere", action: #selector(handleSetEverywhere), keyEquivalent: "")
        everywhereItem.identifier = MenuItemID.visibilityEverywhere
        everywhereItem.state = state.visibilityMode == .everywhere ? .on : .off
        menu.addItem(everywhereItem)
        let currentSpaceItem = NSMenuItem(title: "Current Space", action: #selector(handleSetCurrentSpace), keyEquivalent: "")
        currentSpaceItem.identifier = MenuItemID.visibilityCurrentSpace
        currentSpaceItem.state = state.visibilityMode == .currentSpace ? .on : .off
        menu.addItem(currentSpaceItem)
        let currentAppItem = NSMenuItem(title: "Current App", action: #selector(handleSetCurrentApp), keyEquivalent: "")
        currentAppItem.identifier = MenuItemID.visibilityCurrentApp
        currentAppItem.state = state.visibilityMode == .currentApp ? .on : .off
        menu.addItem(currentAppItem)
        menu.addItem(.separator())
        let ignoreClicksItem = NSMenuItem(title: "Ignore Mouse Clicks", action: #selector(handleToggleIgnoreMouseClicks), keyEquivalent: "")
        ignoreClicksItem.identifier = MenuItemID.ignoreMouseClicks
        ignoreClicksItem.state = state.ignoresMouseEvents ? .on : .off
        menu.addItem(ignoreClicksItem)
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc
    nonisolated private func handleCopyImage() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.onCopyImageRequested?(self.shotID)
        }
    }

    @objc
    nonisolated private func handleExport() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.onExportRequested?(self.shotID)
        }
    }

    @objc
    nonisolated private func handleRevealInFinder() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.onRevealInFinderRequested?(self.shotID)
        }
    }

    @objc
    nonisolated private func handleAnnotate() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.onAnnotateRequested?(self.shotID)
        }
    }

    @objc
    nonisolated private func handleSetEverywhere() {
        Task { @MainActor [weak self] in
            self?.setVisibilityMode(.everywhere)
        }
    }

    @objc
    nonisolated private func handleSetCurrentSpace() {
        Task { @MainActor [weak self] in
            self?.setVisibilityMode(.currentSpace)
        }
    }

    @objc
    nonisolated private func handleSetCurrentApp() {
        Task { @MainActor [weak self] in
            self?.setVisibilityMode(.currentApp)
        }
    }

    @objc
    nonisolated private func handleToggleIgnoreMouseClicks() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.state.ignoresMouseEvents.toggle()
            self.applyStateToWindow()
            self.persistState()
            self.refreshContextMenus()
        }
    }

    @objc
    nonisolated private func handleSetOpacity(_ sender: NSMenuItem) {
        let opacity = Double(sender.tag) / 100
        Task { @MainActor [weak self] in
            self?.setOpacity(opacity)
        }
    }

    @objc
    nonisolated private func handleFitToScreen() {
        Task { @MainActor [weak self] in
            self?.fitWindowToVisibleScreen()
        }
    }

    @objc
    nonisolated private func handleResetSize() {
        Task { @MainActor [weak self] in
            self?.resetWindowToDefaultSize()
        }
    }

    private func setVisibilityMode(_ mode: ShotVisibilityMode) {
        state.visibilityMode = mode
        applyStateToWindow()
        persistState()
        refreshContextMenus()
    }

    private func setOpacity(_ opacity: Double) {
        state.opacity = min(max(opacity, 0.25), 1.0)
        applyStateToWindow()
        persistState()
        refreshContextMenus()
    }

    private func makeOpacitySubmenu() -> NSMenu {
        let submenu = NSMenu(title: "Opacity")
        submenu.identifier = MenuItemID.opacitySubmenu

        [100, 90, 75, 60, 45, 30].forEach { percent in
            let item = NSMenuItem(
                title: "\(percent)%",
                action: #selector(handleSetOpacity(_:)),
                keyEquivalent: ""
            )
            item.tag = percent
            item.target = self
            item.state = Int((state.opacity * 100).rounded()) == percent ? .on : .off
            submenu.addItem(item)
        }

        return submenu
    }

    private func installWindowObservers(for window: NSWindow) {
        let center = NotificationCenter.default

        let moveObserver = center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistCurrentFrame()
            }
        }

        let resizeObserver = center.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistCurrentFrame()
            }
        }

        let changeScreenObserver = center.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else {
                    return
                }

                self.clampWindowFrameToVisibleScreen(for: window, animated: true)
                self.persistCurrentFrame()
            }
        }

        let closeObserver = center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.state.isVisible = false
                self.persistState()
                self.removeScrollMonitor()
                self.removeWindowObservers()
            }
        }

        windowObservers = [moveObserver, resizeObserver, changeScreenObserver, closeObserver]
    }

    private func installScrollMonitor(for window: NSWindow) {
        removeScrollMonitor()

        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak window] event in
            guard
                let self,
                let window,
                event.window === window,
                window.isVisible,
                window.ignoresMouseEvents == false
            else {
                return event
            }

            self.adjustOpacity(by: event.scrollingDeltaY * -0.01)
            return event
        }
    }

    private func removeScrollMonitor() {
        guard let localScrollMonitor else {
            return
        }

        NSEvent.removeMonitor(localScrollMonitor)
        self.localScrollMonitor = nil
    }

    private func removeWindowObservers() {
        let center = NotificationCenter.default
        windowObservers.forEach(center.removeObserver)
        windowObservers.removeAll()
    }

    private static func collectionBehavior(for mode: ShotVisibilityMode) -> NSWindow.CollectionBehavior {
        switch mode {
        case .everywhere:
            return [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .currentSpace:
            return [.fullScreenAuxiliary]
        case .currentApp:
            return [.moveToActiveSpace, .fullScreenAuxiliary]
        }
    }

    private static func defaultInitialFrame(for imageSize: NSSize) -> CGRect {
        let placementScreen = preferredPlacementScreen()
        let visibleFrame = placementScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 160, y: 160, width: 1440, height: 900)
        let maxImageWidth = min(visibleFrame.width * Layout.maxWidthRatio, Layout.maxWidthCap)
        let maxImageHeight = min(visibleFrame.height * Layout.maxHeightRatio, Layout.maxHeightCap)

        let fittedImageSize = fittedImageSize(
            imageSize,
            maxSize: NSSize(width: maxImageWidth, height: maxImageHeight)
        )

        let windowWidth = fittedImageSize.width + Layout.horizontalChrome
        let windowHeight = fittedImageSize.height + Layout.verticalChrome
        let origin = CGPoint(
            x: min(visibleFrame.minX + Layout.outerMargin, max(visibleFrame.maxX - windowWidth - Layout.outerMargin, visibleFrame.minX + 16)),
            y: max(visibleFrame.maxY - windowHeight - Layout.outerMargin, visibleFrame.minY + 16)
        )

        return CGRect(origin: origin, size: NSSize(width: windowWidth, height: windowHeight)).integral
    }

    private static func fittedImageSize(
        _ imageSize: NSSize,
        maxSize: NSSize
    ) -> NSSize {
        let baseWidth = max(imageSize.width, 1)
        let baseHeight = max(imageSize.height, 1)
        let widthScale = maxSize.width / baseWidth
        let heightScale = maxSize.height / baseHeight
        let scale = min(widthScale, heightScale, 1)

        return NSSize(
            width: max((baseWidth * scale).rounded(), Layout.minimumImageWidth),
            height: max((baseHeight * scale).rounded(), Layout.minimumImageHeight)
        )
    }

    private static func preferredPlacementScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.visibleFrame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func configureSizing(for window: NSWindow, imageSize: NSSize) {
        let safeImageSize = NSSize(
            width: max(imageSize.width, 1),
            height: max(imageSize.height, 1)
        )

        window.contentAspectRatio = safeImageSize
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.contentMinSize = NSSize(
            width: 96,
            height: 120
        )
    }

    private func fitWindowToVisibleScreen() {
        guard let window else {
            return
        }

        let targetFrame = Self.fitToScreenFrame(
            for: imageSize,
            anchoredAt: window.frame,
            on: window.screen ?? Self.preferredPlacementScreen()
        )
        window.setFrame(targetFrame, display: true, animate: true)
        persistCurrentFrame()
    }

    private func resetWindowToDefaultSize() {
        guard let window else {
            return
        }

        let targetFrame = Self.defaultInitialFrame(for: imageSize)
        window.setFrame(targetFrame, display: true, animate: true)
        persistCurrentFrame()
    }

    private func clampWindowFrameToVisibleScreen(for window: NSWindow, animated: Bool) {
        let fittedFrame = Self.fittedFrame(
            for: imageSize,
            from: window.frame,
            on: window.screen ?? Self.preferredPlacementScreen()
        )
        guard window.frame.integral != fittedFrame.integral else {
            return
        }

        window.setFrame(fittedFrame, display: true, animate: animated)
    }

    private static func fittedFrame(
        for imageSize: NSSize,
        from currentFrame: CGRect,
        on screen: NSScreen?
    ) -> CGRect {
        let visibleFrame = screen?.visibleFrame
            ?? preferredPlacementScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 160, y: 160, width: 1440, height: 900)

        let maxContentWidth = max(visibleFrame.width - Layout.horizontalChrome - (Layout.outerMargin * 2), Layout.minimumImageWidth)
        let maxContentHeight = max(visibleFrame.height - Layout.verticalChrome - (Layout.outerMargin * 2), Layout.minimumImageHeight)

        let availableSize = NSSize(width: maxContentWidth, height: maxContentHeight)
        let currentContentSize = NSSize(
            width: max(currentFrame.width - Layout.horizontalChrome, 1),
            height: max(currentFrame.height - Layout.verticalChrome, 1)
        )

        let clampedContentSize = fittedImageSize(currentContentSize, maxSize: availableSize)
        let clampedWindowSize = NSSize(
            width: clampedContentSize.width + Layout.horizontalChrome,
            height: clampedContentSize.height + Layout.verticalChrome
        )

        let desiredOrigin = CGPoint(
            x: min(
                max(currentFrame.minX, visibleFrame.minX + 16),
                max(visibleFrame.maxX - clampedWindowSize.width - 16, visibleFrame.minX + 16)
            ),
            y: min(
                max(currentFrame.minY, visibleFrame.minY + 16),
                max(visibleFrame.maxY - clampedWindowSize.height - 16, visibleFrame.minY + 16)
            )
        )

        let normalizedOrigin = CGPoint(
            x: desiredOrigin.x.isFinite ? desiredOrigin.x : visibleFrame.minX + Layout.outerMargin,
            y: desiredOrigin.y.isFinite ? desiredOrigin.y : max(visibleFrame.maxY - clampedWindowSize.height - Layout.outerMargin, visibleFrame.minY + 16)
        )

        return CGRect(origin: normalizedOrigin, size: clampedWindowSize).integral
    }

    private static func fitToScreenFrame(
        for imageSize: NSSize,
        anchoredAt currentFrame: CGRect,
        on screen: NSScreen?
    ) -> CGRect {
        let visibleFrame = screen?.visibleFrame
            ?? preferredPlacementScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 160, y: 160, width: 1440, height: 900)

        let maxContentWidth = max(visibleFrame.width - Layout.horizontalChrome - (Layout.outerMargin * 2), Layout.minimumImageWidth)
        let maxContentHeight = max(visibleFrame.height - Layout.verticalChrome - (Layout.outerMargin * 2), Layout.minimumImageHeight)

        let fittedContentSize = fittedImageSize(
            imageSize,
            maxSize: NSSize(width: maxContentWidth, height: maxContentHeight)
        )
        let targetSize = NSSize(
            width: fittedContentSize.width + Layout.horizontalChrome,
            height: fittedContentSize.height + Layout.verticalChrome
        )

        let centeredOrigin = CGPoint(
            x: min(
                max(currentFrame.midX - (targetSize.width / 2), visibleFrame.minX + 16),
                max(visibleFrame.maxX - targetSize.width - 16, visibleFrame.minX + 16)
            ),
            y: min(
                max(currentFrame.midY - (targetSize.height / 2), visibleFrame.minY + 16),
                max(visibleFrame.maxY - targetSize.height - 16, visibleFrame.minY + 16)
            )
        )

        return CGRect(origin: centeredOrigin, size: targetSize).integral
    }
}
