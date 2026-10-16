import AppKit
import ServiceManagement

extension Notification.Name {
    static let favoritesChanged = Notification.Name("explorer.favoritesChanged")
    static let showHiddenChanged = Notification.Name("explorer.showHiddenChanged")
    static let clipboardChanged = Notification.Name("explorer.clipboardChanged")
    static let folderSizeUpdated = Notification.Name("explorer.folderSizeUpdated")
    static let globalShortcutChanged = Notification.Name("explorer.globalShortcutChanged")
}

enum Settings {
    private static let defaults = UserDefaults.standard
    static let ghosttyBundleID = "com.mitchellh.ghostty"

    static var homeFolder: URL {
        get {
            if let path = defaults.string(forKey: "homeFolder"), isFolder(URL(fileURLWithPath: path)) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }
        set { defaults.set(newValue.path, forKey: "homeFolder") }
    }

    static var showHidden: Bool {
        get { defaults.bool(forKey: "showHidden") }
        set {
            defaults.set(newValue, forKey: "showHidden")
            NotificationCenter.default.post(name: .showHiddenChanged, object: nil)
        }
    }

    static var terminalApp: URL? {
        get {
            if let path = defaults.string(forKey: "terminalApp"), FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: ghosttyBundleID)
        }
        set { defaults.set(newValue?.path, forKey: "terminalApp") }
    }

    static var favorites: [URL] {
        get {
            if let paths = defaults.stringArray(forKey: "favorites") {
                return paths.map { URL(fileURLWithPath: $0) }
            }
            let home = FileManager.default.homeDirectoryForCurrentUser
            return [home] + ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
        }
        set {
            defaults.set(newValue.map(\.path), forKey: "favorites")
            NotificationCenter.default.post(name: .favoritesChanged, object: nil)
        }
    }

    static var openWith: [String: String] {
        get { defaults.dictionary(forKey: "openWith") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "openWith") }
    }

    static var globalShortcut: Shortcut? {
        get {
            guard let stored = defaults.dictionary(forKey: "globalShortcut") else { return .standard }
            guard let keyCode = stored["keyCode"] as? Int, let flags = stored["modifiers"] as? UInt,
                  let key = stored["key"] as? String, !key.isEmpty else { return nil }
            return Shortcut(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: flags), key: key)
        }
        set {
            let value = newValue ?? Shortcut(keyCode: -1, modifiers: [], key: "")
            defaults.set(["keyCode": value.keyCode, "modifiers": value.modifiers.rawValue, "key": value.key],
                         forKey: "globalShortcut")
            NotificationCenter.default.post(name: .globalShortcutChanged, object: nil)
        }
    }

    static var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    static func setUpLoginItemOnce() {
        guard !defaults.bool(forKey: "loginItemConfigured"), Bundle.main.bundleIdentifier != nil else { return }
        defaults.set(true, forKey: "loginItemConfigured")
        openAtLogin = true
    }

    /// AppKit's "Finder replacement": "Show in Finder" in other apps reveals in Explorer instead.
    /// Apps read it at launch, so already running ones keep using Finder until restarted.
    static var replacesFinder: Bool {
        get {
            let value = CFPreferencesCopyValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication,
                                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
            return value != nil && value == Bundle.main.bundleIdentifier
        }
        set {
            let value = newValue ? Bundle.main.bundleIdentifier as CFString? : nil
            CFPreferencesSetValue("NSFileViewer" as CFString, value, kCFPreferencesAnyApplication,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
    }

    static func setUpReplacesFinderOnce() {
        guard !defaults.bool(forKey: "replacesFinderConfigured"), Bundle.main.bundleIdentifier != nil else { return }
        defaults.set(true, forKey: "replacesFinderConfigured")
        replacesFinder = true
    }

    static func addFavorite(_ url: URL, at index: Int? = nil) {
        var list = favorites
        guard !list.contains(where: { $0.path == url.path }) else { return }
        list.insert(url, at: min(index ?? list.count, list.count))
        favorites = list
    }

    static func removeFavorite(_ url: URL) {
        favorites = favorites.filter { $0.path != url.path }
    }
}

func isFolder(_ url: URL) -> Bool {
    var dir: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
}
