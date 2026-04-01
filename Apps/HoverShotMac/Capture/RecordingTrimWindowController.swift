import AVFoundation
import AVKit
import AppKit
import Foundation

@MainActor
public final class RecordingTrimWindowController: NSWindowController {
    public var onDidClose: ((String) -> Void)?
    public var onDidExport: ((URL) -> Void)?

    private let recording: RecordingItem
    private let trimExportService = RecordingTrimExportService()
    private let totalDuration: TimeInterval
    private let playerView = AVPlayerView()
    private let summaryField = NSTextField(labelWithString: "")
    private let startValueField = NSTextField(labelWithString: "")
    private let endValueField = NSTextField(labelWithString: "")
    private let durationValueField = NSTextField(labelWithString: "")
    private let startMarkerPopup = NSPopUpButton()
    private let endMarkerPopup = NSPopUpButton()
    private let startSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let endSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let playSelectionButton = NSButton(title: "Preview Trim", target: nil, action: nil)
    private let exportButton = NSButton(title: "Export Trimmed Video", target: nil, action: nil)

    public init(recording: RecordingItem) {
        self.recording = recording
        self.totalDuration = max(recording.duration ?? 0, 0.1)

        let window = NSWindow(
            contentRect: NSRect(x: 360, y: 220, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Trim Recording"
        window.identifier = NSUserInterfaceItemIdentifier("trim-recording-\(recording.id)")
        window.setFrameAutosaveName("TrimRecording")

        super.init(window: window)
        window.delegate = self

        configureWindow()
        configurePlayer()
        syncUI(seekTo: 0)
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

    private var minimumTrimDuration: TimeInterval {
        min(0.2, totalDuration)
    }

    private var selectedStartTime: TimeInterval {
        startSlider.doubleValue
    }

    private var selectedEndTime: TimeInterval {
        endSlider.doubleValue
    }

    private func configureWindow() {
        guard let window else {
            return
        }

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.wantsLayer = true
        playerView.layer?.cornerRadius = 18
        playerView.layer?.cornerCurve = .continuous
        playerView.translatesAutoresizingMaskIntoConstraints = false

        summaryField.font = .systemFont(ofSize: 13, weight: .regular)
        summaryField.textColor = .secondaryLabelColor
        summaryField.stringValue = recording.markers.isEmpty
            ? "Trim the beginning or end of this recording and save it as a new video."
            : "Trim the beginning or end of this recording. \(recording.markers.count) edit marker\(recording.markers.count == 1 ? "" : "s") available for snapping."
        summaryField.translatesAutoresizingMaskIntoConstraints = false

        let startLabel = makeLabel("Start")
        let endLabel = makeLabel("End")
        let durationLabel = makeLabel("Selection")
        let startMarkerLabel = makeLabel("Start Marker")
        let endMarkerLabel = makeLabel("End Marker")

        [startValueField, endValueField, durationValueField].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        configureMarkerPopups()

        [startMarkerPopup, endMarkerPopup].forEach {
            $0.target = self
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        startMarkerPopup.action = #selector(handleSelectStartMarker)
        endMarkerPopup.action = #selector(handleSelectEndMarker)

        [startSlider, endSlider].forEach {
            $0.minValue = 0
            $0.maxValue = totalDuration
            $0.target = self
            $0.action = #selector(handleSliderChanged(_:))
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        startSlider.doubleValue = 0
        endSlider.doubleValue = totalDuration

        playSelectionButton.bezelStyle = .rounded
        playSelectionButton.target = self
        playSelectionButton.action = #selector(handlePreviewSelection)

        exportButton.bezelStyle = .rounded
        exportButton.target = self
        exportButton.action = #selector(handleExportTrimmedVideo)

        let buttonRow = NSStackView(views: [playSelectionButton, exportButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        var metricRows: [[NSView]] = [
            [startLabel, startValueField],
            [endLabel, endValueField],
            [durationLabel, durationValueField]
        ]
        if recording.markers.isEmpty == false {
            metricRows.append([startMarkerLabel, startMarkerPopup])
            metricRows.append([endMarkerLabel, endMarkerPopup])
        }

        let metricsGrid = NSGridView(views: metricRows)
        metricsGrid.rowSpacing = 10
        metricsGrid.columnSpacing = 18
        metricsGrid.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(playerView)
        contentView.addSubview(summaryField)
        contentView.addSubview(metricsGrid)
        contentView.addSubview(startSlider)
        contentView.addSubview(endSlider)
        contentView.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            playerView.heightAnchor.constraint(equalToConstant: 320),

            summaryField.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 18),
            summaryField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            summaryField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            metricsGrid.topAnchor.constraint(equalTo: summaryField.bottomAnchor, constant: 18),
            metricsGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),

            startSlider.topAnchor.constraint(equalTo: metricsGrid.bottomAnchor, constant: 18),
            startSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            startSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            endSlider.topAnchor.constraint(equalTo: startSlider.bottomAnchor, constant: 12),
            endSlider.leadingAnchor.constraint(equalTo: startSlider.leadingAnchor),
            endSlider.trailingAnchor.constraint(equalTo: startSlider.trailingAnchor),

            buttonRow.topAnchor.constraint(equalTo: endSlider.bottomAnchor, constant: 20),
            buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            buttonRow.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    private func configurePlayer() {
        let player = AVPlayer(url: recording.url)
        playerView.player = player
    }

    private func makeLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func configureMarkerPopups() {
        startMarkerPopup.removeAllItems()
        endMarkerPopup.removeAllItems()

        startMarkerPopup.addItem(withTitle: "Set from marker…")
        endMarkerPopup.addItem(withTitle: "Set from marker…")

        for (index, marker) in recording.markers.enumerated() {
            let title = "Marker \(index + 1) · \(formattedDuration(marker.timestamp))"

            startMarkerPopup.addItem(withTitle: title)
            startMarkerPopup.lastItem?.representedObject = NSNumber(value: marker.timestamp)

            endMarkerPopup.addItem(withTitle: title)
            endMarkerPopup.lastItem?.representedObject = NSNumber(value: marker.timestamp)
        }

        startMarkerPopup.selectItem(at: 0)
        endMarkerPopup.selectItem(at: 0)
    }

    private func syncUI(seekTo time: TimeInterval?) {
        let selectedDuration = max(selectedEndTime - selectedStartTime, 0)

        startValueField.stringValue = formattedDuration(selectedStartTime)
        endValueField.stringValue = formattedDuration(selectedEndTime)
        durationValueField.stringValue = formattedDuration(selectedDuration)
        exportButton.isEnabled = selectedDuration >= 0.05

        if let time {
            playerView.player?.seek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let clamped = max(duration, 0)
        let totalTenths = Int((clamped * 10).rounded())
        let hours = totalTenths / 36000
        let minutes = (totalTenths % 36000) / 600
        let seconds = (totalTenths % 600) / 10
        let tenths = totalTenths % 10

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, seconds, tenths)
        }

        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }

    @objc
    private func handleSliderChanged(_ sender: NSSlider) {
        if sender === startSlider {
            let clamped = min(startSlider.doubleValue, endSlider.doubleValue - minimumTrimDuration)
            startSlider.doubleValue = max(0, clamped)
            syncUI(seekTo: startSlider.doubleValue)
            return
        }

        let clamped = max(endSlider.doubleValue, startSlider.doubleValue + minimumTrimDuration)
        endSlider.doubleValue = min(totalDuration, clamped)
        syncUI(seekTo: endSlider.doubleValue)
    }

    @objc
    private func handlePreviewSelection() {
        playerView.player?.seek(
            to: CMTime(seconds: selectedStartTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        playerView.player?.play()
    }

    @objc
    private func handleExportTrimmedVideo() {
        let startTime = selectedStartTime
        let endTime = selectedEndTime

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                guard let outputURL = try await trimExportService.exportInteractively(
                    recording: recording,
                    startTime: startTime,
                    endTime: endTime
                ) else {
                    return
                }

                onDidExport?(outputURL)
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                close()
            } catch {
                presentErrorAlert(
                    message: "Failed to export trimmed recording.",
                    detail: error.localizedDescription
                )
            }
        }
    }

    @objc
    private func handleSelectStartMarker() {
        guard startMarkerPopup.indexOfSelectedItem > 0 else {
            return
        }

        let timestamp = (startMarkerPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue ?? 0
        startSlider.doubleValue = min(timestamp, max(endSlider.doubleValue - minimumTrimDuration, 0))
        syncUI(seekTo: startSlider.doubleValue)
    }

    @objc
    private func handleSelectEndMarker() {
        guard endMarkerPopup.indexOfSelectedItem > 0 else {
            return
        }

        let timestamp = (endMarkerPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue ?? totalDuration
        endSlider.doubleValue = max(timestamp, min(startSlider.doubleValue + minimumTrimDuration, totalDuration))
        syncUI(seekTo: endSlider.doubleValue)
    }

    private func presentErrorAlert(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.beginSheetModal(for: window ?? NSWindow(), completionHandler: nil)
    }
}

extension RecordingTrimWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        playerView.player?.pause()
        onDidClose?(recording.id)
    }
}
