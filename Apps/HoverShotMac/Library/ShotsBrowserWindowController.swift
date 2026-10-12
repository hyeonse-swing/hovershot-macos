@preconcurrency import AppKit
import Foundation
import Shared

@MainActor
public protocol ShotsBrowserWindowControllerDelegate: AnyObject {
    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestOpen shot: Shot
    )

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestAnnotate shot: Shot
    )

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestCopy shot: Shot
    ) throws

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestExport shot: Shot
    ) throws

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestRevealInFinder shot: Shot
    )

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestDelete shot: Shot
    ) throws

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestDelete shots: [Shot]
    ) throws

    func shotsBrowserWindowController(
        _ controller: ShotsBrowserWindowController,
        didRequestUpdateMetadataFor shot: Shot,
        title: String,
        notes: String?,
        tags: [String],
        isFavorite: Bool
    ) throws
}

@MainActor
public final class ShotsBrowserWindowController: NSWindowController {
    private static let preferredWindowSize = NSSize(width: 920, height: 620)

    private enum FilterScope: Int, CaseIterable {
        case all
        case favorites
        case tagged
        case annotated
        case withOCR
        case visible
        case hidden

        var title: String {
            switch self {
            case .all: return "All Shots"
            case .favorites: return "Favorites"
            case .tagged: return "Tagged"
            case .annotated: return "Annotated"
            case .withOCR: return "With OCR"
            case .visible: return "Visible"
            case .hidden: return "Hidden"
            }
        }

        func includes(_ shot: Shot) -> Bool {
            switch self {
            case .all:
                return true
            case .favorites:
                return shot.isFavorite
            case .tagged:
                return shot.tags.isEmpty == false
            case .annotated:
                return shot.annotations.isEmpty == false
            case .withOCR:
                return shot.recognizedText?.isEmpty == false
            case .visible:
                return shot.floatingState.isVisible
            case .hidden:
                return shot.floatingState.isVisible == false
            }
        }
    }

    public weak var delegate: ShotsBrowserWindowControllerDelegate?

    private let shotStore: ShotStore
    private let detectedDataService = DetectedDataService()
    private let searchField = NSSearchField()
    private let scopePopUpButton = NSPopUpButton()
    private let tableView = NSTableView()
    private let detailScrollView = NSScrollView()
    private let previewImageView = NSImageView()
    private var previewHeightConstraint: NSLayoutConstraint?
    private let titleField = NSTextField()
    private let metadataField = NSTextField(labelWithString: "Create a shot to populate the browser.")
    private let stateField = NSTextField(labelWithString: "")
    private let favoriteButton = NSButton(checkboxWithTitle: "Favorite", target: nil, action: nil)
    private let tagsField = NSTextField()
    private let notesTextView = NSTextView()
    private let notesScrollView = NSScrollView()
    private let saveMetadataButton = NSButton(title: "Save Details", target: nil, action: nil)
    private let ocrField = NSTextField(labelWithString: "")
    private let ocrActionsLabel = NSTextField(labelWithString: "Smart Actions")
    private let ocrActionsStack = NSStackView()
    private let primaryActionsContainer = NSStackView()
    private let openButton = NSButton(title: "Float Shot", target: nil, action: nil)
    private let annotateButton = NSButton(title: "Annotate", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let exportButton = NSButton(title: "Export", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "No shots match the current filter.")
    private let resultCountField = NSTextField(labelWithString: "")
    private let feedbackField = NSTextField(labelWithString: "")
    private let clearFiltersButton = NSButton(title: "Clear Filters", target: nil, action: nil)
    private struct MetadataDraft: Equatable {
        var title: String
        var notes: String
        var tags: String
        var isFavorite: Bool

        init(shot: Shot) {
            title = shot.title
            notes = shot.notes ?? ""
            tags = shot.tags.joined(separator: ", ")
            isFavorite = shot.isFavorite
        }
    }
    private var drafts: [UUID: MetadataDraft] = [:]
    private var displayedShot: Shot?
    private var isReloading = false
    private let tableContextMenu = NSMenu(title: "Shot Actions")
    private let deleteSelectedMenuItem = NSMenuItem(title: "Delete Selected Shots", action: nil, keyEquivalent: "")

    private var allShots: [Shot] = []
    private var filteredShots: [Shot] = []
    private var selectedShotID: UUID?
    private var currentDetectedDataItems: [DetectedDataItem] = []
    private var isUpdatingMetadataForm = false
    private let relativeDateFormatter = RelativeDateTimeFormatter()
    private let absoluteDateFormatter = DateFormatter()
    private weak var detailContainerView: NSView?
    private weak var browserSplitView: NSSplitView?

    private final class FlippedContentView: NSView {
        override var isFlipped: Bool { true }
    }

    public init(shotStore: ShotStore) {
        self.shotStore = shotStore

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 280, y: 200), size: Self.preferredWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shots Browser"
        window.identifier = NSUserInterfaceItemIdentifier("shots-browser")
        window.setFrameAutosaveName("ShotsBrowser")
        window.minSize = NSSize(width: 600, height: 520)
        BrowserWindowFrameHelper.prepareForStandardBrowserBehavior(window)

        super.init(window: window)

        absoluteDateFormatter.dateStyle = .medium
        absoluteDateFormatter.timeStyle = .short

        configureWindow()
        window.delegate = self
        observeWindowChanges()
        observeStoreChanges()
        DispatchQueue.main.async { [weak self] in
            self?.reloadShots(preservingSelection: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func present() {
        showWindow(nil)
        if let window {
            BrowserWindowFrameHelper.normalizeFrame(of: window, preferredSize: Self.preferredWindowSize)
            BrowserWindowFrameHelper.bringAppAndWindowToFront(window)
        }
        refreshDetailLayoutAfterPresentation()
    }

    public func reloadShots(preservingSelection: Bool = true) {
        rememberDraft()
        let previousSelections = preservingSelection ? Set(selectedShots().map(\.id)) : []

        do {
            allShots = try shotStore.loadShots().sorted { $0.createdAt > $1.createdAt }
        } catch {
            presentErrorAlert(
                message: "Failed to load shots.",
                detail: error.localizedDescription
            )
            return
        }

        applyFilter()

        let indexes = IndexSet(filteredShots.indices.filter { previousSelections.contains(filteredShots[$0].id) })
        if !indexes.isEmpty {
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        } else if filteredShots.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
            selectedShotID = nil
            updateDetail(for: nil)
        }
        refreshSelectionDetail()

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
        browserSplitView = splitView

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
        splitView.setPosition(240, ofDividerAt: 0)
    }

    private func makeSidebarView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        searchField.placeholderString = "Search titles, OCR, tags, notes"
        searchField.delegate = self
        searchField.setAccessibilityLabel("Search shots")
        searchField.toolTip = "Search titles, recognized text, tags, and notes"
        scopePopUpButton.setAccessibilityLabel("Filter shots")
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shot"))
        column.title = "Shots"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
        tableView.backgroundColor = .clear
        tableView.focusRingType = .default
        tableView.setAccessibilityLabel("Shots")
        tableView.target = self
        tableView.doubleAction = #selector(handleOpenSelectedShot)
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.selectionHighlightStyle = .regular
        deleteSelectedMenuItem.target = self
        deleteSelectedMenuItem.action = #selector(handleDeleteSelectedShot)
        tableContextMenu.autoenablesItems = false
        tableContextMenu.items = [deleteSelectedMenuItem]
        tableView.menu = tableContextMenu
        scrollView.documentView = tableView

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.maximumNumberOfLines = 0
        emptyLabel.lineBreakMode = .byWordWrapping
        clearFiltersButton.bezelStyle = .rounded
        clearFiltersButton.target = self
        clearFiltersButton.action = #selector(handleClearFilters)
        clearFiltersButton.translatesAutoresizingMaskIntoConstraints = false
        clearFiltersButton.isHidden = true
        resultCountField.textColor = .secondaryLabelColor
        resultCountField.font = .systemFont(ofSize: 11)
        resultCountField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resultCountField)
        container.addSubview(clearFiltersButton)
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
            scrollView.bottomAnchor.constraint(equalTo: resultCountField.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            emptyLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            clearFiltersButton.topAnchor.constraint(equalTo: emptyLabel.bottomAnchor, constant: 12),
            clearFiltersButton.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            resultCountField.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
            resultCountField.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makeDetailView() -> NSView {
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        detailScrollView.drawsBackground = false
        detailScrollView.borderType = .noBorder
        detailScrollView.hasVerticalScroller = true
        detailScrollView.hasHorizontalScroller = false
        detailScrollView.autohidesScrollers = true

        let container = FlippedContentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        detailContainerView = container
        detailScrollView.documentView = container

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: detailScrollView.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: detailScrollView.contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: detailScrollView.contentView.topAnchor),
            container.widthAnchor.constraint(equalTo: detailScrollView.contentView.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: detailScrollView.contentView.heightAnchor)
        ])

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.imageAlignment = .alignCenter
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        let previewHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 188)
        previewHeightConstraint.isActive = true
        self.previewHeightConstraint = previewHeightConstraint

        titleField.placeholderString = "Shot title"
        titleField.setAccessibilityLabel("Shot title")
        titleField.delegate = self
        tagsField.setAccessibilityLabel("Tags, comma separated")
        tagsField.delegate = self
        notesTextView.setAccessibilityLabel("Shot notes")
        notesTextView.delegate = self
        previewImageView.setAccessibilityLabel("Shot preview")
        titleField.font = .systemFont(ofSize: 22, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.focusRingType = .default
        titleField.target = self
        titleField.action = #selector(handleSaveMetadata)
        metadataField.textColor = .secondaryLabelColor
        stateField.textColor = .secondaryLabelColor
        tagsField.placeholderString = "Tags, comma separated"
        tagsField.translatesAutoresizingMaskIntoConstraints = false
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
        notesScrollView.heightAnchor.constraint(equalToConstant: 84).isActive = true
        favoriteButton.target = self
        favoriteButton.action = #selector(handleToggleFavorite)
        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        saveMetadataButton.bezelStyle = .rounded
        saveMetadataButton.target = self
        saveMetadataButton.action = #selector(handleSaveMetadata)
        saveMetadataButton.translatesAutoresizingMaskIntoConstraints = false
        saveMetadataButton.keyEquivalent = "s"
        saveMetadataButton.keyEquivalentModifierMask = .command
        feedbackField.textColor = .secondaryLabelColor
        feedbackField.font = .systemFont(ofSize: 12)
        feedbackField.maximumNumberOfLines = 0
        feedbackField.lineBreakMode = .byWordWrapping
        ocrField.isSelectable = true
        ocrField.textColor = .secondaryLabelColor
        ocrField.font = .systemFont(ofSize: 12, weight: .regular)
        ocrField.lineBreakMode = .byCharWrapping
        ocrField.cell?.wraps = true
        ocrField.cell?.usesSingleLineMode = false
        ocrField.cell?.isScrollable = false
        ocrField.translatesAutoresizingMaskIntoConstraints = false
        ocrActionsLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        ocrActionsLabel.textColor = .secondaryLabelColor
        ocrActionsLabel.isHidden = true
        ocrActionsStack.orientation = .vertical
        ocrActionsStack.alignment = .leading
        ocrActionsStack.spacing = 6
        ocrActionsStack.translatesAutoresizingMaskIntoConstraints = false
        ocrActionsStack.isHidden = true

        [titleField, metadataField, stateField, ocrActionsLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.lineBreakMode = .byWordWrapping
        }
        metadataField.maximumNumberOfLines = 2
        stateField.maximumNumberOfLines = 2
        ocrField.maximumNumberOfLines = 5
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metadataField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stateField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        ocrField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        ocrField.setContentCompressionResistancePriority(.required, for: .vertical)
        metadataField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stateField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        ocrField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tagsField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tagsField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        [openButton, annotateButton, copyButton, exportButton, revealButton, deleteButton, refreshButton].forEach {
            $0.bezelStyle = .rounded
            $0.target = self
        }
        openButton.action = #selector(handleOpenSelectedShot)
        annotateButton.action = #selector(handleAnnotateSelectedShot)
        copyButton.action = #selector(handleCopySelectedShot)
        exportButton.action = #selector(handleExportSelectedShot)
        revealButton.action = #selector(handleRevealSelectedShot)
        deleteButton.action = #selector(handleDeleteSelectedShot)
        refreshButton.action = #selector(handleRefresh)
        primaryActionsContainer.translatesAutoresizingMaskIntoConstraints = false

        let favoriteRow = NSStackView(views: [makeEditorLabel("Favorite"), favoriteButton])
        favoriteRow.orientation = .horizontal
        favoriteRow.alignment = .centerY
        favoriteRow.spacing = 12
        favoriteRow.translatesAutoresizingMaskIntoConstraints = false

        let tagsRow = NSStackView(views: [makeEditorLabel("Tags"), tagsField])
        tagsRow.orientation = .horizontal
        tagsRow.alignment = .centerY
        tagsRow.spacing = 12
        tagsRow.translatesAutoresizingMaskIntoConstraints = false

        let notesLabel = makeEditorLabel("Notes")
        let notesStack = NSStackView(views: [notesLabel, notesScrollView])
        notesStack.orientation = .vertical
        notesStack.alignment = .leading
        notesStack.spacing = 8
        notesStack.translatesAutoresizingMaskIntoConstraints = false

        let metadataActionRow = NSStackView(views: [saveMetadataButton, feedbackField])
        metadataActionRow.orientation = .horizontal
        metadataActionRow.alignment = .leading
        metadataActionRow.translatesAutoresizingMaskIntoConstraints = false

        let infoStack = NSStackView(views: [titleField, metadataField, stateField])
        infoStack.orientation = .vertical
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(previewImageView)
        container.addSubview(infoStack)
        container.addSubview(ocrField)
        container.addSubview(ocrActionsLabel)
        container.addSubview(ocrActionsStack)
        container.addSubview(favoriteRow)
        container.addSubview(tagsRow)
        container.addSubview(notesStack)
        container.addSubview(metadataActionRow)
        container.addSubview(primaryActionsContainer)

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            previewImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            previewImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),


            infoStack.topAnchor.constraint(equalTo: primaryActionsContainer.bottomAnchor, constant: 20),
            infoStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            infoStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            ocrField.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 12),
            ocrField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            ocrField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -40),

            ocrActionsLabel.topAnchor.constraint(equalTo: ocrField.bottomAnchor, constant: 10),
            ocrActionsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            ocrActionsLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),

            ocrActionsStack.topAnchor.constraint(equalTo: ocrActionsLabel.bottomAnchor, constant: 8),
            ocrActionsStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            ocrActionsStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),

            favoriteRow.topAnchor.constraint(equalTo: ocrActionsStack.bottomAnchor, constant: 18),
            favoriteRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            favoriteRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            tagsRow.topAnchor.constraint(equalTo: favoriteRow.bottomAnchor, constant: 12),
            tagsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            tagsRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            notesStack.topAnchor.constraint(equalTo: tagsRow.bottomAnchor, constant: 12),
            notesStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            notesStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            metadataActionRow.topAnchor.constraint(equalTo: notesStack.bottomAnchor, constant: 12),
            metadataActionRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            metadataActionRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            metadataActionRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            notesScrollView.widthAnchor.constraint(equalTo: notesStack.widthAnchor),

            primaryActionsContainer.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 12),
            primaryActionsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            primaryActionsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        configurePrimaryActionRows()
        updateButtons(enabled: false)
        return detailScrollView
    }

    private func applyFilter() {
        rememberDraft()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = FilterScope(rawValue: scopePopUpButton.indexOfSelectedItem) ?? .all

        filteredShots = allShots.filter { scope.includes($0) }

        if query.isEmpty == false {
            filteredShots = filteredShots.filter { shot in
                let haystack = [
                    shot.title,
                    shot.recognizedText ?? "",
                    shot.notes ?? "",
                    shot.tags.joined(separator: " "),
                    shot.isFavorite ? "favorite starred saved" : "",
                    shot.floatingState.visibilityMode.rawValue,
                    absoluteDateFormatter.string(from: shot.createdAt)
                ].joined(separator: " ")

                return haystack.localizedCaseInsensitiveContains(query)
            }
        }

        isReloading = true
        tableView.reloadData()
        isReloading = false
        emptyLabel.isHidden = filteredShots.isEmpty == false
        emptyLabel.stringValue = allShots.isEmpty
            ? "No shots yet.\nCapture an area or import an image from the menu bar."
            : "No matching shots.\nTry another search or clear your filters."
        clearFiltersButton.isHidden = filteredShots.isEmpty == false || (query.isEmpty && scope == .all)
        resultCountField.stringValue = "\(filteredShots.count) of \(allShots.count) shots"
        drafts = drafts.filter { id, _ in allShots.contains { $0.id == id } }
    }

    private func selectedShot() -> Shot? {
        if let selectedShotID {
            return filteredShots.first(where: { $0.id == selectedShotID })
                ?? allShots.first(where: { $0.id == selectedShotID })
        }

        return nil
    }

    private func selectedShots() -> [Shot] {
        tableView.selectedRowIndexes.compactMap { row in
            filteredShots.indices.contains(row) ? filteredShots[row] : nil
        }
    }

    private func updateDetail(for shot: Shot?) {
        rememberDraft()
        displayedShot = shot
        guard let shot else {
            isUpdatingMetadataForm = true
            feedbackField.stringValue = ""
            previewImageView.image = nil
            titleField.stringValue = "No shot selected"
            metadataField.stringValue = "Choose a shot from the list to preview it."
            stateField.stringValue = ""
            favoriteButton.state = .off
            tagsField.stringValue = ""
            notesTextView.string = ""
            ocrField.stringValue = ""
            currentDetectedDataItems = []
            reloadOCRActionButtons()
            isUpdatingMetadataForm = false
            updateButtons(enabled: false)
            return
        }

        isUpdatingMetadataForm = true
        previewImageView.image = shotStore.loadRenderedImage(for: shot)
        let draft = drafts[shot.id] ?? MetadataDraft(shot: shot)
        titleField.stringValue = draft.title
        metadataField.stringValue = metadataString(for: shot)
        stateField.stringValue = stateString(for: shot)
        favoriteButton.state = draft.isFavorite ? .on : .off
        tagsField.stringValue = draft.tags
        notesTextView.string = draft.notes
        ocrField.stringValue = ocrString(for: shot)
        currentDetectedDataItems = detectedDataItems(for: shot)
        reloadOCRActionButtons()
        isUpdatingMetadataForm = false
        updateButtons(enabled: true)
        updateDraftFeedback()
    }

    private func updateDetailForMultipleSelection(_ shots: [Shot]) {
        rememberDraft()
        displayedShot = nil
        feedbackField.stringValue = ""
        isUpdatingMetadataForm = true
        previewImageView.image = nil
        titleField.stringValue = "\(shots.count) shots selected"
        metadataField.stringValue = "Delete the selected shots, or select a single shot to inspect and edit it."
        stateField.stringValue = ""
        favoriteButton.state = .off
        tagsField.stringValue = ""
        notesTextView.string = ""
        ocrField.stringValue = ""
        currentDetectedDataItems = []
        reloadOCRActionButtons()
        isUpdatingMetadataForm = false
        updateButtonsForSelection(count: shots.count)
    }

    private func updateButtons(enabled: Bool) {
        titleField.isEditable = enabled
        titleField.isEnabled = enabled
        openButton.isEnabled = enabled
        annotateButton.isEnabled = enabled
        copyButton.isEnabled = enabled
        exportButton.isEnabled = enabled
        revealButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
        favoriteButton.isEnabled = enabled
        tagsField.isEnabled = enabled
        notesTextView.isEditable = enabled
        saveMetadataButton.isEnabled = enabled
    }

    private func updateButtonsForSelection(count: Int) {
        guard count > 0 else {
            updateButtons(enabled: false)
            deleteButton.isEnabled = false
            return
        }

        guard count == 1 else {
            titleField.isEditable = false
            titleField.isEnabled = false
            openButton.isEnabled = false
            annotateButton.isEnabled = false
            copyButton.isEnabled = false
            exportButton.isEnabled = false
            revealButton.isEnabled = false
            deleteButton.isEnabled = true
            favoriteButton.isEnabled = false
            tagsField.isEnabled = false
            notesTextView.isEditable = false
            saveMetadataButton.isEnabled = false
            return
        }

        updateButtons(enabled: true)
    }

    private func metadataString(for shot: Shot) -> String {
        let relative = relativeDateFormatter.localizedString(for: shot.createdAt, relativeTo: .now)
        let absolute = absoluteDateFormatter.string(from: shot.createdAt)
        let favorite = shot.isFavorite ? "Favorite" : nil
        let tags = shot.tags.isEmpty ? nil : "\(shot.tags.count) tag\(shot.tags.count == 1 ? "" : "s")"
        let notes = shot.notes?.isEmpty == false ? "Notes" : nil
        let extras = [favorite, tags, notes].compactMap { $0 }.joined(separator: " · ")

        if extras.isEmpty {
            return "Created \(relative) · \(absolute)"
        }

        return "Created \(relative) · \(absolute) · \(extras)"
    }

    private func stateString(for shot: Shot) -> String {
        let visibility = switch shot.floatingState.visibilityMode {
        case .everywhere: "Everywhere"
        case .currentSpace: "Current Space"
        case .currentApp: "Current App"
        }

        let floatingStatus = shot.floatingState.isVisible ? "Visible" : "Hidden"
        let clickThrough = shot.floatingState.ignoresMouseEvents ? "Click-through On" : "Click-through Off"
        let opacity = Int((shot.floatingState.opacity * 100).rounded())
        let annotationCount = shot.annotations.count
        let annotationSummary = annotationCount == 0 ? "No Markup" : "\(annotationCount) Markup Item\(annotationCount == 1 ? "" : "s")"
        return "\(floatingStatus) · \(visibility) · \(clickThrough) · \(opacity)% opacity · \(annotationSummary)"
    }

    private func ocrString(for shot: Shot) -> String {
        guard let recognizedText = shot.recognizedText, recognizedText.isEmpty == false else {
            return "OCR: No recognized text yet"
        }

        let preview = recognizedText
            .replacingOccurrences(of: "\n", with: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPreview: String
        if preview.count > 420 {
            clampedPreview = String(preview.prefix(420)) + "…"
        } else {
            clampedPreview = preview
        }
        return "OCR: \(clampedPreview)"
    }

    private func detectedDataItems(for shot: Shot) -> [DetectedDataItem] {
        guard let recognizedText = shot.recognizedText, recognizedText.isEmpty == false else {
            return []
        }

        return detectedDataService.detect(in: recognizedText)
    }

    private func reloadOCRActionButtons() {
        ocrActionsStack.arrangedSubviews.forEach { view in
            ocrActionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let shot = selectedShot()
        guard let shot, shot.recognizedText?.isEmpty == false else {
            ocrActionsLabel.isHidden = true
            ocrActionsStack.isHidden = true
            return
        }

        var buttons: [NSButton] = []
        let copyTextButton = makeOCRActionButton(
            title: "Copy OCR",
            action: #selector(handleCopyOCRText)
        )
        buttons.append(copyTextButton)

        for item in currentDetectedDataItems.prefix(3) {
            let title = switch item.kind {
            case .link: "Open Link"
            case .email: "Compose Email"
            case .phoneNumber: "Copy Phone"
            }

            let button = makeOCRActionButton(
                title: title,
                action: #selector(handlePerformDetectedDataAction(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(item.id)
            buttons.append(button)
        }

        rebuildWrappedButtonRows(
            buttons: buttons,
            in: ocrActionsStack,
            availableWidth: availableOCRActionsWidth(),
            maxColumns: 3
        )
        ocrActionsLabel.isHidden = false
        ocrActionsStack.isHidden = buttons.isEmpty
    }

    private func configurePrimaryActionRows() {
        primaryActionsContainer.orientation = .vertical
        primaryActionsContainer.alignment = .leading
        primaryActionsContainer.spacing = 8
        rebuildWrappedButtonRows(
            buttons: [openButton, annotateButton, copyButton, exportButton, revealButton, deleteButton, refreshButton],
            in: primaryActionsContainer,
            availableWidth: availablePrimaryActionsWidth(),
            maxColumns: 4
        )
    }

    private func rebuildWrappedButtonRows(
        buttons: [NSButton],
        in stack: NSStackView,
        availableWidth: CGFloat,
        maxColumns: Int
    ) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard buttons.isEmpty == false else {
            stack.isHidden = true
            return
        }

        let spacing: CGFloat = 8
        let estimatedButtonWidth: CGFloat = 124
        let columns = max(
            1,
            min(
                maxColumns,
                Int((max(availableWidth, estimatedButtonWidth) + spacing) / (estimatedButtonWidth + spacing))
            )
        )

        stride(from: 0, to: buttons.count, by: columns).forEach { index in
            let rowButtons = Array(buttons[index..<min(index + columns, buttons.count)])
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = spacing
            row.translatesAutoresizingMaskIntoConstraints = false
            rowButtons.forEach { row.addArrangedSubview($0) }
            row.spacing = spacing
            stack.addArrangedSubview(row)
        }

        stack.isHidden = false
    }

    private func availablePrimaryActionsWidth() -> CGFloat {
        max(resolvedDetailContentWidth() - 48, 240)
    }

    private func availableOCRActionsWidth() -> CGFloat {
        max(resolvedDetailContentWidth() - 80, 140)
    }

    private func resolvedDetailContentWidth() -> CGFloat {
        window?.contentView?.layoutSubtreeIfNeeded()
        browserSplitView?.layoutSubtreeIfNeeded()
        detailScrollView.layoutSubtreeIfNeeded()
        detailScrollView.contentView.layoutSubtreeIfNeeded()
        detailContainerView?.layoutSubtreeIfNeeded()

        let measuredWidths: [CGFloat] = [
            browserSplitView?.arrangedSubviews.last?.bounds.width ?? 0,
            browserSplitView?.subviews.last?.bounds.width ?? 0,
            detailScrollView.bounds.width,
            detailScrollView.frame.width,
            detailContainerView?.bounds.width ?? 0,
            detailScrollView.contentSize.width,
            detailScrollView.contentView.bounds.width,
            max((window?.contentView?.bounds.width ?? Self.preferredWindowSize.width) - 260, 0)
        ]

        return measuredWidths.first { $0 > 0 } ?? (Self.preferredWindowSize.width - 240)
    }

    private func refreshDetailLayoutAfterPresentation() {
        let refresh: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.configurePrimaryActionRows()
            self.reloadOCRActionButtons()
            self.scrollDetailToTop()
        }

        refresh()
        DispatchQueue.main.async(execute: refresh)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: refresh)
    }

    private func scrollDetailToTop() {
        detailScrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
    }

    private func makeOCRActionButton(
        title: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func copyStringToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func makeEditorLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func parsedTags() -> [String] {
        tagsField.stringValue
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func observeStoreChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShotStoreDidChange),
            name: .shotStoreDidChange,
            object: shotStore
        )
    }

    private func observeWindowChanges() {
        guard let window else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc
    private func handleShotStoreDidChange() {
        reloadShots()
    }

    @objc
    private func handleWindowDidResize() {
        configurePrimaryActionRows()
        reloadOCRActionButtons()
    }

    private func presentErrorAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }

    @objc
    private func handleOpenSelectedShot() {
        guard selectedShots().count == 1, let shot = selectedShot() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.delegate?.shotsBrowserWindowController(self, didRequestOpen: shot)
            self.reloadShots()
        }
    }

    @objc
    private func handleAnnotateSelectedShot() {
        guard let shot = selectedShot() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.delegate?.shotsBrowserWindowController(self, didRequestAnnotate: shot)
        }
    }

    @objc
    private func handleCopySelectedShot() {
        guard let shot = selectedShot() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                guard let delegate = self.delegate else { return }
                try delegate.shotsBrowserWindowController(self, didRequestCopy: shot)
                self.feedbackField.stringValue = "Image copied to clipboard."
            } catch {
                self.presentErrorAlert(message: "Failed to copy shot.", detail: error.localizedDescription)
            }
        }
    }

    @objc
    private func handleExportSelectedShot() {
        guard let shot = selectedShot() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try self.delegate?.shotsBrowserWindowController(self, didRequestExport: shot)
            } catch {
                self.presentErrorAlert(message: "Failed to export shot.", detail: error.localizedDescription)
            }
        }
    }

    @objc
    private func handleRevealSelectedShot() {
        guard let shot = selectedShot() else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.delegate?.shotsBrowserWindowController(self, didRequestRevealInFinder: shot)
        }
    }

    @objc
    private func handleDeleteSelectedShot() {
        let shots = selectedShots()
        guard shots.isEmpty == false else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        if shots.count == 1 {
            alert.messageText = "Delete this shot?"
            alert.informativeText = "This removes the shot metadata and the stored image file."
        } else {
            alert.messageText = "Delete \(shots.count) shots?"
            alert.informativeText = "This removes the selected shot metadata and stored image files."
        }
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try self.delegate?.shotsBrowserWindowController(self, didRequestDelete: shots)
                self.reloadShots(preservingSelection: false)
            } catch {
                self.presentErrorAlert(message: "Failed to delete shot.", detail: error.localizedDescription)
            }
        }
    }

    @objc
    private func handleRefresh() {
        reloadShots()
    }

    private func rememberDraft() {
        guard !isUpdatingMetadataForm, let shot = displayedShot,
              allShots.contains(where: { $0.id == shot.id }) else { return }
        var draft = MetadataDraft(shot: shot)
        draft.title = titleField.stringValue
        draft.notes = notesTextView.string
        draft.tags = tagsField.stringValue
        draft.isFavorite = favoriteButton.state == .on
        drafts[shot.id] = draft == MetadataDraft(shot: shot) ? nil : draft
        window?.isDocumentEdited = !drafts.isEmpty
    }

    private func updateDraftFeedback() {
        let isDirty = displayedShot.map { drafts[$0.id] != nil } ?? false
        saveMetadataButton.isEnabled = isDirty
        feedbackField.stringValue = isDirty ? "Unsaved changes · ⌘S to save" : ""
        window?.isDocumentEdited = !drafts.isEmpty
    }

    @discardableResult
    private func saveDraft(for id: UUID) -> Bool {
        guard let draft = drafts[id], let shot = allShots.first(where: { $0.id == id }),
              let delegate else { return false }
        let previousDisplayedShot = displayedShot
        displayedShot = nil
        do {
            try delegate.shotsBrowserWindowController(
                self, didRequestUpdateMetadataFor: shot, title: draft.title,
                notes: draft.notes,
                tags: draft.tags.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                isFavorite: draft.isFavorite
            )
            drafts[id] = nil
            displayedShot = nil
            reloadShots()
            feedbackField.stringValue = "Details saved."
            return true
        } catch {
            displayedShot = previousDisplayedShot
            drafts[id] = draft
            updateDraftFeedback()
            presentErrorAlert(message: "Failed to save shot metadata.", detail: error.localizedDescription)
            return false
        }
    }

    @objc
    private func handleSaveMetadata() {
        rememberDraft()
        guard let id = displayedShot?.id else { return }
        saveDraft(for: id)
    }

    @objc
    private func handleToggleFavorite() {
        guard isUpdatingMetadataForm == false else {
            return
        }

        handleSaveMetadata()
    }

    @objc
    private func handleScopeChanged() {
        let previousID = selectedShotID
        applyFilter()
        selectedShotID = previousID

        if let selectedShotID,
           let index = filteredShots.firstIndex(where: { $0.id == selectedShotID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if filteredShots.isEmpty == false {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            selectedShotID = nil
            updateDetail(for: nil)
        }
        refreshSelectionDetail()
    }

    @objc
    private func handleCopyOCRText() {
        guard let text = selectedShot()?.recognizedText, text.isEmpty == false else {
            return
        }

        copyStringToPasteboard(text)
        feedbackField.stringValue = "Recognized text copied to clipboard."
    }

    @objc
    private func handlePerformDetectedDataAction(_ sender: NSButton) {
        guard
            let identifier = sender.identifier?.rawValue,
            let item = currentDetectedDataItems.first(where: { $0.id == identifier })
        else {
            return
        }

        switch item.kind {
        case .link, .email:
            if let url = item.url {
                NSWorkspace.shared.open(url)
            }
        case .phoneNumber:
            copyStringToPasteboard(item.displayValue)
        }
    }

}

extension ShotsBrowserWindowController: NSSearchFieldDelegate, NSTextViewDelegate, NSWindowDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSSearchField === searchField {
            handleScopeChanged()
        } else {
            rememberDraft()
            updateDraftFeedback()
        }
    }

    public func textDidChange(_ notification: Notification) {
        rememberDraft()
        updateDraftFeedback()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        rememberDraft()
        guard !drafts.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "You have unsaved details for \(drafts.count) shot(s)."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            for id in Array(drafts.keys) {
                guard saveDraft(for: id) else { return false }
            }
            return true
        case .alertThirdButtonReturn:
            drafts.removeAll()
            displayedShot = nil
            refreshSelectionDetail()
            sender.isDocumentEdited = false
            return true
        default: return false
        }
    }

    @objc private func handleClearFilters() {
        searchField.stringValue = ""
        scopePopUpButton.selectItem(at: FilterScope.all.rawValue)
        handleScopeChanged()
        window?.makeFirstResponder(searchField)
    }
}

extension ShotsBrowserWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredShots.count
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        56
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("shot-row")
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? ShotRowView)
            ?? ShotRowView(frame: .zero)
        view.identifier = identifier

        let shot = filteredShots[row]
        view.configure(
            title: shot.title,
            subtitle: metadataString(for: shot),
            isVisible: shot.floatingState.isVisible,
            isFavorite: shot.isFavorite
        )
        return view
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloading else { return }
        refreshSelectionDetail()
    }

    private func refreshSelectionDetail() {
        rememberDraft()
        let selectedRows = tableView.selectedRowIndexes
        guard selectedRows.isEmpty == false else {
            selectedShotID = nil
            updateDetail(for: nil)
            return
        }

        let shots = selectedShots()
        selectedShotID = shots.first?.id

        if shots.count == 1 {
            updateDetail(for: shots.first)
        } else {
            updateDetailForMultipleSelection(shots)
        }
    }
}

final class ShotRowView: NSTableCellView {
    private let dotView = NSView()
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

    func configure(title: String, subtitle: String, isVisible: Bool, isFavorite: Bool) {
        titleField.stringValue = isFavorite ? "★ \(title)" : title
        subtitleField.stringValue = subtitle
        dotView.layer?.backgroundColor = (isVisible ? NSColor.systemGreen : NSColor.systemGray).cgColor
    }

    private func setup() {
        wantsLayer = true

        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.translatesAutoresizingMaskIntoConstraints = false

        titleField.font = .systemFont(ofSize: 13, weight: .semibold)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dotView)
        addSubview(titleField)
        addSubview(subtitleField)

        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleField.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor)
        ])
    }
}
