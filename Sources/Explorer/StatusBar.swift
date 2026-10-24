import AppKit

/// The line under the list: what the folder holds, or what is selected, and the free space.
final class StatusBar: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}

private let sizeFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter
}()

private func counted(_ count: Int, _ one: String, _ many: String) -> String {
    "\(count.formatted()) \(count == 1 ? one : many)"
}

extension BrowserWindowController {
    func updateStatus() {
        var parts: [String] = []
        let selected = selectedItems()
        if selected.isEmpty {
            let folders = rootItems.filter(\.isFolder).count
            let files = rootItems.count - folders
            parts.append(rootItems.isEmpty
                ? "No items"
                : "\(counted(folders, "folder", "folders")), \(counted(files, "file", "files"))")
            if !filterText.isEmpty { parts.append("filtered from \(allRootItems.count.formatted())") }
            parts.append(FolderSizes.shared.size(current.path).map { sizeFormatter.string(fromByteCount: $0) } ?? "…")
        } else {
            parts.append("\(selected.count.formatted()) of \(outline.numberOfRows.formatted()) selected")
            let sizes = selected.map(\.displaySize)
            if !sizes.contains(where: { $0 == nil }) {
                parts.append(sizeFormatter.string(fromByteCount: sizes.reduce(0) { $0 + ($1 ?? 0) }))
            }
        }
        if let availableSpace { parts.append("\(sizeFormatter.string(fromByteCount: availableSpace)) available") }
        statusBar.text = parts.joined(separator: " · ")
    }

    /// Read off the main thread: on a network volume it can take a while.
    func refreshAvailableSpace() {
        let dir = current
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            let space = values?.volumeAvailableCapacityForImportantUsage
            DispatchQueue.main.async {
                guard let self, self.current == dir else { return }
                self.availableSpace = space
                self.updateStatus()
            }
        }
    }
}
