import AppKit

@main
struct HoverShotApp {
    @MainActor
    private static var coordinator: AppCoordinator?

    static func main() {
        let app = NSApplication.shared

        app.setActivationPolicy(.accessory)
        app.delegate = nil

        Task { @MainActor in
            let coordinator = AppCoordinator()
            self.coordinator = coordinator
            coordinator.start()
        }

        app.run()
    }
}
