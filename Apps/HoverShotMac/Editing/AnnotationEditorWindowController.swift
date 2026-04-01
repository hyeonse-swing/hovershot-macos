import AppKit
import Library

@MainActor
public final class AnnotationEditorWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    public let shotID: UUID

    public var onSave: ((UUID, [ShotAnnotation]) -> Void)?
    public var onClose: ((UUID) -> Void)?

    private let canvasView = AnnotationCanvasView()
    private let instructionsField = NSTextField(labelWithString: "")
    private let modeControl = NSSegmentedControl(
        labels: ShotAnnotationStyle.allCases.map(\.displayName),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let textField = NSTextField(string: "Note")
    private let undoButton = NSButton(title: "Undo Last", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear All", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private var workingAnnotations: [ShotAnnotation]
    private var savedAnnotations: [ShotAnnotation]

    public init(shot: Shot, baseImage: NSImage) {
        self.shotID = shot.id
        self.workingAnnotations = shot.annotations
        self.savedAnnotations = shot.annotations

        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 180, width: 1100, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Annotate \(shot.title)"
        window.identifier = NSUserInterfaceItemIdentifier("annotation-editor-\(shot.id.uuidString)")
        window.setFrameAutosaveName("annotation-editor-\(shot.id.uuidString)")

        super.init(window: window)

        canvasView.baseImage = baseImage
        canvasView.annotations = shot.annotations
        canvasView.currentStyle = .highlight
        canvasView.currentText = "Note"
        canvasView.onAnnotationsChange = { [weak self] annotations in
            self?.workingAnnotations = annotations
            self?.syncControls()
        }

        configureWindow()
        syncControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        onClose?(shotID)
    }

    private func configureWindow() {
        guard let window else {
            return
        }

        instructionsField.textColor = .secondaryLabelColor
        instructionsField.maximumNumberOfLines = 2
        instructionsField.translatesAutoresizingMaskIntoConstraints = false

        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(handleModeChange)
        modeControl.translatesAutoresizingMaskIntoConstraints = false

        textField.placeholderString = "Text label"
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.controlSize = .regular
        textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        [undoButton, clearButton, saveButton].forEach {
            $0.bezelStyle = .rounded
            $0.target = self
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        undoButton.action = #selector(handleUndo)
        clearButton.action = #selector(handleClear)
        saveButton.action = #selector(handleSave)
        saveButton.keyEquivalent = "\r"

        canvasView.translatesAutoresizingMaskIntoConstraints = false

        let toolbarRow = NSStackView(views: [modeControl, textField, undoButton, clearButton, saveButton])
        toolbarRow.orientation = .horizontal
        toolbarRow.spacing = 10
        toolbarRow.alignment = .centerY
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        contentView.addSubview(toolbarRow)
        contentView.addSubview(instructionsField)
        contentView.addSubview(canvasView)

        NSLayoutConstraint.activate([
            toolbarRow.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            toolbarRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            toolbarRow.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            instructionsField.topAnchor.constraint(equalTo: toolbarRow.bottomAnchor, constant: 12),
            instructionsField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            instructionsField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            canvasView.topAnchor.constraint(equalTo: instructionsField.bottomAnchor, constant: 16),
            canvasView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        window.delegate = self
    }

    private func syncControls() {
        canvasView.annotations = workingAnnotations
        canvasView.currentStyle = selectedStyle()
        canvasView.currentText = effectiveText()
        undoButton.isEnabled = workingAnnotations.isEmpty == false
        clearButton.isEnabled = workingAnnotations.isEmpty == false
        saveButton.isEnabled = workingAnnotations != savedAnnotations
        textField.isEnabled = selectedStyle() == .text
        textField.alphaValue = selectedStyle() == .text ? 1 : 0.55
        instructionsField.stringValue = instructionsText(for: selectedStyle())
        window?.isDocumentEdited = workingAnnotations != savedAnnotations
    }

    private func selectedStyle() -> ShotAnnotationStyle {
        ShotAnnotationStyle.allCases[modeControl.selectedSegment]
    }

    @objc
    private func handleModeChange() {
        canvasView.currentStyle = selectedStyle()
        syncControls()
    }

    @objc
    private func handleUndo() {
        canvasView.undoLastAnnotation()
    }

    @objc
    private func handleClear() {
        canvasView.clearAnnotations()
    }

    @objc
    private func handleSave() {
        savedAnnotations = workingAnnotations
        onSave?(shotID, workingAnnotations)
        syncControls()
    }

    public func controlTextDidChange(_ obj: Notification) {
        canvasView.currentText = effectiveText()
        canvasView.needsDisplay = true
    }

    private func effectiveText() -> String {
        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Text" : trimmed
    }

    private func instructionsText(for style: ShotAnnotationStyle) -> String {
        switch style {
        case .highlight:
            return "Drag to draw a highlight box. Save stores metadata only and keeps the original PNG untouched."
        case .redaction:
            return "Drag to draw a redaction box. Save stores metadata only and keeps the original PNG untouched."
        case .arrow:
            return "Drag to draw a directional arrow. Save stores metadata only and keeps the original PNG untouched."
        case .step:
            return "Click or drag to place numbered step markers. Save stores metadata only and keeps the original PNG untouched."
        case .text:
            return "Enter text in the field, then click or drag to place a text callout. Save stores metadata only and keeps the original PNG untouched."
        }
    }
}
