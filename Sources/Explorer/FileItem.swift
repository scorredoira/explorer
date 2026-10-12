import AppKit

final class FileItem: NSObject {
    let url: URL
    let name: String
    let isFolder: Bool
    let modified: Date?
    let fileSize: Int64?
    let kind: String
    weak var parent: FileItem?
    var children: [FileItem]?

    var path: String { url.path }

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        .contentModificationDateKey, .fileSizeKey, .localizedTypeDescriptionKey,
    ]

    init(url: URL, parent: FileItem?) {
        self.url = url
        self.parent = parent
        name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: Set(FileItem.keys))
        var folder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        if values?.isSymbolicLink == true {
            let target = url.resolvingSymlinksInPath()
            let targetValues = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            folder = (targetValues?.isDirectory ?? false) && !(targetValues?.isPackage ?? false)
        }
        isFolder = folder
        modified = values?.contentModificationDate
        fileSize = folder ? nil : values?.fileSize.map(Int64.init)
        kind = values?.localizedTypeDescription ?? ""
    }

    static func list(_ dir: URL, parent: FileItem?) -> [FileItem] {
        let options: FileManager.DirectoryEnumerationOptions = Settings.showHidden ? [] : [.skipsHiddenFiles]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: options)) ?? []
        return urls.map { FileItem(url: $0, parent: parent) }
    }

    static func sort(_ items: [FileItem], by descriptor: NSSortDescriptor?) -> [FileItem] {
        let key = descriptor?.key ?? "name"
        let ascending = descriptor?.ascending ?? true
        return items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let result: ComparisonResult
            switch key {
            case "date":
                result = compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
            case "size":
                result = compare(a.displaySize ?? -1, b.displaySize ?? -1)
            case "kind":
                result = a.kind.localizedStandardCompare(b.kind)
            default:
                result = .orderedSame
            }
            let final = result == .orderedSame ? a.name.localizedStandardCompare(b.name) : result
            return ascending ? final == .orderedAscending : final == .orderedDescending
        }
    }

    var displaySize: Int64? {
        isFolder ? FolderSizes.shared.size(path) : fileSize
    }
}

private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
    a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
}
