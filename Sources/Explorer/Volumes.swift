import AppKit
import NetFS
import UniformTypeIdentifiers

/// Network volumes (SMB, AFP, NFS…) mounted again on demand, so a favorite on one keeps working
/// after a restart or a disconnect.
enum Volumes {
    /// userCanceledErr: the person closed the sign-in dialog.
    private static let userCanceled: Int32 = -128

    /// The icon macOS gives a mounted network volume, available while it is not mounted too.
    static var serverIcon: NSImage {
        NSWorkspace.shared.icon(for: UTType("com.apple.file-server") ?? .folder)
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
