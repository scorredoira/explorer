import AppKit
import NetFS

/// Network volumes (SMB, AFP, NFS…) mounted again on demand, so a favorite on one keeps working
/// after a restart or a disconnect.
enum Volumes {
    /// userCanceledErr: the person closed the sign-in dialog.
    private static let userCanceled: Int32 = -128

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

    /// Mounts the volume of `url` and calls `done(true)` once `url` is there, `done(false)` if it
    /// could not be mounted (errors are shown). A second call while the volume is being mounted
    /// does nothing.
    static func mount(_ url: URL, done: @escaping (Bool) -> Void) {
        guard let remote = remountURL(for: url), !mounting.contains(remote) else { return }
        mounting.insert(remote)
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(remote as CFURL, nil, nil, nil, nil, nil, &request, .main) { status, _, _ in
            mounting.remove(remote)
            if status == ECANCELED || status == userCanceled {
                done(false)
            } else if status != 0 && status != EEXIST {
                showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
                done(false)
            } else if isFolder(url) {
                done(true)
            } else {
                showError("Connected to \(remote.absoluteString), but \(url.path) is not there.")
                done(false)
            }
        }
        if status != 0 {
            mounting.remove(remote)
            done(false)
            showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
        }
    }

    private static func errorText(_ status: Int32) -> String {
        String(cString: strerror(status))
    }
}
