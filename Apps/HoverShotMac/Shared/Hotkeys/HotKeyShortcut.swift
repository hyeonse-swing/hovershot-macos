import AppKit
import Carbon
import Foundation

public struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard Self.isModifierOnlyKeyCode(UInt32(keyCode)) == false else {
            return nil
        }

        let modifiers = Self.carbonModifiers(from: modifierFlags)
        guard modifiers != 0 else {
            return nil
        }

        self.init(keyCode: UInt32(keyCode), carbonModifiers: modifiers)
    }

    public var displayString: String {
        HotKeyFormatter.string(for: self)
    }

    public static func carbonModifiers(from modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0

        if modifierFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if modifierFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if modifierFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if modifierFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }

        return modifiers
    }

    public static func isModifierOnlyKeyCode(_ keyCode: UInt32) -> Bool {
        switch Int(keyCode) {
        case kVK_Command,
            kVK_RightCommand,
            kVK_Shift,
            kVK_RightShift,
            kVK_Option,
            kVK_RightOption,
            kVK_Control,
            kVK_RightControl,
            kVK_CapsLock,
            kVK_Function:
            return true
        default:
            return false
        }
    }
}
