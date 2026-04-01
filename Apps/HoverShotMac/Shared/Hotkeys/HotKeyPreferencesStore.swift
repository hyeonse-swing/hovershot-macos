import Foundation

public final class HotKeyPreferencesStore {
    private enum Storage {
        static let defaultsKey = "hovershot.hotkeys.v1"
    }

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> [HotKeyAction: HotKeyShortcut] {
        guard
            let data = userDefaults.data(forKey: Storage.defaultsKey),
            let saved = try? decoder.decode([HotKeyAction: HotKeyShortcut].self, from: data)
        else {
            return defaultShortcuts()
        }

        return saved
    }

    public func save(_ shortcuts: [HotKeyAction: HotKeyShortcut]) {
        guard let data = try? encoder.encode(shortcuts) else {
            return
        }

        userDefaults.set(data, forKey: Storage.defaultsKey)
    }

    public func resetToDefaults() -> [HotKeyAction: HotKeyShortcut] {
        let defaults = defaultShortcuts()
        save(defaults)
        return defaults
    }

    public func defaultShortcuts() -> [HotKeyAction: HotKeyShortcut] {
        var shortcuts: [HotKeyAction: HotKeyShortcut] = [:]

        for action in HotKeyAction.allCases {
            if let shortcut = action.defaultShortcut {
                shortcuts[action] = shortcut
            }
        }

        return shortcuts
    }
}
