import Foundation

final class FolderSizes {
    static let shared = FolderSizes()

    private struct Entry {
        var size: Int64
        var computedAt: Date
        var stale: Bool
    }

    private var cache: [String: Entry] = [:]
    private let refreshInterval: TimeInterval = 30

    func size(_ path: String) -> Int64? {
        cache[path]?.size
    }

    func needsCompute(_ path: String) -> Bool {
        guard let entry = cache[path] else { return true }
        return entry.stale && Date().timeIntervalSince(entry.computedAt) > refreshInterval
    }

    func store(_ path: String, size: Int64) {
        cache[path] = Entry(size: size, computedAt: Date(), stale: false)
        NotificationCenter.default.post(name: .folderSizeUpdated, object: path)
    }

    func invalidate(changedPath: String) {
        var path = changedPath
        while path.count > 1 {
            cache[path]?.stale = true
            path = (path as NSString).deletingLastPathComponent
        }
    }

    static func compute(_ url: URL, isCancelled: () -> Bool) -> Int64? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return nil }
        var total: Int64 = 0
        var count = 0
        for case let file as URL in enumerator {
            count += 1
            if count % 500 == 0 && isCancelled() { return nil }
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
