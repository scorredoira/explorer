import AppKit

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: enabled ? #selector(run) : nil, keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

extension NSMenu {
    @discardableResult
    func add(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, enabled: enabled, handler: handler)
        addItem(item)
        return item
    }

    func separator() {
        if let last = items.last, !last.isSeparatorItem { addItem(.separator()) }
    }
}

func openWithMenu(for url: URL, remember: Bool) -> NSMenu {
    let menu = NSMenu()
    let ext = url.pathExtension.lowercased()
    let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
    var apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
    if let defaultApp {
        apps.removeAll { $0.path == defaultApp.path }
        apps.insert(defaultApp, at: 0)
    }
    var seen = Set<String>()
    for app in apps where seen.insert(app.path).inserted {
        var title = FileManager.default.displayName(atPath: app.path)
        if app.path == defaultApp?.path { title += " (predeterminada)" }
        if remember, Settings.openWith[ext] == app.path { title += " ✓" }
        let item = menu.add(title) {
            if remember { Settings.openWith[ext] = app.path }
            FileOps.open(url, with: app)
        }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
    }
    menu.separator()
    menu.add("Otra…") {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let app = panel.url else { return }
        if remember { Settings.openWith[ext] = app.path }
        FileOps.open(url, with: app)
    }
    return menu
}
