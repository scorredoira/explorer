import AppKit
import Quartz

final class FileOutlineView: NSOutlineView {
    weak var browser: BrowserWindowController?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.keyCode, flags) {
        case (36, []), (76, []):
            browser?.renameSelection(nil)
        case (49, []):
            browser?.toggleQuickLook(nil)
        case (53, []):
            if !FileClipboard.cancelCut() { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

private let sizeFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
}()

extension BrowserWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? FileItem else { return rootItems.count }
        return children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? FileItem else { return rootItems[index] }
        return children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileItem)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? FileItem, let column = tableColumn?.identifier.rawValue else { return nil }
        let cell = makeCell(column)
        let text = cell.textField!
        text.alphaValue = FileClipboard.isCut(item.path) ? 0.5 : 1
        switch column {
        case "name":
            text.stringValue = item.name
            let icon = NSWorkspace.shared.icon(forFile: item.path)
            icon.size = NSSize(width: 16, height: 16)
            cell.imageView?.image = icon
            cell.imageView?.alphaValue = text.alphaValue
        case "date":
            text.stringValue = item.modified.map { dateFormatter.string(from: $0) } ?? "—"
        case "size":
            if item.isFolder {
                requestSize(item)
                text.stringValue = FolderSizes.shared.size(item.path).map { sizeFormatter.string(fromByteCount: $0) } ?? "…"
            } else {
                text.stringValue = item.fileSize.map { sizeFormatter.string(fromByteCount: $0) } ?? "—"
            }
        default:
            text.stringValue = item.kind
        }
        return cell
    }

    private func makeCell(_ column: String) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier("cell-\(column)")
        if let cell = outline.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return cell }
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        text.isEditable = false
        text.delegate = self
        cell.addSubview(text)
        cell.textField = text
        if column == "name" {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            ])
        } else {
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            text.textColor = .secondaryLabelColor
        }
        if column == "size" { text.alignment = .right }
        NSLayoutConstraint.activate([
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        reload()
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        tableColumn?.identifier.rawValue == "name" ? (item as? FileItem)?.name : nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        (notification.userInfo?["NSObject"] as? FileItem)?.children = nil
    }

    // MARK: Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        (item as? FileItem)?.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let urls = draggedURLs(info)
        guard !urls.isEmpty else { return [] }
        var target = item as? FileItem
        if let candidate = target, !candidate.isFolder { target = candidate.parent }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        let dir = target?.url ?? current
        if urls.contains(where: { $0.standardizedFileURL.path == dir.standardizedFileURL.path }) { return [] }
        let operation = FileOps.dropOperation(info, urls: urls, to: dir)
        let allInside = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path }
        if operation == .move && allInside { return [] }
        return operation
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let urls = draggedURLs(info)
        let dir = (item as? FileItem)?.url ?? current
        let operation = FileOps.dropOperation(info, urls: urls, to: dir)
        guard !urls.isEmpty, !operation.isEmpty else { return false }
        FileOps.transfer(urls, to: dir, move: operation == .move) { [weak self] _ in self?.reload() }
        return true
    }

    func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

// MARK: Context menu

extension BrowserWindowController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = clickedItems()
        if items.isEmpty {
            buildBlankMenu(menu)
        } else {
            buildItemMenu(menu, items: items)
        }
    }

    private func buildBlankMenu(_ menu: NSMenu) {
        let dir = current
        menu.add("Nueva carpeta") { [weak self] in self?.create(folder: true, in: dir) }
        menu.add("Nuevo archivo") { [weak self] in self?.create(folder: false, in: dir) }
        menu.separator()
        menu.add("Pegar", enabled: FileClipboard.hasFiles) { [weak self] in self?.paste(into: dir) }
        menu.separator()
        menu.add("Copiar ruta") { FileOps.copyPaths([dir]) }
        menu.add("Abrir terminal aquí") { FileOps.openTerminal(at: dir) }
        menu.add("Abrir en den", enabled: FileOps.denCommand != nil) { FileOps.openInDen([dir]) }
        menu.add("Añadir a Favoritos") { Settings.addFavorite(dir) }
        menu.separator()
        addHiddenToggle(menu)
    }

    private func buildItemMenu(_ menu: NSMenu, items: [FileItem]) {
        let single = items.count == 1 ? items[0] : nil
        let clicked = outline.item(atRow: outline.clickedRow) as? FileItem
        let urls = items.map(\.url)

        menu.add("Abrir") { [weak self] in self?.open(items) }
        if let single, single.isFolder {
            menu.add("Abrir en nueva ventana") { AppDelegate.shared.openWindow(at: single.url) }
        }
        if let single, !single.isFolder {
            if !Opener.opensInPreview(single.url) {
                menu.add("Previsualizar") { [weak self] in self?.preview(single) }
            }
            let previewSingle: () -> Void = { [weak self] in self?.preview(single) }
            let openWith = NSMenuItem(title: "Abrir con", action: nil, keyEquivalent: "")
            openWith.submenu = openWithMenu(for: single.url, remember: false, preview: previewSingle)
            menu.addItem(openWith)
            let ext = single.url.pathExtension.lowercased()
            if !ext.isEmpty {
                let always = NSMenuItem(title: "Abrir siempre .\(ext) con", action: nil, keyEquivalent: "")
                always.submenu = openWithMenu(for: single.url, remember: true, preview: previewSingle)
                menu.addItem(always)
                if Settings.openWith[ext] != nil {
                    menu.add("Quitar programa asignado a .\(ext)") { Settings.openWith[ext] = nil }
                }
            }
        }
        menu.add("Abrir en den", enabled: FileOps.denCommand != nil) { FileOps.openInDen(urls) }
        menu.add("Vista rápida") { [weak self] in
            guard let self else { return }
            self.selectURLs(urls)
            self.toggleQuickLook(nil)
        }
        menu.separator()
        menu.add(items.count == 1 ? "Copiar ruta" : "Copiar rutas") { FileOps.copyPaths(urls) }
        menu.add("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        menu.separator()
        menu.add("Cortar") { FileClipboard.write(urls, cut: true) }
        menu.add("Copiar") { FileClipboard.write(urls, cut: false) }
        let pasteDir = folderFor(clicked)
        menu.add(clicked?.isFolder == true ? "Pegar dentro" : "Pegar", enabled: FileClipboard.hasFiles) { [weak self] in
            self?.paste(into: pasteDir)
        }
        menu.separator()
        if let single {
            menu.add("Renombrar") { [weak self] in self?.beginRename(single) }
        }
        menu.add("Mover a la Papelera") { FileOps.trash(urls) }
        menu.separator()
        let dir = folderFor(clicked)
        let inside = clicked?.isFolder == true ? " dentro" : ""
        menu.add("Nueva carpeta\(inside)") { [weak self] in self?.create(folder: true, in: dir) }
        menu.add("Nuevo archivo\(inside)") { [weak self] in self?.create(folder: false, in: dir) }
        menu.separator()
        menu.add("Abrir terminal aquí") { FileOps.openTerminal(at: dir) }
        let folders = items.filter(\.isFolder)
        if !folders.isEmpty {
            menu.add("Añadir a Favoritos") { folders.forEach { Settings.addFavorite($0.url) } }
        }
        menu.separator()
        addHiddenToggle(menu)
    }

    private func addHiddenToggle(_ menu: NSMenu) {
        menu.add(Settings.showHidden ? "Ocultar archivos ocultos" : "Mostrar archivos ocultos") {
            Settings.showHidden.toggle()
        }
    }
}

// MARK: Text fields: path, filter and rename

extension BrowserWindowController: NSTextFieldDelegate, NSSearchFieldDelegate {
    func beginRename(_ item: FileItem) {
        let row = outline.row(forItem: item)
        guard row >= 0 else { return }
        outline.scrollRowToVisible(row)
        let column = outline.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        guard let cell = outline.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingItem = item
        field.isEditable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.alphaValue = 1
        window?.makeFirstResponder(field)
        let name = item.name as NSString
        let ext = name.pathExtension
        let length = item.isFolder || ext.isEmpty ? name.length : name.length - (ext as NSString).length - 1
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: max(length, 0))
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        filterText = searchField.stringValue
        applyFilter()
        outline.reloadData()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === pathField {
            pathField.stringValue = current.path
            return
        }
        guard field !== searchField, let item = renamingItem else { return }
        renamingItem = nil
        field.isEditable = false
        field.drawsBackground = false
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == item.name || name.contains("/") {
            field.stringValue = item.name
        } else if let url = FileOps.rename(item.url, to: name) {
            reload()
            selectURLs([url])
        } else {
            field.stringValue = item.name
        }
        window?.makeFirstResponder(outline)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === pathField {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                goToTypedPath()
                return true
            case #selector(NSResponder.insertTab(_:)):
                completePath(textView)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                pathField.stringValue = current.path
                window?.makeFirstResponder(outline)
                return true
            default:
                return false
            }
        }
        if control === searchField {
            switch selector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertNewline(_:)):
                window?.makeFirstResponder(outline)
                if outline.selectedRow < 0, outline.numberOfRows > 0 {
                    outline.selectRowIndexes([0], byExtendingSelection: false)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if searchField.stringValue.isEmpty { window?.makeFirstResponder(outline) }
                return false
            default:
                return false
            }
        }
        if let item = renamingItem, selector == #selector(NSResponder.cancelOperation(_:)) {
            (control as? NSTextField)?.stringValue = item.name
            window?.makeFirstResponder(outline)
            return true
        }
        return false
    }

    private func typedURL(_ text: String) -> URL {
        URL(fileURLWithPath: (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath)
    }

    private func goToTypedPath() {
        let url = typedURL(pathField.stringValue)
        if isFolder(url) {
            navigate(to: url)
            window?.makeFirstResponder(outline)
        } else if FileManager.default.fileExists(atPath: url.path) {
            navigate(to: url.deletingLastPathComponent(), select: url)
            window?.makeFirstResponder(outline)
        } else {
            NSSound.beep()
        }
    }

    private func completePath(_ textView: NSTextView) {
        let text = pathField.stringValue
        let expanded = (text as NSString).expandingTildeInPath
        let endsWithSlash = expanded.hasSuffix("/")
        let dir = endsWithSlash ? expanded : (expanded as NSString).deletingLastPathComponent
        let prefix = endsWithSlash ? "" : (expanded as NSString).lastPathComponent
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir)) ?? [])
            .filter { $0.lowercased().hasPrefix(prefix.lowercased()) }
            .filter { prefix.hasPrefix(".") || Settings.showHidden || !$0.hasPrefix(".") }
            .sorted()
        guard let first = names.first else { return NSSound.beep() }
        var common = first
        for name in names.dropFirst() {
            while !name.lowercased().hasPrefix(common.lowercased()) { common.removeLast() }
        }
        var completed = (dir as NSString).appendingPathComponent(names.count == 1 ? first : common)
        if names.count == 1, isFolder(URL(fileURLWithPath: completed)) { completed += "/" }
        if names.count > 1, common.count == prefix.count { NSSound.beep() }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if text.hasPrefix("~"), completed.hasPrefix(home) { completed = "~" + completed.dropFirst(home.count) }
        pathField.stringValue = completed
        textView.selectedRange = NSRange(location: (completed as NSString).length, length: 0)
    }
}
