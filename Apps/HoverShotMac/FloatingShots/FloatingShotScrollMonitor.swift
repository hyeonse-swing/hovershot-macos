import AppKit

final class FloatingShotScrollMonitor {
    var onScrollEvent: ((Double, NSPoint) -> Void)?

    private var eventMonitor: Any?

    init() {
        install()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func install() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else {
                return event
            }

            self.onScrollEvent?(event.scrollingDeltaY * -0.01, NSEvent.mouseLocation)
            return event
        }
    }
}
