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
        guard let remote = remountURL(for: url) else { return }
        connect(remote) { volume in
            if volume == nil {
                done(false)
            } else if isFolder(url) {
                done(true)
            } else {
                showError("Connected to \(remote.absoluteString), but \(url.path) is not there.")
                done(false)
            }
        }
    }

    /// Mounts `remote` (smb://host/share…) unless it is mounted already, and calls `done` with the
    /// folder it is mounted on, or nil if it could not be mounted (errors are shown). A second call
    /// while it is being mounted does nothing.
    static func connect(_ remote: URL, done: @escaping (URL?) -> Void) {
        if let volume = mountedVolume(of: remote) {
            done(volume)
            return
        }
        guard !mounting.contains(remote) else { return }
        mounting.insert(remote)
        var request: AsyncRequestID?
        let status = NetFSMountURLAsync(remote as CFURL, nil, nil, nil, nil, nil, &request, .main) { status, _, mountpoints in
            mounting.remove(remote)
            let paths = mountpoints as? [String] ?? []
            if status == ECANCELED || status == userCanceled {
                done(nil)
            } else if status != 0 && status != EEXIST {
                showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
                done(nil)
            } else if let volume = paths.first.map({ URL(fileURLWithPath: $0) }) ?? mountedVolume(of: remote) {
                done(volume)
            } else {
                showError("Connected to \(remote.absoluteString), but it is not mounted anywhere.")
                done(nil)
            }
        }
        if status != 0 {
            mounting.remove(remote)
            done(nil)
            showError("Could not connect to \(remote.host ?? remote.absoluteString): \(errorText(status))")
        }
    }

    /// The folder `remote` is mounted on, matched by scheme, host and share; with no share in
    /// `remote`, any volume of that host.
    static func mountedVolume(of remote: URL) -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeURLForRemountingKey]) ?? []
        for volume in volumes {
            guard let other = try? volume.resourceValues(forKeys: [.volumeURLForRemountingKey]).volumeURLForRemounting,
                  other.scheme?.lowercased() == remote.scheme?.lowercased(),
                  other.host?.lowercased() == remote.host?.lowercased() else { continue }
            if share(remote).isEmpty || share(remote) == share(other) { return volume }
        }
        return nil
    }

    private static func share(_ url: URL) -> String {
        url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func errorText(_ status: Int32) -> String {
        String(cString: strerror(status))
    }
}
