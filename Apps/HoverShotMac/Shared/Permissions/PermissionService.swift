import AVFoundation
import CoreGraphics
import Foundation

public enum AppPermissionState: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public struct PermissionSnapshot: Equatable, Sendable {
    public let screenCapture: AppPermissionState
    public let microphone: AppPermissionState

    public init(
        screenCapture: AppPermissionState,
        microphone: AppPermissionState
    ) {
        self.screenCapture = screenCapture
        self.microphone = microphone
    }
}

public final class PermissionService {
    private let defaults: UserDefaults
    private let screenCaptureRequestKey = "screenHovering.didRequestScreenCaptureAccess"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func currentSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            screenCapture: currentScreenCaptureState(),
            microphone: currentMicrophoneState()
        )
    }

    @discardableResult
    public func requestScreenCaptureAccess() -> Bool {
        defaults.set(true, forKey: screenCaptureRequestKey)
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    public func requestMicrophoneAccess(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func currentScreenCaptureState() -> AppPermissionState {
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }

        if defaults.bool(forKey: screenCaptureRequestKey) {
            return .denied
        }

        return .notDetermined
    }

    private func currentMicrophoneState() -> AppPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .restricted, .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }
}
