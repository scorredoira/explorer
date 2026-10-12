import AppKit

enum FileOps {
    static func transfer(_ urls: [URL], to dir: URL, move: Bool, completion: (([URL]) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [URL] = []
            var errors: [String] = []
            for src in urls {
                let sameFolder = src.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path
                if move && sameFolder {
                    results.append(src)
                    continue
                }
                if dir.standardizedFileURL.path == src.standardizedFileURL.path
                    || dir.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/") {
                    errors.append("No se puede meter «\(src.lastPathComponent)» dentro de sí misma.")
                    continue
                }
                let dest = uniqueURL(dir.appendingPathComponent(src.lastPathComponent), copy: !move && sameFolder)
                do {
                    if move {
                        try FileManager.default.moveItem(at: src, to: dest)
                    } else {
                        try FileManager.default.copyItem(at: src, to: dest)
                    }
                    results.append(dest)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            DispatchQueue.main.async {
                if !errors.isEmpty { showError(errors.joined(separator: "\n")) }
                completion?(results)
            }
        }
    }

    static func uniqueURL(_ url: URL, copy: Bool = false) -> URL {
        let fm = FileManager.default
        if !copy && !fm.fileExists(atPath: url.path) { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let stem = copy ? "\(base) copia" : base
        var n = copy ? 1 : 2
        while true {
            let name = n == 1 ? stem : "\(stem) \(n)"
            let candidate = dir.appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func trash(_ urls: [URL]) {
        NSWorkspace.shared.recycle(urls) { _, error in
            if let error { showError(error.localizedDescription) }
        }
    }

    static func createFolder(in dir: URL) -> URL? {
        let url = uniqueURL(dir.appendingPathComponent("carpeta sin título"))
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            return url
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    static func createFile(in dir: URL) -> URL? {
        let url = uniqueURL(dir.appendingPathComponent("archivo sin título"))
        guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
            showError("No se pudo crear el archivo en \(dir.path).")
            return nil
        }
        return url
    }

    static func rename(_ url: URL, to name: String) -> URL? {
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        } catch {
            showError(error.localizedDescription)
            return nil
        }
    }

    static func dropOperation(_ info: NSDraggingInfo, urls: [URL], to dir: URL) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        if mask == .copy { return .copy }
        let dirVolume = volume(dir)
        let sameVolume = urls.allSatisfy { volume($0) == dirVolume }
        if sameVolume && mask.contains(.move) { return .move }
        if mask.contains(.copy) { return .copy }
        return mask.contains(.move) ? .move : []
    }

    private static func volume(_ url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    static func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let appPath = Settings.openWith[ext], FileManager.default.fileExists(atPath: appPath) {
            open(url, with: URL(fileURLWithPath: appPath))
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func open(_ url: URL, with app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { showError(error.localizedDescription) } }
        }
    }

    static func openTerminal(at dir: URL) {
        guard let app = Settings.terminalApp else {
            showError("No se encuentra la terminal. Elígela en Ajustes.")
            return
        }
        guard Bundle(url: app)?.bundleIdentifier == Settings.ghosttyBundleID else {
            open(dir, with: app)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--working-directory=\(dir.path)"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { DispatchQueue.main.async { showError(error.localizedDescription) } }
        }
    }

    static let denCommand: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/den", "/opt/homebrew/bin/den", "/usr/local/bin/den"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }()

    static func openInDen(_ urls: [URL]) {
        guard let den = denCommand else {
            showError("No se encuentra el comando den.")
            return
        }
        for url in urls {
            let process = Process()
            process.executableURL = den
            process.arguments = [url.path]
            do {
                try process.run()
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    static func copyPaths(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }
}

enum FileClipboard {
    private static var cutPaths: Set<String> = []
    private static var cutChangeCount = -1

    static func write(_ urls: [URL], cut: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        cutPaths = cut ? Set(urls.map(\.path)) : []
        cutChangeCount = cut ? pb.changeCount : -1
        NotificationCenter.default.post(name: .clipboardChanged, object: nil)
    }

    static func urls() -> [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static var hasFiles: Bool { !urls().isEmpty }

    static var isCut: Bool { NSPasteboard.general.changeCount == cutChangeCount && !cutPaths.isEmpty }

    static func isCut(_ path: String) -> Bool { isCut && cutPaths.contains(path) }

    static func paste(into dir: URL, completion: (([URL]) -> Void)? = nil) {
        let list = urls()
        guard !list.isEmpty else { return }
        let move = isCut
        if move {
            cutPaths = []
            cutChangeCount = -1
            NotificationCenter.default.post(name: .clipboardChanged, object: nil)
        }
        FileOps.transfer(list, to: dir, move: move, completion: completion)
    }
}

func showError(_ message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "No se pudo completar"
    alert.informativeText = message
    alert.runModal()
}
