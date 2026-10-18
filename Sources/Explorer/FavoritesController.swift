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
    /// The folder the window is opening (mounting its volume or reading it); its row spins.
    private var loading: URL?

    private enum Row {
        case header(String)
        case favorite(Int)
        case location(Location)
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
        } else {
            table.deselectAll(nil)
        }
    }

    @objc private func clicked(_ sender: Any?) {
        guard let url = url(table.clickedRow) else { return }
        browser?.navigate(to: url)
    }

    private var locationsHeader: Int { items.count + 1 }

    private func row(_ row: Int) -> Row? {
        if row == 0 { return .header("Favorites") }
        if row <= items.count { return .favorite(row - 1) }
        if row == locationsHeader { return .header("Locations") }
        let index = row - locationsHeader - 1
        return index >= 0 && index < locations.count ? .location(locations[index]) : nil
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

    func numberOfRows(in tableView: NSTableView) -> Int { items.count + locations.count + 2 }

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
        for sub in [image, text, spinner] as [NSView] {
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
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
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
}

/// A favorite's row: icon and name, and a spinner in place of the icon while its volume mounts.
final class FavoriteCell: NSTableCellView {
    let spinner = NSProgressIndicator()

    func spin(_ on: Bool) {
        imageView?.isHidden = on
        if on { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }
}
