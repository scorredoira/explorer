import AppKit

private final class DeletableTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let homeLabel = NSTextField(labelWithString: "")
    private let terminalLabel = NSTextField(labelWithString: "")
    private let hiddenCheck = NSButton(checkboxWithTitle: "Show Hidden Files", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "Open at login (so the shortcut always works)", target: nil, action: nil)
    private let replaceFinderCheck = NSButton(checkboxWithTitle: "Use Explorer for \u{201C}Show in Finder\u{201D} in other apps", target: nil, action: nil)
    private let shortcutRecorder = ShortcutRecorder()
    private let table = DeletableTableView()
    private let removeButton = NSButton()
    private var rows: [(ext: String, app: String)] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
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

        let homeButton = NSButton(title: "Choose…", target: self, action: #selector(chooseHome))
        let terminalButton = NSButton(title: "Choose…", target: self, action: #selector(chooseTerminal))
        hiddenCheck.target = self
        hiddenCheck.action = #selector(toggleHidden)
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)
        replaceFinderCheck.target = self
        replaceFinderCheck.action = #selector(toggleReplaceFinder)
        shortcutRecorder.onChange = { Settings.globalShortcut = $0 }
        homeLabel.lineBreakMode = .byTruncatingMiddle
        terminalLabel.lineBreakMode = .byTruncatingMiddle

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Start folder:"), homeLabel, homeButton],
            [NSTextField(labelWithString: "Terminal:"), terminalLabel, terminalButton],
            [NSTextField(labelWithString: "New window shortcut:"), shortcutRecorder, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, hiddenCheck, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, loginCheck, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, replaceFinderCheck, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 10
        homeLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        grid.cell(for: shortcutRecorder)?.xPlacement = .leading

        let openWithTitle = NSTextField(labelWithString: "Always open with:")
        for (id, title, width) in [("ext", "Extension", 100.0), ("app", "App", 340.0)] {
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
        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.bezelStyle = .smallSquare
        removeButton.toolTip = "Remove the selected assignment"
        removeButton.target = self
        removeButton.action = #selector(removeAssignment)
        removeButton.isEnabled = false
        table.onDelete = { [weak self] in self?.removeAssignment() }

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
            removeButton.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -1),
            removeButton.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 22),
            removeButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    private func refresh() {
        homeLabel.stringValue = Settings.homeFolder.path
        terminalLabel.stringValue = Settings.terminalApp.map { FileManager.default.displayName(atPath: $0.path) } ?? "—"
        shortcutRecorder.shortcut = Settings.globalShortcut
        hiddenCheck.state = Settings.showHidden ? .on : .off
        loginCheck.state = Settings.openAtLogin ? .on : .off
        replaceFinderCheck.state = Settings.replacesFinder ? .on : .off
        rows = Settings.openWith.map { ($0.key, $0.value) }.sorted { $0.ext < $1.ext }
        table.reloadData()
        removeButton.isEnabled = table.selectedRow >= 0
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

    @objc private func toggleLogin() {
        Settings.openAtLogin = loginCheck.state == .on
        refresh()
    }

    @objc private func toggleReplaceFinder() {
        Settings.replacesFinder = replaceFinderCheck.state == .on
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = table.selectedRow >= 0
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
        let app = rows[row].app
        let value = isExt ? ".\(rows[row].ext)"
            : app == Opener.previewID ? "Preview" : FileManager.default.displayName(atPath: app)
        let text = NSTextField(labelWithString: value)
        text.lineBreakMode = .byTruncatingMiddle
        return text
    }
}
