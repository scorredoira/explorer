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
        HotKey.register(keyCode: kVK_ANSI_E, modifiers: cmdKey | optionKey) { [weak self] in
            self?.openWindow(at: Settings.homeFolder)
            NSApp.activate(ignoringOtherApps: true)
        }
        Settings.setUpLoginItemOnce()
        if !openedWithURLs && !launchedAtLogin { openWindow(at: Settings.homeFolder) }
        NSApp.activate(ignoringOtherApps: true)
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
        app.addItem(withTitle: "Acerca de Explorer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        item(app, "Ajustes…", #selector(showSettings(_:)), ",")
        app.addItem(.separator())
        item(app, "Ocultar Explorer", #selector(NSApplication.hide(_:)), "h")
        item(app, "Ocultar otros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addItem(withTitle: "Mostrar todo", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        item(app, "Salir de Explorer", #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(main, "Archivo")
        item(file, "Nueva ventana", #selector(newWindow(_:)), "n")
        item(file, "Nueva carpeta", #selector(BrowserWindowController.newFolder(_:)), "n", [.command, .shift])
        item(file, "Nuevo archivo", #selector(BrowserWindowController.newFile(_:)), "n", [.command, .option])
        file.addItem(.separator())
        item(file, "Abrir", #selector(BrowserWindowController.openSelection(_:)), key(NSDownArrowFunctionKey))
        item(file, "Vista rápida", #selector(BrowserWindowController.toggleQuickLook(_:)), "y")
        item(file, "Renombrar", #selector(BrowserWindowController.renameSelection(_:)), "")
        file.addItem(.separator())
        item(file, "Copiar ruta", #selector(BrowserWindowController.copyPath(_:)), "c", [.command, .option])
        item(file, "Abrir terminal aquí", #selector(BrowserWindowController.openTerminal(_:)), "t", [.command, .option])
        item(file, "Añadir a Favoritos", #selector(BrowserWindowController.addCurrentToFavorites(_:)), "")
        file.addItem(.separator())
        item(file, "Mover a la Papelera", #selector(BrowserWindowController.moveToTrash(_:)), "\u{8}")
        file.addItem(.separator())
        item(file, "Cerrar ventana", #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu(main, "Edición")
        item(edit, "Deshacer", Selector(("undo:")), "z")
        item(edit, "Rehacer", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Cortar", #selector(NSText.cut(_:)), "x")
        item(edit, "Copiar", #selector(NSText.copy(_:)), "c")
        item(edit, "Pegar", #selector(NSText.paste(_:)), "v")
        item(edit, "Seleccionar todo", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Filtrar", #selector(BrowserWindowController.focusSearch(_:)), "f")

        let view = submenu(main, "Visualización")
        item(view, "Mostrar archivos ocultos", #selector(BrowserWindowController.toggleHidden(_:)), ".", [.command, .shift])

        let go = submenu(main, "Ir")
        item(go, "Atrás", #selector(BrowserWindowController.goBack(_:)), "[")
        item(go, "Adelante", #selector(BrowserWindowController.goForward(_:)), "]")
        item(go, "Carpeta superior", #selector(BrowserWindowController.goUp(_:)), key(NSUpArrowFunctionKey))
        go.addItem(.separator())
        item(go, "Ir a la carpeta…", #selector(BrowserWindowController.focusPath(_:)), "g", [.command, .shift])
        item(go, "Editar ruta", #selector(BrowserWindowController.focusPath(_:)), "l")

        let window = submenu(main, "Ventana")
        item(window, "Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Traer todo al frente", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
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
