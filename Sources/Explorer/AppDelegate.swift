import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }

    private var windows: [BrowserWindowController] = []
    private lazy var settings = SettingsWindowController()
    private var openedWithURLs = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        registerGlobalShortcut()
        NotificationCenter.default.addObserver(forName: .globalShortcutChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerGlobalShortcut()
        }
        Settings.setUpLoginItemOnce()
        if !openedWithURLs && !launchedAtLogin { openWindow(at: Settings.homeFolder) }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerGlobalShortcut() {
        HotKey.register(Settings.globalShortcut) { [weak self] in
            self?.openWindow(at: Settings.homeFolder)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication
            && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedWithURLs = true
        for url in urls {
            if isFolder(url) {
                openWindow(at: url)
            } else {
                openWindow(at: url.deletingLastPathComponent(), select: url)
                if Opener.opensInPreview(url), let browser = windows.last {
                    browser.previewSelection(nil)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(at: Settings.homeFolder) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func openWindow(at url: URL, select: URL? = nil) {
        let controller = BrowserWindowController(url: url)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        windows.append(controller)
        if let key = NSApp.keyWindow, key.windowController is BrowserWindowController {
            controller.window?.setFrame(key.frame, display: false)
            controller.window?.setFrameTopLeftPoint(key.cascadeTopLeft(from: NSPoint(x: key.frame.minX, y: key.frame.maxY)))
        } else {
            controller.window?.center()
        }
        controller.showWindow(nil)
        if let select { controller.selectURLs([select]) }
        controller.window?.makeFirstResponder(controller.outline)
    }

    @objc func newWindow(_ sender: Any?) {
        let current = (NSApp.keyWindow?.windowController as? BrowserWindowController)?.current
            ?? (NSApp.mainWindow?.windowController as? BrowserWindowController)?.current
        openWindow(at: current ?? Settings.homeFolder)
    }

    @objc func showSettings(_ sender: Any?) {
        settings.showWindow(nil)
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = submenu(main, "Explorer")
        app.addItem(withTitle: "About Explorer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        item(app, "Settings…", #selector(showSettings(_:)), ",")
        app.addItem(.separator())
        item(app, "Hide Explorer", #selector(NSApplication.hide(_:)), "h")
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        item(app, "Quit Explorer", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(main, "File")
        item(file, "New Window", #selector(newWindow(_:)), "n")
        item(file, "New Folder", #selector(BrowserWindowController.newFolder(_:)), "n", [.command, .shift])
        item(file, "New File", #selector(BrowserWindowController.newFile(_:)), "n", [.command, .option])
        file.addItem(.separator())
        item(file, "Open", #selector(BrowserWindowController.openSelection(_:)), key(NSDownArrowFunctionKey))
        item(file, "Quick Look", #selector(BrowserWindowController.toggleQuickLook(_:)), "y")
        item(file, "Rename", #selector(BrowserWindowController.renameSelection(_:)), "")
        file.addItem(.separator())
        item(file, "Copy Path", #selector(BrowserWindowController.copyPath(_:)), "c", [.command, .option])
        item(file, "Open Terminal Here", #selector(BrowserWindowController.openTerminal(_:)), "t", [.command, .option])
        item(file, "Add to Favorites", #selector(BrowserWindowController.addCurrentToFavorites(_:)), "")
        file.addItem(.separator())
        item(file, "Move to Trash", #selector(BrowserWindowController.moveToTrash(_:)), "\u{8}")
        file.addItem(.separator())
        item(file, "Close Window", #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu(main, "Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Filter", #selector(BrowserWindowController.focusSearch(_:)), "f")

        let view = submenu(main, "View")
        item(view, "Show Hidden Files", #selector(BrowserWindowController.toggleHidden(_:)), ".", [.command, .shift])

        let go = submenu(main, "Go")
        item(go, "Back", #selector(BrowserWindowController.goBack(_:)), "[")
        item(go, "Forward", #selector(BrowserWindowController.goForward(_:)), "]")
        item(go, "Enclosing Folder", #selector(BrowserWindowController.goUp(_:)), key(NSUpArrowFunctionKey))
        go.addItem(.separator())
        item(go, "Go to Folder…", #selector(BrowserWindowController.focusPath(_:)), "g", [.command, .shift])
        item(go, "Edit Path", #selector(BrowserWindowController.focusPath(_:)), "l")

        let window = submenu(main, "Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window

        return main
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    private func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                      _ modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    private func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt16(functionKey))!))
    }
}
