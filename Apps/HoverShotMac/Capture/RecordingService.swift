import AVFoundation
import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit
import Shared

public enum RecordingState: Equatable, Sendable {
    case idle
    case selectingArea
    case starting(URL)
    case recording(URL)
    case paused(String)
    case stopping(URL)
}

public enum RecordingError: LocalizedError, Equatable {
    case requiresMacOS15
    case screenRecordingPermissionRequired
    case screenRecordingPermissionDenied
    case selectionAlreadyInProgress
    case recordingAlreadyInProgress
    case noActiveRecording
    case noPausedRecording
    case markerUnavailable
    case noShareableWindows
    case windowSelectionCancelled
    case selectionCancelled
    case displayUnavailable
    case failedToPrepareOutputDirectory

    public var errorDescription: String? {
        switch self {
        case .requiresMacOS15:
            return "Screen recording requires macOS 15 or later in the current implementation."
        case .screenRecordingPermissionRequired:
            return "Screen Recording permission is required. After granting it in System Settings, close and reopen HoverShot."
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission was previously denied. Allow HoverShot in System Settings, then close and reopen the app."
        case .selectionAlreadyInProgress:
            return "A capture or recording selection is already in progress."
        case .recordingAlreadyInProgress:
            return "A recording is already in progress."
        case .noActiveRecording:
            return "There is no active recording to stop."
        case .noPausedRecording:
            return "There is no paused recording session to resume."
        case .markerUnavailable:
            return "An edit marker can only be added after recording has fully started."
        case .noShareableWindows:
            return "There are no shareable windows available to record right now."
        case .windowSelectionCancelled:
            return "The window selection was cancelled."
        case .selectionCancelled:
            return "The selection was cancelled."
        case .displayUnavailable:
            return "The selected display is no longer available."
        case .failedToPrepareOutputDirectory:
            return "The recordings folder could not be prepared."
        }
    }
}

@MainActor
public final class RecordingService: NSObject {
    public var onStateChange: ((RecordingState) -> Void)?
    public var onFinish: ((URL) -> Void)?
    public var onPause: ((URL) -> Void)?
    public var onError: ((Error) -> Void)?

    public private(set) var state: RecordingState = .idle {
        didSet {
            onStateChange?(state)
        }
    }

    private let permissionService: PermissionService
    private let recordingStore: RecordingStore
    private let windowPicker = WindowPicker()

    private var activeSelectionSession: AreaSelectionSession?
    private var activeRecordingSession: AnyObject?
    private var resumeContext: RecordingResumeContext?

    public init(
        permissionService: PermissionService,
        recordingStore: RecordingStore = RecordingStore()
    ) {
        self.permissionService = permissionService
        self.recordingStore = recordingStore

        super.init()
    }

    public func startAreaRecording(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard activeSelectionSession == nil else {
            completion(.failure(RecordingError.selectionAlreadyInProgress))
            return
        }

        guard hasOngoingRecordingSession == false else {
            completion(.failure(RecordingError.recordingAlreadyInProgress))
            return
        }

        switch permissionService.currentSnapshot().screenCapture {
        case .authorized:
            break
        case .notDetermined:
            _ = permissionService.requestScreenCaptureAccess()
            completion(.failure(RecordingError.screenRecordingPermissionRequired))
            return
        case .denied:
            completion(.failure(RecordingError.screenRecordingPermissionDenied))
            return
        }

        state = .selectingArea

        let session = AreaSelectionSession { [weak self] result in
            guard let self else {
                return
            }

            self.activeSelectionSession = nil

            switch result {
            case let .success(area):
                Task {
                    await self.startRecording(area: area, completion: completion)
                }
            case let .failure(error):
                self.state = .idle
                if error == .selectionCancelled {
                    completion(.failure(RecordingError.selectionCancelled))
                } else {
                    completion(.failure(error))
                }
            }
        }

        activeSelectionSession = session
        session.start()
    }

    public func startWindowRecording(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard hasOngoingRecordingSession == false else {
            completion(.failure(RecordingError.recordingAlreadyInProgress))
            return
        }

        switch permissionService.currentSnapshot().screenCapture {
        case .authorized:
            break
        case .notDetermined:
            _ = permissionService.requestScreenCaptureAccess()
            completion(.failure(RecordingError.screenRecordingPermissionRequired))
            return
        case .denied:
            completion(.failure(RecordingError.screenRecordingPermissionDenied))
            return
        }

        Task {
            do {
                let windows = try await shareableWindows()
                guard windows.isEmpty == false else {
                    completion(.failure(RecordingError.noShareableWindows))
                    return
                }

                guard let selectedWindow = windowPicker.chooseWindow(from: windows, purpose: "Record Window") else {
                    completion(.failure(RecordingError.windowSelectionCancelled))
                    return
                }

                await startRecording(window: selectedWindow, completion: completion)
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func stopRecording(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        if activeRecordingSession == nil, resumeContext != nil {
            resumeContext = nil
            state = .idle
            completion(.success(()))
            return
        }

        guard
            #available(macOS 15.0, *),
            let activeRecordingSession = activeRecordingSession as? ActiveRecordingSession
        else {
            completion(.failure(RecordingError.noActiveRecording))
            return
        }

        state = .stopping(activeRecordingSession.outputURL)

        Task {
            do {
                try await activeRecordingSession.stop()
                completion(.success(()))
            } catch {
                completeRecording(with: .failure(error))
                completion(.failure(error))
            }
        }
    }

    public func pauseRecording(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard
            #available(macOS 15.0, *),
            let activeRecordingSession = activeRecordingSession as? ActiveRecordingSession
        else {
            completion(.failure(RecordingError.noActiveRecording))
            return
        }

        state = .stopping(activeRecordingSession.outputURL)

        Task {
            do {
                try await activeRecordingSession.pause()
                completion(.success(()))
            } catch {
                completeRecording(with: .failure(error))
                completion(.failure(error))
            }
        }
    }

    public func resumeRecording(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard #available(macOS 15.0, *) else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard activeRecordingSession == nil else {
            completion(.failure(RecordingError.recordingAlreadyInProgress))
            return
        }

        guard let resumeContext else {
            completion(.failure(RecordingError.noPausedRecording))
            return
        }

        Task {
            do {
                let outputURL = try outputURL(
                    for: resumeContext.outputPrefix,
                    segmentIndex: resumeContext.nextSegmentIndex
                )
                try await beginRecording(
                    filter: resumeContext.filter,
                    configuration: resumeContext.configuration,
                    outputURL: outputURL,
                    outputPrefix: resumeContext.outputPrefix,
                    nextSegmentIndex: resumeContext.nextSegmentIndex + 1
                )
                completion(.success(()))
            } catch {
                state = .paused(resumeContext.outputPrefix)
                completion(.failure(error))
            }
        }
    }

    public func addEditMarker(
        completion: @escaping (Result<RecordingEditMarker, Error>) -> Void
    ) {
        guard availabilityIsSupported else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        guard
            #available(macOS 15.0, *),
            let activeRecordingSession = activeRecordingSession as? ActiveRecordingSession
        else {
            completion(.failure(RecordingError.noActiveRecording))
            return
        }

        guard let elapsedTime = activeRecordingSession.currentElapsedTime() else {
            completion(.failure(RecordingError.markerUnavailable))
            return
        }

        do {
            let marker = try recordingStore.addMarker(to: activeRecordingSession.outputURL, at: elapsedTime)
            NSSound.beep()
            completion(.success(marker))
        } catch {
            completion(.failure(error))
        }
    }

    private var availabilityIsSupported: Bool {
        if #available(macOS 15.0, *) {
            return true
        }

        return false
    }

    private var hasOngoingRecordingSession: Bool {
        activeRecordingSession != nil || resumeContext != nil
    }

    private func startRecording(
        area: CaptureArea,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        guard #available(macOS 15.0, *) else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = shareableContent.displays.first(where: { $0.displayID == area.displayID }) else {
                throw RecordingError.displayUnavailable
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let configuration = makeAreaStreamConfiguration(for: area, displayID: area.displayID)
            let outputPrefix = "Area Recording"
            let outputURL = try outputURL(for: outputPrefix, segmentIndex: 1)
            try await beginRecording(
                filter: filter,
                configuration: configuration,
                outputURL: outputURL,
                outputPrefix: outputPrefix,
                nextSegmentIndex: 2
            )
            completion(.success(()))
        } catch {
            state = .idle
            completion(.failure(error))
        }
    }

    private func startRecording(
        window: SCWindow,
        completion: @escaping (Result<Void, Error>) -> Void
    ) async {
        guard #available(macOS 15.0, *) else {
            completion(.failure(RecordingError.requiresMacOS15))
            return
        }

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let contentInfo = SCShareableContent.info(for: filter)
            let configuration = makeWindowStreamConfiguration(contentInfo: contentInfo)
            let prefix = [
                window.owningApplication?.applicationName ?? "Window",
                sanitizedWindowTitle(window.title)
            ].joined(separator: " - ")
            let outputURL = try outputURL(for: prefix, segmentIndex: 1)
            try await beginRecording(
                filter: filter,
                configuration: configuration,
                outputURL: outputURL,
                outputPrefix: prefix,
                nextSegmentIndex: 2
            )
            completion(.success(()))
        } catch {
            state = .idle
            completion(.failure(error))
        }
    }

    @available(macOS 15.0, *)
    private func beginRecording(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        outputURL: URL,
        outputPrefix: String,
        nextSegmentIndex: Int
    ) async throws {
        state = .starting(outputURL)
        let currentSegmentIndex = max(nextSegmentIndex - 1, 1)
        try recordingStore.prepareSegmentMetadata(
            for: outputURL,
            sessionName: outputPrefix,
            segmentIndex: currentSegmentIndex
        )
        resumeContext = RecordingResumeContext(
            filter: filter,
            configuration: configuration,
            outputPrefix: outputPrefix,
            nextSegmentIndex: nextSegmentIndex
        )

        let recordingSession = try ActiveRecordingSession(
            filter: filter,
            configuration: configuration,
            outputURL: outputURL
        )
        recordingSession.onDidStart = { [weak self] outputURL in
            self?.state = .recording(outputURL)
        }
        recordingSession.onComplete = { [weak self] result in
            self?.completeRecording(with: result)
        }

        activeRecordingSession = recordingSession
        try await recordingSession.start()
    }

    private func completeRecording(with result: RecordingSessionResult) {
        activeRecordingSession = nil

        switch result {
        case let .finished(outputURL):
            state = .idle
            resumeContext = nil
            onFinish?(outputURL)
        case let .paused(outputURL):
            if let resumeContext {
                state = .paused(resumeContext.outputPrefix)
            } else {
                state = .paused(outputURL.deletingPathExtension().lastPathComponent)
            }
            onPause?(outputURL)
        case let .failure(error):
            state = .idle
            resumeContext = nil
            onError?(error)
        }
    }

    private func outputURL(
        for outputPrefix: String,
        segmentIndex: Int
    ) throws -> URL {
        let prefix = if segmentIndex <= 1 {
            outputPrefix
        } else {
            "\(outputPrefix) Part \(segmentIndex)"
        }

        return try recordingStore.nextOutputURL(prefix: prefix)
    }

    private func makeAreaStreamConfiguration(
        for area: CaptureArea,
        displayID: UInt32
    ) -> SCStreamConfiguration {
        let configuration = makeBaseStreamConfiguration()
        guard let screen = NSScreen.screens.first(where: { $0.screenHoveringDisplayID == displayID }) else {
            return configuration
        }
        let scale = max(screen.backingScaleFactor, 1)
        let localPointRect = CGRect(
            x: area.rect.x / scale,
            y: area.rect.y / scale,
            width: area.rect.width / scale,
            height: area.rect.height / scale
        )
        let sourceRect = CGRect(
            x: max(0, localPointRect.minX),
            y: max(0, screen.frame.height - localPointRect.maxY),
            width: localPointRect.width,
            height: localPointRect.height
        ).integral

        configuration.sourceRect = sourceRect
        configuration.width = max(Int(area.rect.width.rounded()), 1)
        configuration.height = max(Int(area.rect.height.rounded()), 1)
        return configuration
    }

    private func makeWindowStreamConfiguration(
        contentInfo: SCShareableContentInfo
    ) -> SCStreamConfiguration {
        let configuration = makeBaseStreamConfiguration()
        configuration.width = max(Int((contentInfo.contentRect.width * CGFloat(contentInfo.pointPixelScale)).rounded()), 1)
        configuration.height = max(Int((contentInfo.contentRect.height * CGFloat(contentInfo.pointPixelScale)).rounded()), 1)
        configuration.scalesToFit = true
        return configuration
    }

    private func makeBaseStreamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = true
        configuration.queueDepth = 6
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true

        if #available(macOS 15.0, *) {
            configuration.showMouseClicks = true
            configuration.captureMicrophone = permissionService.currentSnapshot().microphone == .authorized
        }

        return configuration
    }

    private func shareableWindows() async throws -> [SCWindow] {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        return shareableContent.windows
            .filter { window in
                window.windowLayer == 0 &&
                window.frame.width >= 80 &&
                window.frame.height >= 60 &&
                window.owningApplication?.processID != currentProcessID
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && rhs.isActive == false
                }

                let lhsApp = lhs.owningApplication?.applicationName ?? ""
                let rhsApp = rhs.owningApplication?.applicationName ?? ""
                if lhsApp != rhsApp {
                    return lhsApp.localizedCaseInsensitiveCompare(rhsApp) == .orderedAscending
                }

                let lhsTitle = lhs.title ?? ""
                let rhsTitle = rhs.title ?? ""
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
    }

    private func sanitizedWindowTitle(_ title: String?) -> String {
        guard let title, title.isEmpty == false else {
            return "Untitled Window"
        }

        return title
    }
}

private struct RecordingResumeContext {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    let outputPrefix: String
    let nextSegmentIndex: Int
}

private enum RecordingSessionResult {
    case finished(URL)
    case paused(URL)
    case failure(Error)
}

@available(macOS 15.0, *)
private final class ActiveRecordingSession: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    private enum CompletionDisposition {
        case finish
        case pause
    }

    let outputURL: URL

    var onDidStart: ((URL) -> Void)?
    var onComplete: ((RecordingSessionResult) -> Void)?

    private var stream: SCStream!
    private var recordingOutput: SCRecordingOutput!
    private var hasCompleted = false
    private var startedAt: Date?
    private var completionDisposition: CompletionDisposition = .finish
    private let lock = NSLock()

    init(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        outputURL: URL
    ) throws {
        self.outputURL = outputURL

        super.init()

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.videoCodecType = .h264
        recordingConfiguration.outputFileType = .mp4

        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )
        self.recordingOutput = recordingOutput

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        self.stream = stream
    }

    func start() async throws {
        try stream.addRecordingOutput(recordingOutput)
        try await stream.startCapture()
    }

    func stop() async throws {
        setCompletionDisposition(.finish)
        try await stream.stopCapture()
    }

    func pause() async throws {
        setCompletionDisposition(.pause)
        try await stream.stopCapture()
    }

    func currentElapsedTime() -> TimeInterval? {
        lock.lock()
        let startedAt = self.startedAt
        lock.unlock()

        guard let startedAt else {
            return nil
        }

        return max(Date().timeIntervalSince(startedAt), 0)
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        lock.lock()
        startedAt = Date()
        lock.unlock()

        let didStart = onDidStart
        DispatchQueue.main.async { [outputURL] in
            didStart?(outputURL)
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        lock.lock()
        let completionDisposition = self.completionDisposition
        lock.unlock()

        switch completionDisposition {
        case .finish:
            completeIfNeeded(.finished(outputURL))
        case .pause:
            completeIfNeeded(.paused(outputURL))
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        completeIfNeeded(.failure(error))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        completeIfNeeded(.failure(error))
    }

    private func completeIfNeeded(_ result: RecordingSessionResult) {
        lock.lock()
        defer { lock.unlock() }

        guard hasCompleted == false else {
            return
        }

        hasCompleted = true
        let completion = onComplete
        DispatchQueue.main.async {
            completion?(result)
        }
    }

    private func setCompletionDisposition(_ disposition: CompletionDisposition) {
        lock.lock()
        completionDisposition = disposition
        lock.unlock()
    }
}
