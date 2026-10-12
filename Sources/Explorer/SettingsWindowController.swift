import AppKit

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let homeLabel = NSTextField(labelWithString: "")
    private let terminalLabel = NSTextField(labelWithString: "")
    private let hiddenCheck = NSButton(checkboxWithTitle: "Mostrar archivos ocultos", target: nil, action: nil)
    private let table = NSTableView()
    private var rows: [(ext: String, app: String)] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ajustes"
        super.init(window: window)
        build()
        refresh()
        NotificationCenter.default.addObserver(forName: .showHiddenChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        refresh()
        window?.center()
        super.showWindow(sender)
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let homeButton = NSButton(title: "Elegir…", target: self, action: #selector(chooseHome))
        let terminalButton = NSButton(title: "Elegir…", target: self, action: #selector(chooseTerminal))
        hiddenCheck.target = self
        hiddenCheck.action = #selector(toggleHidden)
        homeLabel.lineBreakMode = .byTruncatingMiddle
        terminalLabel.lineBreakMode = .byTruncatingMiddle

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Carpeta de inicio:"), homeLabel, homeButton],
            [NSTextField(labelWithString: "Terminal:"), terminalLabel, terminalButton],
            [NSGridCell.emptyContentView, hiddenCheck, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 10
        homeLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let openWithTitle = NSTextField(labelWithString: "Abrir siempre con:")
        for (id, title, width) in [("ext", "Extensión", 100.0), ("app", "Programa", 340.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let removeButton = NSButton(title: "Quitar", target: self, action: #selector(removeAssignment))

        for view in [grid, openWithTitle, scroll, removeButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            openWithTitle.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            openWithTitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: openWithTitle.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            removeButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            removeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            removeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func refresh() {
        homeLabel.stringValue = Settings.homeFolder.path
        terminalLabel.stringValue = Settings.terminalApp.map { FileManager.default.displayName(atPath: $0.path) } ?? "—"
        hiddenCheck.state = Settings.showHidden ? .on : .off
        rows = Settings.openWith.map { ($0.key, $0.value) }.sorted { $0.ext < $1.ext }
        table.reloadData()
    }

    @objc private func chooseHome() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = Settings.homeFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.homeFolder = url
        refresh()
    }

    @objc private func chooseTerminal() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Settings.terminalApp = url
        refresh()
    }

    @objc private func toggleHidden() {
        Settings.showHidden = hiddenCheck.state == .on
    }

    @objc private func removeAssignment() {
        let row = table.selectedRow
        guard row >= 0 else { return NSSound.beep() }
        Settings.openWith[rows[row].ext] = nil
        refresh()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isExt = tableColumn?.identifier.rawValue == "ext"
        let value = isExt ? ".\(rows[row].ext)" : FileManager.default.displayName(atPath: rows[row].app)
        let text = NSTextField(labelWithString: value)
        text.lineBreakMode = .byTruncatingMiddle
        return text
    }
}
