import AppKit
import NetFS

/// Network volumes (SMB, AFP, NFS…) mounted again on demand, so a favorite on one keeps working
/// after a restart or a disconnect.
enum Volumes {
    /// userCanceledErr: the person closed the sign-in dialog.
    private static let userCanceled: Int32 = -128

    /// A folder with a server glyph, drawn like the system folders (Downloads, Desktop…).
    static var serverIcon: NSImage {
        let folder = NSWorkspace.shared.icon(for: .folder)
        let tint = NSColor(srgbRed: 0.30, green: 0.58, blue: 0.84, alpha: 0.75)
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            folder.draw(in: rect)
            let config = NSImage.SymbolConfiguration(pointSize: rect.height * 0.34, weight: .medium)
                .applying(.init(paletteColors: [tint]))
            guard let glyph = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return true }
            let size = glyph.size
            glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.height * 0.39 - size.height / 2,
                                  width: size.width, height: size.height))
            return true
        }
    }

    static func remember(_ url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeURLForRemountingKey]),
              let volume = values.volume, let remount = values.volumeURLForRemounting else { return }
        Settings.remounts[volume.standardizedFileURL.path] = remount.absoluteString
    }

    static func remountURL(for url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        for (volume, remount) in Settings.remounts where path == volume || path.hasPrefix(volume + "/") {
            return URL(string: remount)
        }
        return nil
    }

    /// Mounts the volume of `url` and calls `done` once `url` is there. Errors are shown.
    static func mount(_ url: URL, done: @escaping () -> Void) {
        guard let remote = remountURL(for: url) else { return }
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(remote as CFURL, nil, nil, nil, nil, nil, &request, .main) { status, _, _ in
            if status == ECANCELED || status == userCanceled {
                return
            } else if status != 0 && status != EEXIST {
                showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
            } else if isFolder(url) {
                done()
            } else {
                showError("Connected to \(remote.absoluteString), but \(url.path) is not there.")
            }
        }
        if status != 0 {
            showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
        }
    }

    private static func errorText(_ status: Int32) -> String {
        String(cString: strerror(status))
    }
}
