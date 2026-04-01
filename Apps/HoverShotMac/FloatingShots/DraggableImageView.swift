import AppKit

final class DraggableImageView: NSImageView, NSDraggingSource {
    var draggingPasteboardWriterProvider: (() -> (any NSPasteboardWriting)?)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
