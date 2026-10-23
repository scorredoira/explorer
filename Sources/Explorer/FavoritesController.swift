import AppKit

/// A fixed place of the Locations section, like Finder's.
struct Location {
    let name: String
    let url: URL
    let symbol: String

    static var all: [Location] {
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let root = URL(fileURLWithPath: "/")
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        let trash = files.urls(for: .trashDirectory, in: .userDomainMask).first ?? home.appendingPathComponent(".Trash")
        var list = [
            Location(name: files.displayName(atPath: home.path), url: home, symbol: "house"),
            Location(name: files.displayName(atPath: root.path), url: root, symbol: "internaldrive"),
        ]
        if isFolder(iCloud) { list.append(Location(name: "iCloud Drive", url: iCloud, symbol: "icloud")) }
        list.append(Location(name: "Trash", url: trash, symbol: "trash"))
        return list
    }

    var isTrash: Bool { symbol == "trash" }
}

/// An SF Symbol in the blue of the folder icons, for the sidebar.
func sidebarSymbol(_ name: String) -> NSImage {
    let blue = NSColor(srgbRed: 0.36, green: 0.66, blue: 0.92, alpha: 1)
    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium).applying(.init(paletteColors: [blue]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        ?? NSWorkspace.shared.icon(for: .folder)
}

final class FavoritesController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowType = NSPasteboard.PasteboardType("com.scorredoira.explorer.favorite-row")

    let view = NSView()
    private let table = NSTableView()
    private weak var browser: BrowserWindowController?
    private var items: [URL] = Settings.favorites
    private let locations = Location.all
    private var servers: [Server] = Settings.servers
    /// Servers whose disk is being mounted, by name; their rows spin.
    private var connecting: Set<String> = []
    /// Where each server's disk was mounted, by name, to select its row while it is shown.
    private var serverVolumes: [String: URL] = [:]
    /// The folder the window is opening (mounting its volume or reading it); its row spins.
    private var loading: URL?

    private enum Row {
        case header(String)
        case favorite(Int)
        case location(Location)
        case server(Int)
    }

    init(browser: BrowserWindowController) {
        self.browser = browser
        super.init()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("favorite"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowSizeStyle = .default
        table.floatsGroupRows = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked(_:))
        table.menu = NSMenu()
        table.menu?.delegate = self
        table.registerForDraggedTypes([.fileURL, Self.rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(forName: .favoritesChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.items = Settings.favorites
            self.reload()
        }
        NotificationCenter.default.addObserver(forName: .serversChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.servers = Settings.servers
            self.reload()
        }
    }

    private func reload() {
        table.reloadData()
        if let loading {
            highlight(loading, loading: true)
        } else if let current = browser?.current {
            highlight(current)
        }
    }

    /// Selects the row of `url`, spinning while the window is still opening it.
    func highlight(_ url: URL, loading: Bool = false) {
        let changed = self.loading != (loading ? url : nil)
        self.loading = loading ? url : nil
        if changed { table.reloadData() }
        let path = url.standardizedFileURL.path
        if let index = items.firstIndex(where: { $0.standardizedFileURL.path == path }) {
            table.selectRowIndexes([index + 1], byExtendingSelection: false)
        } else if let index = locations.firstIndex(where: { $0.url.standardizedFileURL.path == path }) {
            table.selectRowIndexes([locationsHeader + 1 + index], byExtendingSelection: false)
        } else if let index = servers.firstIndex(where: { serverVolumes[$0.name]?.standardizedFileURL.path == path }) {
            table.selectRowIndexes([serversHeader + 1 + index], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    @objc private func clicked(_ sender: Any?) {
        if case .server(let index) = row(table.clickedRow) {
            openServer(servers[index])
            return
        }
        guard let url = url(table.clickedRow) else { return }
        browser?.navigate(to: url)
    }

    /// Opens the server's disk in the list, or its screen when it has no disk.
    private func openServer(_ server: Server) {
        guard let disk = server.diskURL else {
            openScreen(server)
            return
        }
        connecting.insert(server.name)
        reload()
        Volumes.connect(disk) { [weak self] volume in
            guard let self else { return }
            self.connecting.remove(server.name)
            if let volume {
                self.serverVolumes[server.name] = volume
                self.browser?.navigate(to: volume)
            } else {
                self.reload()
            }
        }
    }

    private func openScreen(_ server: Server) {
        guard let screen = server.screenURL, NSWorkspace.shared.open(screen) else {
            showError("Could not open the screen of \(server.name) (\(server.screen)).")
            return
        }
    }

    private var locationsHeader: Int { items.count + 1 }
    private var serversHeader: Int { locationsHeader + locations.count + 1 }

    private func row(_ row: Int) -> Row? {
        if row < 0 { return nil }
        if row == 0 { return .header("Favorites") }
        if row <= items.count { return .favorite(row - 1) }
        if row == locationsHeader { return .header("Locations") }
        if row < serversHeader { return .location(locations[row - locationsHeader - 1]) }
        if servers.isEmpty { return nil }
        if row == serversHeader { return .header("Servers") }
        let index = row - serversHeader - 1
        return index < servers.count ? .server(index) : nil
    }

    private func index(_ row: Int) -> Int? {
        if case .favorite(let index) = self.row(row) { return index }
        return nil
    }

    private func url(_ row: Int) -> URL? {
        switch self.row(row) {
        case .favorite(let index): return items[index]
        case .location(let location): return location.url
        default: return nil
        }
    }

    private func isHeader(_ row: Int) -> Bool {
        if case .header = self.row(row) { return true }
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count + locations.count + 2 + (servers.isEmpty ? 0 : servers.count + 1)
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { isHeader(row) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !isHeader(row) }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { isHeader(row) ? 28 : 26 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let kind = self.row(row)
        if case .header(let title) = kind {
            let header = NSTableCellView()
            let text = NSTextField(labelWithString: title)
            text.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
            text.textColor = .secondaryLabelColor
            text.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(text)
            header.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 4),
                text.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
            ])
            return header
        }
        let id = NSUserInterfaceItemIdentifier("favorite-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? FavoriteCell ?? makeCell(id)
        cell.onScreen = nil
        if case .server(let index) = kind {
            let server = servers[index]
            cell.textField?.stringValue = server.name
            cell.textField?.textColor = .labelColor
            cell.toolTip = [server.disk, server.screen].filter { !$0.isEmpty }.joined(separator: "\n")
            cell.spin(connecting.contains(server.name))
            cell.imageView?.image = sidebarSymbol(server.diskURL == nil ? "display" : "server.rack")
            if server.screenURL != nil {
                cell.onScreen = { [weak self] in self?.openScreen(server) }
            }
            return cell
        }
        if case .location(let location) = kind {
            cell.textField?.stringValue = location.name
            cell.textField?.textColor = .labelColor
            cell.toolTip = location.url.path
            cell.spin(isLoading(location.url))
            cell.imageView?.image = sidebarSymbol(location.symbol)
            return cell
        }
        guard case .favorite(let index) = kind else { return nil }
        let url = items[index]
        // A favorite on a network volume opens even when it is not mounted: a click mounts it.
        let remote = Volumes.remountURL(for: url) != nil
        let exists = remote || isFolder(url)
        cell.textField?.stringValue = FileManager.default.displayName(atPath: url.path)
        cell.textField?.textColor = exists ? .labelColor : .tertiaryLabelColor
        cell.toolTip = url.path
        cell.spin(isLoading(url))
        if remote {
            cell.imageView?.image = sidebarSymbol("server.rack")
        } else {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            cell.imageView?.image = icon
        }
        return cell
    }

    private func isLoading(_ url: URL) -> Bool {
        loading?.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> FavoriteCell {
        let cell = FavoriteCell()
        cell.identifier = id
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        let spinner = cell.spinner
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let screen = cell.screenButton
        screen.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Open Screen")
        screen.isBordered = false
        screen.toolTip = "Open Screen"
        screen.isHidden = true
        for sub in [image, text, spinner, screen] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(sub)
        }
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            spinner.centerXAnchor.constraint(equalTo: image.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: image.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(lessThanOrEqualTo: screen.leadingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            screen.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            screen.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            screen.widthAnchor.constraint(equalToConstant: 18),
        ])
        return cell
    }

    // MARK: Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let index = index(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(index), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on, case .location(let location) = self.row(row) {
            let urls = draggedURLs(info)
            guard !urls.isEmpty, info.draggingPasteboard.string(forType: Self.rowType) == nil else { return [] }
            if location.isTrash { return .delete }
            return FileOps.dropOperation(info, urls: urls, to: location.url)
        }
        // Favorites are added and reordered only within their own section.
        let row = min(max(row, 1), items.count + 1)
        if info.draggingPasteboard.string(forType: Self.rowType) != nil {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        let urls = draggedURLs(info)
        guard !urls.isEmpty else { return [] }
        if dropOperation == .on, let index = index(row) {
            let dir = items[index]
            let allInside = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path }
            let operation = FileOps.dropOperation(info, urls: urls, to: dir)
            return operation == .move && allInside ? [] : operation
        }
        tableView.setDropRow(row, dropOperation: .above)
        return urls.allSatisfy(isFolder) ? .link : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if dropOperation == .on, case .location(let location) = self.row(row) {
            let urls = draggedURLs(info)
            if location.isTrash {
                FileOps.trash(urls)
                return true
            }
            let operation = FileOps.dropOperation(info, urls: urls, to: location.url)
            guard !operation.isEmpty else { return false }
            FileOps.transfer(urls, to: location.url, move: operation == .move)
            return true
        }
        let target = min(max(row - 1, 0), items.count)
        if let source = info.draggingPasteboard.string(forType: Self.rowType).flatMap(Int.init) {
            var list = items
            let moved = list.remove(at: source)
            list.insert(moved, at: source < target ? target - 1 : target)
            Settings.favorites = list
            return true
        }
        let urls = draggedURLs(info)
        if dropOperation == .on, let index = index(row) {
            let dir = items[index]
            let operation = FileOps.dropOperation(info, urls: urls, to: dir)
            guard !operation.isEmpty else { return false }
            FileOps.transfer(urls, to: dir, move: operation == .move)
            return true
        }
        var index = target
        for url in urls where isFolder(url) && !items.contains(where: { $0.path == url.path }) {
            Settings.addFavorite(url, at: index)
            index += 1
        }
        return true
    }

    private func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = row(table.clickedRow)
        if case .server(let index) = clicked {
            let server = servers[index]
            menu.add("Open Disk", enabled: server.diskURL != nil) { [weak self] in self?.openServer(server) }
            menu.add("Open Screen", enabled: server.screenURL != nil) { [weak self] in self?.openScreen(server) }
            menu.separator()
            menu.add("Edit Server…") { Self.editServer(at: index) }
            menu.add("Remove Server") { Settings.servers.remove(at: index) }
        }
        switch clicked {
        case .favorite, .location:
            break
        default:
            menu.separator()
            menu.add("Add Server…") { Self.editServer(at: nil) }
            return
        }
        guard let url = url(table.clickedRow) else { return }
        let favorite = index(table.clickedRow) != nil
        menu.add("Open") { [weak self] in self?.browser?.navigate(to: url) }
        menu.add("Open in New Window") { AppDelegate.shared.openWindow(at: url) }
        menu.add("Open in den", enabled: FileOps.denCommand != nil) { FileOps.openInDen([url]) }
        menu.separator()
        menu.add("Copy Path") { FileOps.copyPaths([url]) }
        menu.add("Open Terminal Here") { FileOps.openTerminal(at: url) }
        menu.add("Paste Inside", enabled: FileClipboard.hasFiles) { FileClipboard.paste(into: url) }
        if favorite {
            menu.separator()
            menu.add("Remove from Favorites") { Settings.removeFavorite(url) }
        }
    }

    /// Asks for a server's name, disk and screen, and adds it (`index` nil) or changes it.
    private static func editServer(at index: Int?) {
        var server = index.map { Settings.servers[$0] } ?? Server(name: "", disk: "", screen: "")
        while true {
            let alert = NSAlert()
            alert.messageText = index == nil ? "Add Server" : "Edit Server"
            alert.informativeText = "The disk opens in the list (smb://host/share). The screen opens in Screen Sharing (vnc://host or vnc://host:port)."
            alert.addButton(withTitle: index == nil ? "Add" : "Save")
            alert.addButton(withTitle: "Cancel")
            let name = NSTextField(string: server.name)
            let disk = NSTextField(string: server.disk)
            disk.placeholderString = "smb://host/share"
            let screen = NSTextField(string: server.screen)
            screen.placeholderString = "vnc://host"
            let grid = NSGridView(views: [
                [NSTextField(labelWithString: "Name:"), name],
                [NSTextField(labelWithString: "Disk:"), disk],
                [NSTextField(labelWithString: "Screen:"), screen],
            ])
            grid.column(at: 0).xPlacement = .trailing
            grid.column(at: 1).width = 280
            grid.rowSpacing = 8
            grid.frame = NSRect(x: 0, y: 0, width: 340, height: 86)
            alert.accessoryView = grid
            alert.window.initialFirstResponder = name
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            server = Server(name: name.stringValue.trimmingCharacters(in: .whitespaces),
                            disk: disk.stringValue.trimmingCharacters(in: .whitespaces),
                            screen: screen.stringValue.trimmingCharacters(in: .whitespaces))
            var list = Settings.servers
            let others = list.enumerated().filter { $0.offset != index }.map(\.element)
            if server.name.isEmpty || server.disk.isEmpty && server.screen.isEmpty {
                showError("A server needs a name and a disk or a screen.")
            } else if others.contains(where: { $0.name == server.name }) {
                showError("There is already a server named \(server.name).")
            } else if !server.disk.isEmpty && server.diskURL?.host == nil {
                showError("\(server.disk) is not a disk URL, like smb://host/share.")
            } else if !server.screen.isEmpty && server.screenURL?.scheme == nil {
                showError("\(server.screen) is not a screen URL, like vnc://host.")
            } else {
                if let index { list[index] = server } else { list.append(server) }
                Settings.servers = list
                return
            }
        }
    }
}

/// A favorite's row: icon and name, and a spinner in place of the icon while its volume mounts.
/// A server's row also has a button that opens its screen.
final class FavoriteCell: NSTableCellView {
    let spinner = NSProgressIndicator()
    let screenButton = NSButton()

    var onScreen: (() -> Void)? {
        didSet {
            screenButton.isHidden = onScreen == nil
            screenButton.target = self
            screenButton.action = #selector(screenClicked)
        }
    }

    @objc private func screenClicked() { onScreen?() }

    func spin(_ on: Bool) {
        imageView?.isHidden = on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}
