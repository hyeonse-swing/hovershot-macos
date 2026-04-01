import Carbon
import Foundation

public enum HotKeyAction: String, Codable, CaseIterable, Hashable, Sendable {
    case captureArea
    case captureWindow
    case recaptureLastArea
    case timedCapture3Seconds
    case openShotsBrowser
    case openRecordingsBrowser
    case importFromClipboard
    case recordArea
    case recordWindow
    case pauseRecording
    case resumeRecording
    case addEditMarker
    case stopRecording

    public var displayName: String {
        switch self {
        case .captureArea:
            return "Capture Area"
        case .captureWindow:
            return "Capture Window"
        case .recaptureLastArea:
            return "Re-capture Last Area"
        case .timedCapture3Seconds:
            return "Timed Capture (3s)"
        case .openShotsBrowser:
            return "Open Shots Browser"
        case .openRecordingsBrowser:
            return "Open Recordings Browser"
        case .importFromClipboard:
            return "Import From Clipboard"
        case .recordArea:
            return "Record Area"
        case .recordWindow:
            return "Record Window"
        case .pauseRecording:
            return "Pause Recording"
        case .resumeRecording:
            return "Resume Recording"
        case .addEditMarker:
            return "Add Edit Marker"
        case .stopRecording:
            return "Stop Recording"
        }
    }

    public var defaultShortcut: HotKeyShortcut? {
        switch self {
        case .captureArea:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .captureWindow:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .recaptureLastArea:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_8), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .timedCapture3Seconds:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_9), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .openShotsBrowser:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(cmdKey | optionKey))
        case .openRecordingsBrowser:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(cmdKey | optionKey))
        case .importFromClipboard:
            return nil
        case .recordArea:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(cmdKey | controlKey | shiftKey))
        case .recordWindow:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: UInt32(cmdKey | controlKey | shiftKey))
        case .pauseRecording:
            return nil
        case .resumeRecording:
            return nil
        case .addEditMarker:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_M), carbonModifiers: UInt32(cmdKey | controlKey | shiftKey))
        case .stopRecording:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_0), carbonModifiers: UInt32(cmdKey | controlKey | shiftKey))
        }
    }

    var registrationID: UInt32 {
        switch self {
        case .captureArea:
            return 1
        case .captureWindow:
            return 2
        case .recaptureLastArea:
            return 3
        case .timedCapture3Seconds:
            return 4
        case .openShotsBrowser:
            return 5
        case .openRecordingsBrowser:
            return 6
        case .importFromClipboard:
            return 7
        case .recordArea:
            return 8
        case .recordWindow:
            return 9
        case .pauseRecording:
            return 10
        case .resumeRecording:
            return 11
        case .addEditMarker:
            return 12
        case .stopRecording:
            return 13
        }
    }
}
