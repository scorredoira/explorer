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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 600, height: 300)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        sizeQueue.maxConcurrentOperationCount = 2
        sizeQueue.qualityOfService = .utility
        favorites = FavoritesController(browser: self)
        buildUI()
        observe()
        navigate(to: current, record: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        configure(backButton, symbol: "chevron.left", tip: "Atrás", action: #selector(goBack(_:)))
        configure(forwardButton, symbol: "chevron.right", tip: "Adelante", action: #selector(goForward(_:)))
        configure(upButton, symbol: "arrow.up", tip: "Carpeta superior", action: #selector(goUp(_:)))

        pathField.delegate = self
        pathField.font = .systemFont(ofSize: NSFont.systemFontSize)
        pathField.lineBreakMode = .byTruncatingHead
        pathField.cell?.isScrollable = true
        pathField.cell?.wraps = false
        pathField.placeholderString = "Ruta"

        searchField.delegate = self
        searchField.placeholderString = "Filtrar"
        searchField.sendsSearchStringImmediately = true
        searchField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        let bar = NSStackView(views: [backButton, forwardButton, upButton, pathField, searchField])
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        outline.browser = self
        setupOutline()
        let listScroll = NSScrollView()
        listScroll.documentView = outline
        listScroll.hasVerticalScroller = true
        listScroll.hasHorizontalScroller = true
        listScroll.autohidesScrollers = true

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(listScroll)
        split.addArrangedSubview(favorites.view)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        let line = NSBox()
        line.boxType = .separator

        for view in [bar, line, split] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            line.topAnchor.constraint(equalTo: bar.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.topAnchor.constraint(equalTo: line.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            favorites.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            listScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 350),
        ])
        split.layoutSubtreeIfNeeded()
        split.setPosition(content.bounds.width - 210, ofDividerAt: 0)
    }

    private func configure(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.toolTip = tip
        button.target = self
        button.action = action
    }

    private func setupOutline() {
        let columns: [(String, String, CGFloat)] = [
            ("name", "Nombre", 360), ("date", "Fecha de modificación", 170),
            ("size", "Tamaño", 90), ("kind", "Tipo", 150),
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
        outline.style = .fullWidth
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.indentationPerLevel = 14
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
            NSSound.beep()
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

        loadRoot()
        outline.reloadData()
        outline.scrollRowToVisible(0)
        if let select { selectURLs([select]) }
        favorites.highlight(current)
        updateButtons()
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
            DispatchQueue.main.async {
                self?.pendingSizes.remove(path)
                if let size, op?.isCancelled == false { FolderSizes.shared.store(path, size: size) }
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
        for item in items {
            if item.isFolder {
                AppDelegate.shared.openWindow(at: item.url)
            } else {
                FileOps.open(item.url)
            }
        }
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
