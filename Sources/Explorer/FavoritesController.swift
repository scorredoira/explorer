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
            self.table.reloadData()
            if let current = self.browser?.current { self.highlight(current) }
        }
    }

    func highlight(_ url: URL) {
        if let index = items.firstIndex(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
            table.selectRowIndexes([index + 1], byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
    }

    @objc private func clicked(_ sender: Any?) {
        guard let index = index(table.clickedRow) else { return }
        browser?.navigate(to: items[index])
    }

    private func index(_ row: Int) -> Int? {
        row >= 1 && row <= items.count ? row - 1 : nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count + 1 }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { row == 0 }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row > 0 }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { row == 0 ? 28 : 26 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == 0 {
            let header = NSTableCellView()
            let text = NSTextField(labelWithString: "Favoritos")
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
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        let url = items[row - 1]
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
        guard let index = index(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(index), forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let row = max(row, 1)
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
        let target = max(row - 1, 0)
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
        guard let index = index(table.clickedRow) else { return }
        let url = items[index]
        menu.add("Abrir") { [weak self] in self?.browser?.navigate(to: url) }
        menu.add("Abrir en nueva ventana") { AppDelegate.shared.openWindow(at: url) }
        menu.add("Abrir en den", enabled: FileOps.denCommand != nil) { FileOps.openInDen([url]) }
        menu.separator()
        menu.add("Copiar ruta") { FileOps.copyPaths([url]) }
        menu.add("Abrir terminal aquí") { FileOps.openTerminal(at: url) }
        menu.add("Pegar dentro", enabled: FileClipboard.hasFiles) { FileClipboard.paste(into: url) }
        menu.separator()
        menu.add("Quitar de Favoritos") { Settings.removeFavorite(url) }
    }
}
