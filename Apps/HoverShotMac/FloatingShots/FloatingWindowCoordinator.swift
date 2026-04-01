import AppKit
import Library

@MainActor
public final class FloatingWindowCoordinator {
    private let shotStore: ShotStore
    private var controllers: [UUID: FloatingShotWindowController] = [:]

    public var onAnnotateRequested: ((UUID) -> Void)?
    public var onCopyImageRequested: ((UUID) -> Void)?
    public var onExportRequested: ((UUID) -> Void)?
    public var onRevealInFinderRequested: ((UUID) -> Void)?
    public var onDragFileURLRequested: ((UUID) -> URL?)?

    public init(shotStore: ShotStore) {
        self.shotStore = shotStore
    }

    public func restoreVisibleShots() throws {
        try restoreShots(includeHidden: false)
    }

    public func restoreAllShots() throws {
        try restoreShots(includeHidden: true)
    }

    private func restoreShots(includeHidden: Bool) throws {
        let shots = try shotStore.loadShots()

        for shot in shots where includeHidden || shot.floatingState.isVisible {
            try present(shot)
        }
    }

    public func present(_ shot: Shot) throws {
        var shot = shot
        shot.floatingState.isVisible = true
        try? shotStore.upsert(shot)

        guard let image = shotStore.loadRenderedImage(for: shot) else {
            return
        }

        let controller: FloatingShotWindowController
        if let existing = controllers[shot.id] {
            controller = existing
            controller.update(shot: shot, image: image)
        } else {
            controller = FloatingShotWindowController(shot: shot, image: image)
            controller.onStateChange = { [weak self] shotID, state in
                self?.persistFloatingState(for: shotID, state: state)
            }
            controller.onAnnotateRequested = { [weak self] shotID in
                self?.onAnnotateRequested?(shotID)
            }
            controller.onCopyImageRequested = { [weak self] shotID in
                self?.onCopyImageRequested?(shotID)
            }
            controller.onExportRequested = { [weak self] shotID in
                self?.onExportRequested?(shotID)
            }
            controller.onRevealInFinderRequested = { [weak self] shotID in
                self?.onRevealInFinderRequested?(shotID)
            }
            controller.onDragFileURLRequested = { [weak self] shotID in
                self?.onDragFileURLRequested?(shotID)
            }
            controllers[shot.id] = controller
        }

        controller.reveal()
    }

    public func disableClickThroughForAllShots() {
        for controller in controllers.values {
            controller.disableClickThrough()
        }

        guard var shots = try? shotStore.loadShots() else {
            return
        }

        var changed = false
        for index in shots.indices where shots[index].floatingState.ignoresMouseEvents {
            shots[index].floatingState.ignoresMouseEvents = false
            changed = true
        }

        if changed {
            try? shotStore.save(shots: shots)
        }
    }

    public func closeShot(withID shotID: UUID) {
        guard let controller = controllers.removeValue(forKey: shotID) else {
            return
        }

        controller.window?.close()
    }

    public func refreshShotIfPresented(withID shotID: UUID) {
        guard let controller = controllers[shotID] else {
            return
        }

        guard
            let shot = try? shotStore.loadShot(withID: shotID),
            let image = shotStore.loadRenderedImage(for: shot)
        else {
            return
        }

        controller.update(shot: shot, image: image)
    }

    private func persistFloatingState(for shotID: UUID, state: FloatingShotState) {
        try? shotStore.updateFloatingState(for: shotID, to: state)

        if state.isVisible == false {
            controllers[shotID] = nil
        }
    }
}
