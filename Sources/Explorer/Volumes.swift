import AppKit
import NetFS

/// Network volumes (SMB, AFP, NFS…) mounted again on demand, so a favorite on one keeps working
/// after a restart or a disconnect.
enum Volumes {
    /// userCanceledErr: the person closed the sign-in dialog.
    private static let userCanceled: Int32 = -128

    /// A server, in the blue of the folder icons around it.
    static var serverIcon: NSImage {
        let blue = NSColor(srgbRed: 0.36, green: 0.66, blue: 0.92, alpha: 1)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(.init(paletteColors: [blue]))
        return NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Server")?
            .withSymbolConfiguration(config) ?? NSWorkspace.shared.icon(for: .folder)
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

    /// Remote URLs being mounted right now.
    private static var mounting: Set<URL> = []

    static func isMounting(_ url: URL) -> Bool {
        remountURL(for: url).map(mounting.contains) ?? false
    }

    private static func setMounting(_ remote: URL, _ on: Bool) {
        if on { mounting.insert(remote) } else { mounting.remove(remote) }
        NotificationCenter.default.post(name: .volumeMountingChanged, object: nil)
    }

    /// Mounts the volume of `url` and calls `done` once `url` is there. Errors are shown.
    /// A second call while the volume is being mounted does nothing.
    static func mount(_ url: URL, done: @escaping () -> Void) {
        guard let remote = remountURL(for: url), !mounting.contains(remote) else { return }
        setMounting(remote, true)
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(remote as CFURL, nil, nil, nil, nil, nil, &request, .main) { status, _, _ in
            setMounting(remote, false)
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
            setMounting(remote, false)
            showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
        }
    }

    private static func errorText(_ status: Int32) -> String {
        String(cString: strerror(status))
    }
}
