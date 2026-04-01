import AVKit
import AppKit
import Foundation
import Shared

@MainActor
public final class RecordingsBrowserWindowController: NSWindowController {
    private static let preferredWindowSize = NSSize(width: 1040, height: 680)

    private enum FilterScope: Int, CaseIterable {
        case all
        case favorites
        case marked
        case withNotes

        var title: String {
            switch self {
            case .all: return "All Recordings"
            case .favorites: return "Favorites"
            case .marked: return "Marked"
            case .withNotes: return "With Notes"
            }
        }

        func includes(_ recording: RecordingItem) -> Bool {
            switch self {
            case .all:
                return true
            case .favorites:
                return recording.isFavorite
            case .marked:
                return recording.markers.isEmpty == false
            case .withNotes:
                return recording.notes?.isEmpty == false
            }
        }
    }

    private let recordingStore: RecordingStore
    private let gifExportService = RecordingGIFExportService()
    private let searchField = NSSearchField()
    private let scopePopUpButton = NSPopUpButton()
    private let tableView = NSTableView()
    private let playerView = AVPlayerView()
    private let titleField = NSTextField()
    private let metadataField = NSTextField(labelWithString: "Recordings will appear here after your first saved video.")
    private let locationField = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton(checkboxWithTitle: "Favorite", target: nil, action: nil)
    private let notesTextView = NSTextView()
    private let notesScrollView = NSScrollView()
    private let saveDetailsButton = NSButton(title: "Save Details", target: nil, action: nil)
    private let openButton = NSButton(title: "Open", target: nil, action: nil)
    private let trimButton = NSButton(title: "Trim…", target: nil, action: nil)
    private let exportGIFButton = NSButton(title: "Export GIF", target: nil, action: nil)
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let openFolderButton = NSButton(title: "Open Folder", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No recordings match the current filter.")
    private var reloadTask: Task<Void, Never>?
    private var trimWindowControllers: [String: RecordingTrimWindowController] = [:]

    private var allRecordings: [RecordingItem] = []
    private var filteredRecordings: [RecordingItem] = []
    private var selectedRecordingID: String?
    private var isUpdatingMetadataForm = false

    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let absoluteDateFormatter = DateFormatter()
    private let byteCountFormatter = ByteCountFormatter()

    public init(recordingStore: RecordingStore) {
        self.recordingStore = recordingStore

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 280, y: 200), size: Self.preferredWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recordings Browser"
        window.identifier = NSUserInterfaceItemIdentifier("recordings-browser")
        window.setFrameAutosaveName("RecordingsBrowser")
        BrowserWindowFrameHelper.prepareForStandardBrowserBehavior(window)

        super.init(window: window)

        absoluteDateFormatter.dateStyle = .medium
        absoluteDateFormatter.timeStyle = .short
        byteCountFormatter.countStyle = .file

        configureWindow()
        reloadRecordings(preservingSelection: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public func present() {
        showWindow(nil)
        if let window {
            BrowserWindowFrameHelper.normalizeFrame(of: window, preferredSize: Self.preferredWindowSize)
            BrowserWindowFrameHelper.bringAppAndWindowToFront(window)
        }
    }

    public func reloadRecordings(preservingSelection: Bool = true) {
        let previousSelection = preservingSelection ? selectedRecordingID : nil
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let recordings = try await recordingStore.loadRecordings()
                guard Task.isCancelled == false else {
                    return
                }

                allRecordings = recordings
                applyFilter()

                if let previousSelection,
                   let index = filteredRecordings.firstIndex(where: { $0.id == previousSelection }) {
                    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                } else if filteredRecordings.isEmpty == false {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                } else {
                    tableView.deselectAll(nil)
                    selectedRecordingID = nil
                    updateDetail(for: nil)
                }
            } catch {
                guard Task.isCancelled == false else {
                    return
                }

                allRecordings = []
                applyFilter()
                tableView.deselectAll(nil)
                selectedRecordingID = nil
                updateDetail(for: nil)
                presentErrorAlert(message: "Failed to load recordings.", detail: error.localizedDescription)
            }
        }
    }

    deinit {
        reloadTask?.cancel()
    }

    private func configureWindow() {
        guard let window else {
            return
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let sidebar = makeSidebarView()
        let detail = makeDetailView()
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(detail)
        splitView.setPosition(320, ofDividerAt: 0)
    }

    private func makeSidebarView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        searchField.placeholderString = "Search titles, notes, files"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        scopePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        scopePopUpButton.target = self
        scopePopUpButton.action = #selector(handleScopeChanged)
        FilterScope.allCases.forEach { scopePopUpButton.addItem(withTitle: $0.title) }
        scopePopUpButton.selectItem(at: FilterScope.all.rawValue)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recording"))
        column.title = "Recordings"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 58
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.backgroundColor = .clear
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.selectionHighlightStyle = .regular
        scrollView.documentView = tableView

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(scopePopUpButton)
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            scopePopUpButton.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scopePopUpButton.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            scopePopUpButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: scopePopUpButton.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        return container
    }

    private func makeDetailView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = 18
        playerView.layer?.cornerCurve = .continuous
        playerView.translatesAutoresizingMaskIntoConstraints = false

        titleField.placeholderString = "Recording title"
        titleField.font = .systemFont(ofSize: 22, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.focusRingType = .default
        titleField.target = self
        titleField.action = #selector(handleSaveDetails)
        metadataField.textColor = .secondaryLabelColor
        locationField.textColor = .secondaryLabelColor
        locationField.lineBreakMode = .byTruncatingMiddle
        notesTextView.isRichText = false
        notesTextView.isAutomaticQuoteSubstitutionEnabled = false
        notesTextView.isAutomaticDashSubstitutionEnabled = false
        notesTextView.font = .systemFont(ofSize: 13, weight: .regular)
        notesTextView.drawsBackground = false
        notesScrollView.drawsBackground = true
        notesScrollView.borderType = .bezelBorder
        notesScrollView.hasVerticalScroller = true
        notesScrollView.documentView = notesTextView
        notesScrollView.translatesAutoresizingMaskIntoConstraints = false
        notesScrollView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        favoriteButton.target = self
        favoriteButton.action = #selector(handleToggleFavorite)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        saveDetailsButton.bezelStyle = .rounded
        saveDetailsButton.target = self
        saveDetailsButton.action = #selector(handleSaveDetails)
        saveDetailsButton.translatesAutoresizingMaskIntoConstraints = false

        [titleField, metadataField, locationField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.maximumNumberOfLines = 2
        }

        [openButton, trimButton, exportGIFButton, revealButton, deleteButton, openFolderButton, refreshButton].forEach {
            $0.bezelStyle = .rounded
            $0.target = self
        }
        openButton.action = #selector(handleOpenSelectedRecording)
        trimButton.action = #selector(handleTrimSelectedRecording)
        exportGIFButton.action = #selector(handleExportGIFSelectedRecording)
        revealButton.action = #selector(handleRevealSelectedRecording)
        deleteButton.action = #selector(handleDeleteSelectedRecording)
        openFolderButton.action = #selector(handleOpenFolder)
        refreshButton.action = #selector(handleRefresh)

        let buttonRow = NSStackView(views: [openButton, trimButton, exportGIFButton, revealButton, deleteButton, openFolderButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let metadataEditorGrid = NSGridView(views: [
            [makeEditorLabel("Favorite"), favoriteButton],
            [makeEditorLabel("Notes"), notesScrollView]
        ])
        metadataEditorGrid.rowSpacing = 10
        metadataEditorGrid.columnSpacing = 14
        metadataEditorGrid.translatesAutoresizingMaskIntoConstraints = false

        let metadataActionRow = NSStackView(views: [saveDetailsButton])
        metadataActionRow.orientation = .horizontal
        metadataActionRow.alignment = .leading
        metadataActionRow.translatesAutoresizingMaskIntoConstraints = false

        let infoStack = NSStackView(views: [titleField, metadataField, locationField])
        infoStack.orientation = .vertical
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(playerView)
        container.addSubview(infoStack)
        container.addSubview(metadataEditorGrid)
        container.addSubview(metadataActionRow)
        container.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),

            infoStack.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 20),
            infoStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            infoStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            metadataEditorGrid.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 18),
            metadataEditorGrid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            metadataEditorGrid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            metadataActionRow.topAnchor.constraint(equalTo: metadataEditorGrid.bottomAnchor, constant: 12),
            metadataActionRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            buttonRow.topAnchor.constraint(equalTo: metadataActionRow.bottomAnchor, constant: 18),
            buttonRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            buttonRow.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24)
        ])

        updateButtons(enabled: false)
        return container
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = FilterScope(rawValue: scopePopUpButton.indexOfSelectedItem) ?? .all

        filteredRecordings = allRecordings.filter { scope.includes($0) }

        if query.isEmpty == false {
            filteredRecordings = filteredRecordings.filter { recording in
                let haystack = [
                    recording.title,
                    recording.sessionName ?? "",
                    recording.segmentIndex.map { "part \($0)" } ?? "",
                    recording.notes ?? "",
                    recording.isFavorite ? "favorite starred saved" : "",
                    absoluteDateFormatter.string(from: recording.modifiedAt),
                    recording.url.lastPathComponent
                ].joined(separator: " ")

                return haystack.localizedCaseInsensitiveContains(query)
            }
        }

        tableView.reloadData()
        emptyLabel.isHidden = filteredRecordings.isEmpty == false
    }

    private func selectedRecording() -> RecordingItem? {
        guard let selectedRecordingID else {
            return nil
        }

        return filteredRecordings.first(where: { $0.id == selectedRecordingID })
            ?? allRecordings.first(where: { $0.id == selectedRecordingID })
    }

    private func updateDetail(for recording: RecordingItem?) {
        guard let recording else {
            isUpdatingMetadataForm = true
            playerView.player?.pause()
            playerView.player = nil
            titleField.stringValue = "No recording selected"
            metadataField.stringValue = "Choose a recording from the list to preview it."
            locationField.stringValue = ""
            favoriteButton.state = .off
            notesTextView.string = ""
            isUpdatingMetadataForm = false
            updateButtons(enabled: false)
            return
        }

        isUpdatingMetadataForm = true
        playerView.player?.pause()
        playerView.player = AVPlayer(url: recording.url)
        titleField.stringValue = recording.title
        metadataField.stringValue = metadataString(for: recording)
        locationField.stringValue = recording.url.path
        favoriteButton.state = recording.isFavorite ? .on : .off
        notesTextView.string = recording.notes ?? ""
        isUpdatingMetadataForm = false
        updateButtons(enabled: true)
    }

    private func updateButtons(enabled: Bool) {
        titleField.isEditable = enabled
        titleField.isEnabled = enabled
        favoriteButton.isEnabled = enabled
        notesTextView.isEditable = enabled
        saveDetailsButton.isEnabled = enabled
        openButton.isEnabled = enabled
        trimButton.isEnabled = enabled
        exportGIFButton.isEnabled = enabled
        revealButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
    }

    private func metadataString(for recording: RecordingItem) -> String {
        let modifiedRelative = relativeDateFormatter.localizedString(for: recording.modifiedAt, relativeTo: .now)
        let modifiedAbsolute = absoluteDateFormatter.string(from: recording.modifiedAt)
        let duration = durationString(recording.duration)
        let fileSize = byteCountFormatter.string(fromByteCount: recording.fileSize)
        let segmentSummary = segmentSummary(for: recording)
        let markerSummary = recording.markers.isEmpty
            ? "No markers"
            : "\(recording.markers.count) marker\(recording.markers.count == 1 ? "" : "s")"
        let favorite = recording.isFavorite ? "Favorite" : nil
        let notes = recording.notes?.isEmpty == false ? "Notes" : nil
        let extras = [favorite, notes, segmentSummary, markerSummary].compactMap { $0 }.joined(separator: " · ")
        return "Modified \(modifiedRelative) · \(modifiedAbsolute) · \(duration) · \(fileSize) · \(extras)"
    }

    private func durationString(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "Unknown duration"
        }

        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func makeEditorLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func segmentSummary(for recording: RecordingItem) -> String? {
        guard let segmentIndex = recording.segmentIndex else {
            return nil
        }

        if let sessionName = recording.sessionName, sessionName.isEmpty == false {
            return "\(sessionName) · Part \(segmentIndex)"
        }

        return "Part \(segmentIndex)"
    }

    private func presentErrorAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    @objc
    private func handleOpenSelectedRecording() {
        guard let recording = selectedRecording() else {
            return
        }

        recordingStore.open(recording)
    }

    @objc
    private func handleRevealSelectedRecording() {
        guard let recording = selectedRecording() else {
            return
        }

        recordingStore.reveal(recording)
    }

    @objc
    private func handleTrimSelectedRecording() {
        guard let recording = selectedRecording() else {
            return
        }

        if let existing = trimWindowControllers[recording.id] {
            existing.present()
            return
        }

        let controller = RecordingTrimWindowController(recording: recording)
        controller.onDidClose = { [weak self] recordingID in
            self?.trimWindowControllers[recordingID] = nil
        }
        controller.onDidExport = { [weak self] outputURL in
            self?.selectedRecordingID = outputURL.path
            self?.reloadRecordings(preservingSelection: true)
        }
        trimWindowControllers[recording.id] = controller
        controller.present()
    }

    @objc
    private func handleExportGIFSelectedRecording() {
        guard let recording = selectedRecording() else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                guard let outputURL = try await gifExportService.exportInteractively(recording: recording) else {
                    return
                }

                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                presentErrorAlert(message: "Failed to export GIF.", detail: error.localizedDescription)
            }
        }
    }

    @objc
    private func handleDeleteSelectedRecording() {
        guard let recording = selectedRecording() else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Delete this recording?"
        alert.informativeText = "This removes the saved video file from disk."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try recordingStore.delete(recording)
            reloadRecordings(preservingSelection: false)
        } catch {
            presentErrorAlert(message: "Failed to delete recording.", detail: error.localizedDescription)
        }
    }

    @objc
    private func handleOpenFolder() {
        do {
            try recordingStore.revealDirectory()
        } catch {
            presentErrorAlert(message: "Failed to open recordings folder.", detail: error.localizedDescription)
        }
    }

    @objc
    private func handleRefresh() {
        reloadRecordings()
    }

    @objc
    private func handleSaveDetails() {
        guard let recording = selectedRecording() else {
            return
        }

        do {
            try recordingStore.updateMetadata(
                for: recording.url,
                title: titleField.stringValue,
                notes: notesTextView.string,
                isFavorite: favoriteButton.state == .on
            )
            reloadRecordings()
        } catch {
            presentErrorAlert(message: "Failed to save recording details.", detail: error.localizedDescription)
        }
    }

    @objc
    private func handleToggleFavorite() {
        guard isUpdatingMetadataForm == false else {
            return
        }

        handleSaveDetails()
    }

    @objc
    private func handleScopeChanged() {
        applyFilter()

        if let selectedRecordingID,
           let index = filteredRecordings.firstIndex(where: { $0.id == selectedRecordingID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if filteredRecordings.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            selectedRecordingID = nil
            updateDetail(for: nil)
        }
    }
}

extension RecordingsBrowserWindowController: NSSearchFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        applyFilter()

        if let selectedRecordingID,
           let index = filteredRecordings.firstIndex(where: { $0.id == selectedRecordingID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if filteredRecordings.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            selectedRecordingID = nil
            updateDetail(for: nil)
        }
    }
}

extension RecordingsBrowserWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecordings.count
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        58
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("recording-row")
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? RecordingRowView)
            ?? RecordingRowView(frame: .zero)
        view.identifier = identifier

        let recording = filteredRecordings[row]
        view.configure(
            title: recording.title,
            subtitle: metadataString(for: recording),
            isFavorite: recording.isFavorite
        )
        return view
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard filteredRecordings.indices.contains(selectedRow) else {
            selectedRecordingID = nil
            updateDetail(for: nil)
            return
        }

        let recording = filteredRecordings[selectedRow]
        selectedRecordingID = recording.id
        updateDetail(for: recording)
    }
}

final class RecordingRowView: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, subtitle: String, isFavorite: Bool) {
        titleField.stringValue = isFavorite ? "★ \(title)" : title
        subtitleField.stringValue = subtitle
    }

    private func setup() {
        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor)
        ])
    }
}
