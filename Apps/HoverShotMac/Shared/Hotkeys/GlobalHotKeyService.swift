import Carbon
import Foundation

public final class GlobalHotKeyService {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [HotKeyAction: EventHotKeyRef] = [:]
    private var registeredActionsByID: [UInt32: HotKeyAction] = [:]
    private var onAction: ((HotKeyAction) -> Void)?

    private let hotKeySignature = OSType(0x53485652) // SHVR

    public init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregisterAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func registerHotKeys(
        _ shortcuts: [HotKeyAction: HotKeyShortcut],
        handler: @escaping (HotKeyAction) -> Void
    ) {
        onAction = handler
        unregisterAll()

        for action in HotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else {
                continue
            }

            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: hotKeySignature,
                id: action.registrationID
            )

            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else {
                NSLog("Failed to register hotkey for action %@ (status=%d)", action.rawValue, status)
                continue
            }

            hotKeyRefs[action] = hotKeyRef
            registeredActionsByID[action.registrationID] = action
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData, let eventRef else {
                return noErr
            }

            let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard
                status == noErr,
                hotKeyID.signature == service.hotKeySignature,
                let action = service.registeredActionsByID[hotKeyID.id]
            else {
                return noErr
            }

            service.onAction?(action)
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
        registeredActionsByID.removeAll()
    }
}
