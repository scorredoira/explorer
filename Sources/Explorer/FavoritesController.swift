import AppKit

final class FavoritesController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private static let rowType = NSPasteboard.PasteboardType("com.scorredoira.explorer.favorite-row")

    let view = NSView()
    private let table = NSTableView()
    private weak var browser: BrowserWindowController?
    private var items: [URL] = Settings.favorites

    init(browser: BrowserWindowController) {
        self.browser = browser
        super.init()

        let title = NSTextField(labelWithString: "Favoritos")
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("favorite"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 24
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

        for sub in [title, scroll] as [NSView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(sub)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        NotificationCenter.default.addObserver(forName: .favoritesChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.items = Settings.favorites
            self.table.reloadData()
            if let current = self.browser?.current { self.highlight(current) }
        }
    }

    func highlight(_ url: URL) {
        if let row = items.firstIndex(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    @objc private func clicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        browser?.navigate(to: items[row])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("favorite-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        let url = items[row]
        let exists = isFolder(url)
        cell.textField?.stringValue = FileManager.default.displayName(atPath: url.path)
        cell.textField?.textColor = exists ? .labelColor : .tertiaryLabelColor
        cell.toolTip = url.path
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        for sub in [image, text] as [NSView] {
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
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: Drag and drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if info.draggingPasteboard.string(forType: Self.rowType) != nil {
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }
        let urls = draggedURLs(info)
        guard !urls.isEmpty else { return [] }
        if dropOperation == .on, row < items.count {
            let dir = items[row]
            let allInside = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path }
            let operation = FileOps.dropOperation(info, urls: urls, to: dir)
            return operation == .move && allInside ? [] : operation
        }
        return urls.allSatisfy(isFolder) ? .link : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if let source = info.draggingPasteboard.string(forType: Self.rowType).flatMap(Int.init) {
            var list = items
            let moved = list.remove(at: source)
            list.insert(moved, at: source < row ? row - 1 : row)
            Settings.favorites = list
            return true
        }
        let urls = draggedURLs(info)
        if dropOperation == .on, row < items.count {
            let dir = items[row]
            let operation = FileOps.dropOperation(info, urls: urls, to: dir)
            guard !operation.isEmpty else { return false }
            FileOps.transfer(urls, to: dir, move: operation == .move)
            return true
        }
        var index = row
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
        let row = table.clickedRow
        guard row >= 0, row < items.count else { return }
        let url = items[row]
        menu.add("Abrir") { [weak self] in self?.browser?.navigate(to: url) }
        menu.add("Abrir en nueva ventana") { AppDelegate.shared.openWindow(at: url) }
        menu.separator()
        menu.add("Copiar ruta") { FileOps.copyPaths([url]) }
        menu.add("Abrir terminal aquí") { FileOps.openTerminal(at: url) }
        menu.add("Pegar dentro", enabled: FileClipboard.hasFiles) { FileClipboard.paste(into: url) }
        menu.separator()
        menu.add("Quitar de Favoritos") { Settings.removeFavorite(url) }
    }
}
