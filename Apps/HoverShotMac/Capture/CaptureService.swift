import AppKit
import Analysis
import Foundation
import Library
import ScreenCaptureKit
import Shared

public enum CaptureError: LocalizedError, Equatable {
    case screenRecordingPermissionRequired
    case screenRecordingPermissionDenied
    case selectionAlreadyInProgress
    case timedCaptureAlreadyInProgress
    case selectionCancelled
    case noShareableWindows
    case windowSelectionCancelled
    case noPreviousSelection
    case displayUnavailable
    case imageCaptureFailed

    public var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "Screen Recording permission is required. After granting it in System Settings, close and reopen HoverShot."
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission was previously denied. Allow HoverShot in System Settings, then close and reopen the app."
        case .selectionAlreadyInProgress:
            return "A capture selection is already in progress."
        case .timedCaptureAlreadyInProgress:
            return "A timed capture countdown is already in progress."
        case .selectionCancelled:
            return "The selection was cancelled."
        case .noShareableWindows:
            return "There are no shareable windows available to capture right now."
        case .windowSelectionCancelled:
            return "The window selection was cancelled."
        case .noPreviousSelection:
            return "There is no previous capture area yet."
        case .displayUnavailable:
            return "The selected display is no longer available."
        case .imageCaptureFailed:
            return "The selected area could not be captured."
        }
    }
}

@MainActor
public final class CaptureService {
    private let permissionService: PermissionService
    private let shotStore: ShotStore
    private let captureAreaStore: CaptureAreaStore

    private var activeSelectionSession: AreaSelectionSession?
    private var activeTimedCaptureTask: Task<Void, Never>?
    private var timedCaptureCountdownWindowController: TimedCaptureCountdownWindowController?
    private let titleFormatter: DateFormatter
    private let windowPicker = WindowPicker()

    public init(
        permissionService: PermissionService,
        shotStore: ShotStore
    ) {
        self.permissionService = permissionService
        self.shotStore = shotStore
        self.captureAreaStore = CaptureAreaStore()

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        self.titleFormatter = formatter
    }

    public func startInteractiveCapture(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) {
        guard canStartCaptureFlow(completion: completion) else {
            return
        }

        beginInteractiveCapture(completion: completion)
    }

    public func startTimedInteractiveCapture(
        delayInSeconds: Int,
        completion: @escaping (Result<Shot, Error>) -> Void
    ) {
        guard delayInSeconds > 0 else {
            startInteractiveCapture(completion: completion)
            return
        }

        guard activeSelectionSession == nil else {
            completion(.failure(CaptureError.selectionAlreadyInProgress))
            return
        }

        guard activeTimedCaptureTask == nil else {
            completion(.failure(CaptureError.timedCaptureAlreadyInProgress))
            return
        }

        guard ensureScreenCapturePermission(completion: completion) else {
            return
        }

        let countdownWindowController = TimedCaptureCountdownWindowController()
        timedCaptureCountdownWindowController = countdownWindowController

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            for remaining in stride(from: delayInSeconds, through: 1, by: -1) {
                guard Task.isCancelled == false else {
                    countdownWindowController.closeOverlay()
                    timedCaptureCountdownWindowController = nil
                    activeTimedCaptureTask = nil
                    return
                }

                countdownWindowController.show(remainingSeconds: remaining)
                NSSound.beep()

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    countdownWindowController.closeOverlay()
                    timedCaptureCountdownWindowController = nil
                    activeTimedCaptureTask = nil
                    return
                }
            }

            countdownWindowController.closeOverlay()
            timedCaptureCountdownWindowController = nil
            activeTimedCaptureTask = nil
            beginInteractiveCapture(completion: completion)
        }

        activeTimedCaptureTask = task
    }

    public func recaptureLastArea(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) {
        guard let area = captureAreaStore.load() else {
            completion(.failure(CaptureError.noPreviousSelection))
            return
        }

        Task {
            completion(await capture(area: area))
        }
    }

    public func startWindowCapture(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) {
        guard activeTimedCaptureTask == nil else {
            completion(.failure(CaptureError.timedCaptureAlreadyInProgress))
            return
        }

        guard ensureScreenCapturePermission(completion: completion) else {
            return
        }

        Task {
            do {
                let windows = try await shareableWindows()
                guard windows.isEmpty == false else {
                    completion(.failure(CaptureError.noShareableWindows))
                    return
                }

                guard let selectedWindow = windowPicker.chooseWindow(from: windows) else {
                    completion(.failure(CaptureError.windowSelectionCancelled))
                    return
                }

                completion(await capture(window: selectedWindow))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func canStartCaptureFlow(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) -> Bool {
        guard activeSelectionSession == nil else {
            completion(.failure(CaptureError.selectionAlreadyInProgress))
            return false
        }

        guard activeTimedCaptureTask == nil else {
            completion(.failure(CaptureError.timedCaptureAlreadyInProgress))
            return false
        }

        guard ensureScreenCapturePermission(completion: completion) else {
            return false
        }

        return true
    }

    private func ensureScreenCapturePermission(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) -> Bool {
        switch permissionService.currentSnapshot().screenCapture {
        case .authorized:
            return true
        case .notDetermined:
            _ = permissionService.requestScreenCaptureAccess()
            completion(.failure(CaptureError.screenRecordingPermissionRequired))
            return false
        case .denied:
            completion(.failure(CaptureError.screenRecordingPermissionDenied))
            return false
        }
    }

    private func beginInteractiveCapture(
        completion: @escaping (Result<Shot, Error>) -> Void
    ) {
        let session = AreaSelectionSession { [weak self] result in
            guard let self else {
                return
            }

            self.activeSelectionSession = nil

            switch result {
            case let .success(area):
                Task {
                    completion(await self.capture(area: area))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }

        activeSelectionSession = session
        session.start()
    }

    private func capture(area: CaptureArea) async -> Result<Shot, Error> {
        do {
            let image = try await captureImage(for: area)
            let title = "Capture \(titleFormatter.string(from: .now))"
            let shot = try shotStore.createShot(image: image, title: title)
            captureAreaStore.save(area)
            enrichShotWithRecognizedText(shotID: shot.id, image: image)
            return .success(shot)
        } catch {
            return .failure(error)
        }
    }

    private func capture(window: SCWindow) async -> Result<Shot, Error> {
        do {
            let image = try await captureImage(for: window)
            let appName = window.owningApplication?.applicationName ?? "Window"
            let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = (windowTitle?.isEmpty == false ? windowTitle! : "Untitled")
            let shot = try shotStore.createShot(
                image: image,
                title: "\(appName) - \(suffix)"
            )
            enrichShotWithRecognizedText(shotID: shot.id, image: image)
            return .success(shot)
        } catch {
            return .failure(error)
        }
    }

    private func enrichShotWithRecognizedText(shotID: UUID, image: NSImage) {
        Task { @MainActor [shotStore] in
            let recognizedText = try? await TextRecognitionService().recognizeText(in: image)
            try? shotStore.updateRecognizedText(for: shotID, to: recognizedText)
        }
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

    private func captureImage(for area: CaptureArea) async throws -> NSImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = shareableContent.displays.first(where: { $0.displayID == area.displayID }) else {
            throw CaptureError.displayUnavailable
        }

        guard let screen = NSScreen.screens.first(where: { $0.screenHoveringDisplayID == area.displayID }) else {
            throw CaptureError.displayUnavailable
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let sourceRect = sourceRect(for: area, on: screen)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.sourceRect = sourceRect
        configuration.width = max(Int(area.rect.width.rounded()), 1)
        configuration.height = max(Int(area.rect.height.rounded()), 1)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(
            cgImage: image,
            size: NSSize(
                width: sourceRect.width,
                height: sourceRect.height
            )
        )
    }

    private func sourceRect(
        for area: CaptureArea,
        on screen: NSScreen
    ) -> CGRect {
        let scale = max(screen.backingScaleFactor, 1)
        let localPointRect = CGRect(
            x: area.rect.x / scale,
            y: area.rect.y / scale,
            width: area.rect.width / scale,
            height: area.rect.height / scale
        )
        let displayHeight = screen.frame.height
        let topOriginY = max(0, displayHeight - localPointRect.maxY)

        return CGRect(
            x: max(0, localPointRect.minX),
            y: topOriginY,
            width: localPointRect.width,
            height: localPointRect.height
        ).integral
    }

    private func captureImage(for window: SCWindow) async throws -> NSImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let contentInfo = SCShareableContent.info(for: filter)
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.width = max(Int((contentInfo.contentRect.width * CGFloat(contentInfo.pointPixelScale)).rounded()), 1)
        configuration.height = max(Int((contentInfo.contentRect.height * CGFloat(contentInfo.pointPixelScale)).rounded()), 1)

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return NSImage(
            cgImage: image,
            size: NSSize(
                width: contentInfo.contentRect.width,
                height: contentInfo.contentRect.height
            )
        )
    }
}
