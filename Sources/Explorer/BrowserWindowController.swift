import AppKit
import Quartz

final class BrowserWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 47 && flags == [.command, .shift] {
            Settings.showHidden.toggle()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private(set) var current: URL
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var allRootItems: [FileItem] = []
    var rootItems: [FileItem] = []
    var filterText = ""

    let outline = FileOutlineView()
    let pathField = NSTextField()
    let searchField = NSSearchField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private(set) var favorites: FavoritesController!

    private var watcher: DirectoryWatcher?
    private var reloadScheduled = false
    let sizeQueue = OperationQueue()
    var pendingSizes = Set<String>()
    var renamingItem: FileItem?

    var onClose: ((BrowserWindowController) -> Void)?

    init(url: URL) {
        current = url.standardizedFileURL
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 640, height: 320)
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        super.init(window: window)
        window.delegate = self
        sizeQueue.maxConcurrentOperationCount = 4
        sizeQueue.qualityOfService = .utility
        favorites = FavoritesController(browser: self)
        buildUI()
        observe()
        navigate(to: current, record: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func buildUI() {
        guard let window else { return }

        configure(backButton, symbol: "chevron.left", tip: "Back", action: #selector(goBack(_:)))
        configure(forwardButton, symbol: "chevron.right", tip: "Forward", action: #selector(goForward(_:)))
        configure(upButton, symbol: "arrow.up", tip: "Enclosing Folder", action: #selector(goUp(_:)))

        pathField.delegate = self
        pathField.font = .systemFont(ofSize: NSFont.systemFontSize)
        pathField.lineBreakMode = .byTruncatingHead
        pathField.cell?.isScrollable = true
        pathField.cell?.wraps = false
        pathField.bezelStyle = .roundedBezel
        pathField.placeholderString = "Path"

        searchField.delegate = self
        searchField.placeholderString = "Filter"
        searchField.sendsSearchStringImmediately = true

        outline.browser = self
        setupOutline()
        let listScroll = NSScrollView()
        listScroll.documentView = outline
        listScroll.hasVerticalScroller = true
        listScroll.hasHorizontalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.drawsBackground = false
        let listController = NSViewController()
        listController.view = listScroll

        let sidebarController = NSViewController()
        sidebarController.view = favorites.view

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        let listItem = NSSplitViewItem(viewController: listController)
        listItem.minimumThickness = 360
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(listItem)
        split.splitView.autosaveName = "ExplorerSidebar"
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 680))

        let toolbar = NSToolbar(identifier: "ExplorerToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    private func configure(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.toolTip = tip
        button.target = self
        button.action = action
    }

    private func setupOutline() {
        let columns: [(String, String, CGFloat)] = [
            ("name", "Name", 360), ("date", "Date Modified", 170),
            ("size", "Size", 90), ("kind", "Kind", 150),
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "name" ? 150 : 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: id != "date" && id != "size")
            if id == "size" { column.headerCell.alignment = .right }
            outline.addTableColumn(column)
            if id == "name" { outline.outlineTableColumn = column }
        }
        outline.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        outline.autosaveName = "ExplorerColumns"
        outline.autosaveTableColumns = true
        outline.style = .inset
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.indentationPerLevel = 16
        outline.rowHeight = 18
        outline.intercellSpacing = NSSize(width: 10, height: 2)
        outline.rowSizeStyle = .custom
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked(_:))
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outline.setDraggingSourceOperationMask(.every, forLocal: false)
    }

    private func observe() {
        let center = NotificationCenter.default
        center.addObserver(forName: .showHiddenChanged, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        center.addObserver(forName: .clipboardChanged, object: nil, queue: .main) { [weak self] _ in self?.refreshVisibleRows() }
        center.addObserver(forName: .folderSizeUpdated, object: nil, queue: .main) { [weak self] note in
            guard let self, let path = note.object as? String else { return }
            self.refreshSize(path: path)
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { FileOps.undoManager }

    func windowWillClose(_ notification: Notification) {
        sizeQueue.cancelAllOperations()
        watcher = nil
        NotificationCenter.default.removeObserver(self)
        onClose?(self)
    }

    // MARK: Navigation

    func navigate(to url: URL, record: Bool = true, select: URL? = nil) {
        let target = url.standardizedFileURL
        guard isFolder(target) else {
            if Volumes.remountURL(for: target) != nil {
                favorites.highlight(target, loading: true)
                Volumes.mount(target) { [weak self] mounted in
                    guard let self else { return }
                    if mounted {
                        self.navigate(to: target, record: record, select: select)
                    } else {
                        self.favorites.highlight(self.current)
                    }
                }
            } else {
                NSSound.beep()
            }
            return
        }
        if record && target.path != current.path {
            backStack.append(current)
            forwardStack.removeAll()
        }
        current = target
        filterText = ""
        searchField.stringValue = ""
        sizeQueue.cancelAllOperations()
        pendingSizes.removeAll()

        window?.title = FileManager.default.displayName(atPath: current.path)
        window?.representedURL = current
        pathField.stringValue = current.path

        let watchedPath = current.resolvingSymlinksInPath().path
        watcher = DirectoryWatcher(path: watchedPath) { [weak self] paths in self?.filesChanged(paths) }

        // The listing is read off the main thread: on a network volume it can take a second.
        allRootItems = []
        applyFilter()
        outline.reloadData()
        favorites.highlight(current, loading: true)
        updateButtons()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FileItem.read(target, parent: nil) }
            DispatchQueue.main.async {
                guard let self, self.current == target else { return }
                let items: [FileItem]
                switch result {
                case .success(let read):
                    items = read
                case .failure(let error):
                    items = []
                    let denied = (error as NSError).code == NSFileReadNoPermissionError
                    showError(denied
                        ? "Explorer can't read \(target.path). Give it Full Disk Access in System Settings → Privacy & Security."
                        : error.localizedDescription)
                }
                self.allRootItems = FileItem.sort(items, by: self.sortDescriptor)
                self.applyFilter()
                self.outline.reloadData()
                self.outline.scrollRowToVisible(0)
                if let select { self.selectURLs([select]) }
                self.favorites.highlight(target)
            }
        }
    }

    private func updateButtons() {
        backButton.isEnabled = !backStack.isEmpty
        forwardButton.isEnabled = !forwardStack.isEmpty
        upButton.isEnabled = current.path != "/"
    }

    @objc func goBack(_ sender: Any?) {
        guard let previous = backStack.popLast() else { return NSSound.beep() }
        forwardStack.append(current)
        let from = current
        navigate(to: previous, record: false, select: from.deletingLastPathComponent().path == previous.path ? from : nil)
    }

    @objc func goForward(_ sender: Any?) {
        guard let next = forwardStack.popLast() else { return NSSound.beep() }
        backStack.append(current)
        navigate(to: next, record: false)
    }

    @objc func goUp(_ sender: Any?) {
        guard current.path != "/" else { return NSSound.beep() }
        navigate(to: current.deletingLastPathComponent(), select: current)
    }

    // MARK: Loading

    var sortDescriptor: NSSortDescriptor? { outline.sortDescriptors.first }

    func loadRoot() {
        allRootItems = FileItem.sort(FileItem.list(current, parent: nil), by: sortDescriptor)
        applyFilter()
    }

    func applyFilter() {
        rootItems = filterText.isEmpty
            ? allRootItems
            : allRootItems.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    func children(of item: FileItem) -> [FileItem] {
        if let children = item.children { return children }
        let children = FileItem.sort(FileItem.list(item.url, parent: item), by: sortDescriptor)
        item.children = children
        return children
    }

    func reload() {
        let expanded = expandedPaths()
        let selected = Set(selectedItems().map(\.path))
        loadRoot()
        outline.reloadData()
        expand(paths: expanded)
        selectPaths(selected)
    }

    private func expandedPaths() -> Set<String> {
        var paths = Set<String>()
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? FileItem, outline.isItemExpanded(item) {
                paths.insert(item.path)
            }
        }
        return paths
    }

    private func expand(paths: Set<String>) {
        guard !paths.isEmpty else { return }
        var row = 0
        while row < outline.numberOfRows {
            if let item = outline.item(atRow: row) as? FileItem, item.isFolder, paths.contains(item.path) {
                outline.expandItem(item)
            }
            row += 1
        }
    }

    private func selectPaths(_ paths: Set<String>) {
        var rows = IndexSet()
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? FileItem, paths.contains(item.path) { rows.insert(row) }
        }
        outline.selectRowIndexes(rows, byExtendingSelection: false)
    }

    func selectURLs(_ urls: [URL]) {
        selectPaths(Set(urls.map { $0.standardizedFileURL.path }))
        if let first = outline.selectedRowIndexes.first { outline.scrollRowToVisible(first) }
    }

    func row(forPath path: String) -> Int? {
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? FileItem, item.path == path { return row }
        }
        return nil
    }

    private func filesChanged(_ paths: [String]) {
        for path in paths { FolderSizes.shared.invalidate(changedPath: path) }
        var loaded: Set<String> = [current.resolvingSymlinksInPath().path]
        for path in expandedPaths() { loaded.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().path) }
        let touches = paths.contains { path in
            loaded.contains((path as NSString).deletingLastPathComponent) || loaded.contains(path)
        }
        guard touches, !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            if self.renamingItem == nil { self.reload() }
        }
    }

    func refreshVisibleRows() {
        guard outline.numberOfRows > 0 else { return }
        outline.reloadData(
            forRowIndexes: IndexSet(integersIn: 0..<outline.numberOfRows),
            columnIndexes: IndexSet(integersIn: 0..<outline.numberOfColumns))
    }

    private func refreshSize(path: String) {
        guard let row = row(forPath: path) else { return }
        let column = outline.column(withIdentifier: NSUserInterfaceItemIdentifier("size"))
        guard column >= 0 else { return }
        outline.reloadData(forRowIndexes: [row], columnIndexes: [column])
    }

    func requestSize(_ item: FileItem) {
        let path = item.path
        guard FolderSizes.shared.needsCompute(path), !pendingSizes.contains(path) else { return }
        pendingSizes.insert(path)
        let op = BlockOperation()
        op.addExecutionBlock { [weak op, weak self] in
            let size = FolderSizes.compute(item.url.resolvingSymlinksInPath()) { op?.isCancelled ?? true }
            let cancelled = op?.isCancelled ?? true
            DispatchQueue.main.async {
                self?.pendingSizes.remove(path)
                if let size, !cancelled { FolderSizes.shared.store(path, size: size) }
            }
        }
        sizeQueue.addOperation(op)
    }

    // MARK: Selection helpers

    func selectedItems() -> [FileItem] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? FileItem }
    }

    func clickedItems() -> [FileItem] {
        let clicked = outline.clickedRow
        guard clicked >= 0 else { return [] }
        if outline.selectedRowIndexes.contains(clicked) { return selectedItems() }
        return [outline.item(atRow: clicked) as? FileItem].compactMap { $0 }
    }

    func folderFor(_ item: FileItem?) -> URL {
        guard let item else { return current }
        return item.isFolder ? item.url : item.url.deletingLastPathComponent()
    }

    // MARK: Actions

    @objc func doubleClicked(_ sender: Any?) {
        guard outline.clickedRow >= 0, let item = outline.item(atRow: outline.clickedRow) as? FileItem else { return }
        open([item])
    }

    func open(_ items: [FileItem]) {
        if items.count == 1, let item = items.first, item.isFolder {
            navigate(to: item.url)
            return
        }
        var previewed = false
        for item in items {
            if item.isFolder {
                AppDelegate.shared.openWindow(at: item.url)
            } else if Opener.opensInPreview(item.url) {
                if !previewed { preview(item) }
                previewed = true
            } else {
                FileOps.open(item.url)
            }
        }
    }

    @objc func previewSelection(_ sender: Any?) {
        guard let item = selectedItems().first(where: { !$0.isFolder }) else { return NSSound.beep() }
        preview(item)
    }

    func preview(_ item: FileItem) {
        let siblings = (item.parent?.children ?? rootItems).filter { !$0.isFolder }.map(\.url)
        PreviewWindowController.shared.show(item.url, among: siblings)
    }

    @objc func openSelection(_ sender: Any?) { open(selectedItems()) }

    @objc func newFolder(_ sender: Any?) { create(folder: true, in: current) }

    @objc func newFile(_ sender: Any?) { create(folder: false, in: current) }

    func create(folder: Bool, in dir: URL) {
        guard let url = folder ? FileOps.createFolder(in: dir) : FileOps.createFile(in: dir) else { return }
        reload()
        if dir.standardizedFileURL.path != current.path, let row = row(forPath: dir.standardizedFileURL.path),
           let parent = outline.item(atRow: row) as? FileItem {
            parent.children = nil
            outline.reloadItem(parent, reloadChildren: true)
            outline.expandItem(parent)
        }
        guard let row = row(forPath: url.standardizedFileURL.path), let item = outline.item(atRow: row) as? FileItem else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        beginRename(item)
    }

    @objc func renameSelection(_ sender: Any?) {
        guard let item = selectedItems().first, outline.selectedRowIndexes.count == 1 else { return NSSound.beep() }
        beginRename(item)
    }

    @objc func moveToTrash(_ sender: Any?) {
        let urls = selectedItems().map(\.url)
        guard !urls.isEmpty else { return NSSound.beep() }
        FileOps.trash(urls)
    }

    @objc func cut(_ sender: Any?) {
        let urls = selectedItems().map(\.url)
        guard !urls.isEmpty else { return NSSound.beep() }
        FileClipboard.write(urls, cut: true)
    }

    @objc func copy(_ sender: Any?) {
        let urls = selectedItems().map(\.url)
        guard !urls.isEmpty else { return NSSound.beep() }
        FileClipboard.write(urls, cut: false)
    }

    @objc func paste(_ sender: Any?) { paste(into: current) }

    func paste(into dir: URL) {
        FileClipboard.paste(into: dir) { [weak self] urls in
            self?.reload()
            self?.selectURLs(urls)
        }
    }

    @objc func copyPath(_ sender: Any?) {
        let urls = selectedItems().map(\.url)
        FileOps.copyPaths(urls.isEmpty ? [current] : urls)
    }

    @objc func openTerminal(_ sender: Any?) {
        let items = selectedItems()
        FileOps.openTerminal(at: items.count == 1 ? folderFor(items[0]) : current)
    }

    @objc func toggleHidden(_ sender: Any?) { Settings.showHidden.toggle() }

    @objc func focusPath(_ sender: Any?) {
        window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectedRange = NSRange(location: pathField.stringValue.count, length: 0)
    }

    @objc func focusSearch(_ sender: Any?) { window?.makeFirstResponder(searchField) }

    @objc func addCurrentToFavorites(_ sender: Any?) { Settings.addFavorite(current) }

    @objc func toggleQuickLook(_ sender: Any?) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = !selectedItems().isEmpty
        switch item.action {
        case #selector(goBack(_:)): return !backStack.isEmpty
        case #selector(goForward(_:)): return !forwardStack.isEmpty
        case #selector(goUp(_:)): return current.path != "/"
        case #selector(cut(_:)), #selector(copy(_:)), #selector(moveToTrash(_:)),
             #selector(openSelection(_:)), #selector(toggleQuickLook(_:)):
            return hasSelection
        case #selector(renameSelection(_:)): return outline.selectedRowIndexes.count == 1
        case #selector(paste(_:)): return FileClipboard.hasFiles
        case #selector(toggleHidden(_:)):
            item.state = Settings.showHidden ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

private extension NSToolbarItem.Identifier {
    static let navigation = NSToolbarItem.Identifier("navigation")
    static let up = NSToolbarItem.Identifier("up")
    static let path = NSToolbarItem.Identifier("path")
    static let search = NSToolbarItem.Identifier("search")
}

extension BrowserWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .navigation, .up, .path, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .navigation:
            let stack = NSStackView(views: [backButton, forwardButton])
            stack.spacing = 2
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = stack
            item.label = "Back/Forward"
            return item
        case .up:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = upButton
            item.label = "Up"
            return item
        case .path:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = pathField
            item.label = "Path"
            item.visibilityPriority = .high
            pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            pathField.widthAnchor.constraint(lessThanOrEqualToConstant: 2000).isActive = true
            return item
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.searchField = searchField
            item.preferredWidthForSearchField = 200
            item.label = "Filter"
            return item
        default:
            return nil
        }
    }
}

extension BrowserWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedItems().count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selectedItems()[index].url as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        outline.keyDown(with: event)
        return true
    }
}
