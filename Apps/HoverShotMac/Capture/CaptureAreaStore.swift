import Foundation

final class CaptureAreaStore {
    private let defaults: UserDefaults
    private let key = "screenHovering.lastCaptureArea"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CaptureArea? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? decoder.decode(CaptureArea.self, from: data)
    }

    func save(_ area: CaptureArea) {
        guard let data = try? encoder.encode(area) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
