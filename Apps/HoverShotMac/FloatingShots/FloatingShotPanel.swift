@preconcurrency import AppKit

final class FloatingShotPanel: NSPanel {
    var onCopyRequested: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard
            event.type == .keyDown,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
            event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }

        onCopyRequested?()
        return true
    }
}
