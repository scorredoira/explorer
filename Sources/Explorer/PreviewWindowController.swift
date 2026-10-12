import AVKit
import AppKit
import Quartz

final class PreviewWindow: NSWindow {
    weak var preview: PreviewWindowController?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let preview, preview.handleKey(event) { return }
        super.sendEvent(event)
    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
        if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
        return rect
    }
}

private extension NSToolbarItem.Identifier {
    static let turnLeft = NSToolbarItem.Identifier("turnLeft")
    static let turnRight = NSToolbarItem.Identifier("turnRight")
    static let copyImage = NSToolbarItem.Identifier("copyImage")
    static let copyPath = NSToolbarItem.Identifier("copyPath")
    static let openApp = NSToolbarItem.Identifier("openApp")
}

final class PreviewWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let shared = PreviewWindowController()

    private var urls: [URL] = []
    private var index = 0
    private var kind: Opener.Kind = .other
    private var image: NSImage?
    private var fitting = true

    private let imageScroll = NSScrollView()
    private let imageView = NSImageView()
    private let playerView = AVPlayerView()
    private var quickLook: QLPreviewView?
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]

    private var url: URL? { urls.indices.contains(index) ? urls[index] : nil }

    private init() {
        let window = PreviewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.backgroundColor = .black
        window.setFrameAutosaveName("ExplorerPreview")
        super.init(window: window)
        window.preview = self
        window.delegate = self

        imageScroll.contentView = CenteringClipView()
        imageScroll.documentView = imageView
        imageScroll.allowsMagnification = true
        imageScroll.minMagnification = 0.02
        imageScroll.maxMagnification = 16
        imageScroll.hasVerticalScroller = true
        imageScroll.hasHorizontalScroller = true
        imageScroll.autohidesScrollers = true
        imageScroll.backgroundColor = .black
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(toggleZoom))
        doubleClick.numberOfClicksRequired = 2
        imageScroll.addGestureRecognizer(doubleClick)
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: imageScroll, queue: .main
        ) { [weak self] _ in self?.fitting = false }

        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true

        let toolbar = NSToolbar(identifier: "ExplorerPreviewToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Showing

    func show(_ url: URL, among siblings: [URL]) {
        let path = url.standardizedFileURL.path
        urls = siblings.contains { $0.standardizedFileURL.path == path } ? siblings : [url]
        index = urls.firstIndex { $0.standardizedFileURL.path == path } ?? 0
        load()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func load() {
        guard let url, let window else { return }
        stopContent()
        kind = Opener.kind(of: url)
        image = nil
        fitting = true
        window.title = "\(url.lastPathComponent) · \(index + 1) de \(urls.count)"
        window.representedURL = url

        switch kind {
        case .image:
            setContent(imageScroll)
            imageView.image = nil
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let loaded = ImageFile.load(url)
                DispatchQueue.main.async {
                    guard let self, self.url == url else { return }
                    if loaded == nil { return self.showQuickLook(url) }
                    self.image = loaded
                    self.showImage()
                }
            }
        case .video:
            setContent(playerView)
            playerView.player = AVPlayer(url: url)
            playerView.player?.play()
        case .other:
            showQuickLook(url)
        }
        updateToolbar()
    }

    private func showQuickLook(_ url: URL) {
        kind = .other
        let view = QLPreviewView(frame: window?.contentView?.bounds ?? .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        quickLook = view
        setContent(view)
        updateToolbar()
    }

    private func setContent(_ view: NSView) {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
    }

    private func stopContent() {
        playerView.player?.pause()
        playerView.player = nil
        quickLook?.close()
        quickLook = nil
    }

    private func showImage() {
        guard let image else { return }
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: image.size)
        fit()
    }

    private func fit() {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let bounds = imageScroll.bounds.size
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height, 1)
        imageScroll.magnification = scale
        fitting = true
    }

    @objc private func toggleZoom(_ gesture: NSClickGestureRecognizer) {
        guard kind == .image else { return }
        if fitting {
            let point = gesture.location(in: imageView)
            imageScroll.setMagnification(1, centeredAt: point)
            fitting = false
        } else {
            fit()
        }
    }

    func windowDidResize(_ notification: Notification) {
        if kind == .image && fitting { fit() }
    }

    func windowWillClose(_ notification: Notification) {
        stopContent()
        imageView.image = nil
        image = nil
    }

    // MARK: Keys

    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, flags) {
        case (123, []):
            step(-1)
        case (124, []):
            step(1)
        case (53, []):
            if window?.styleMask.contains(.fullScreen) == true { return false }
            close()
        case (49, []):
            if kind == .video, let player = playerView.player {
                player.timeControlStatus == .playing ? player.pause() : player.play()
            } else {
                close()
            }
        case (15, [.command]):
            turn(clockwise: true)
        case (37, [.command]):
            turn(clockwise: false)
        case (8, [.command]) where kind == .image:
            copyImage()
        case (8, [.command, .option]):
            copyPath()
        default:
            return false
        }
        return true
    }

    private func step(_ delta: Int) {
        guard !urls.isEmpty else { return }
        let next = index + delta
        guard urls.indices.contains(next) else { return NSSound.beep() }
        index = next
        load()
    }

    // MARK: Actions

    @objc private func turnLeft() { turn(clockwise: false) }

    @objc private func turnRight() { turn(clockwise: true) }

    private func turn(clockwise: Bool) {
        guard kind == .image, let url else { return NSSound.beep() }
        do {
            try ImageFile.turn(url, clockwise: clockwise)
        } catch {
            return showError("No se puede girar: \(error.localizedDescription)")
        }
        let wasFitting = fitting
        image = ImageFile.load(url)
        showImage()
        if !wasFitting { fit() }
    }

    @objc private func copyImage() {
        guard let image else { return NSSound.beep() }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    @objc private func copyPath() {
        guard let url else { return }
        FileOps.copyPaths([url])
    }

    @objc private func openInApp() {
        guard let url else { return }
        if case .app(let app) = Opener.handler(for: url) {
            FileOps.open(url, with: app)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Toolbar

    private func updateToolbar() {
        let isImage = kind == .image
        toolbarItems[.turnLeft]?.isEnabled = isImage
        toolbarItems[.turnRight]?.isEnabled = isImage
        toolbarItems[.copyImage]?.isEnabled = isImage
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .turnLeft, .turnRight, .copyImage, .copyPath, .openApp]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let specs: [NSToolbarItem.Identifier: (String, String, Selector)] = [
            .turnLeft: ("Girar a la izquierda (⌘L)", "rotate.left", #selector(turnLeft)),
            .turnRight: ("Girar a la derecha (⌘R)", "rotate.right", #selector(turnRight)),
            .copyImage: ("Copiar imagen (⌘C)", "doc.on.doc", #selector(copyImage)),
            .copyPath: ("Copiar ruta (⌥⌘C)", "link", #selector(copyPath)),
            .openApp: ("Abrir en su app", "arrow.up.forward.app", #selector(openInApp)),
        ]
        guard let (label, symbol, action) = specs[id] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        item.autovalidates = false
        toolbarItems[id] = item
        return item
    }
}
