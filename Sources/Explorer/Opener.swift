import AVFoundation
import AppKit
import UniformTypeIdentifiers

enum Opener {
    static let previewID = "preview"
    static let vlcBundleID = "org.videolan.vlc"

    enum Handler {
        case preview
        case app(URL)
        case system
    }

    enum Kind {
        case image
        case video
        case other
    }

    static func handler(for url: URL) -> Handler {
        let ext = url.pathExtension.lowercased()
        if let assigned = Settings.openWith[ext] {
            if assigned == previewID { return .preview }
            if FileManager.default.fileExists(atPath: assigned) { return .app(URL(fileURLWithPath: assigned)) }
        }
        switch kind(of: url) {
        case .image, .video:
            return .preview
        case .other:
            if isMovie(url), let vlc = NSWorkspace.shared.urlForApplication(withBundleIdentifier: vlcBundleID) {
                return .app(vlc)
            }
            return .system
        }
    }

    static func opensInPreview(_ url: URL) -> Bool {
        if case .preview = handler(for: url) { return true }
        return false
    }

    static func kind(of url: URL) -> Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audiovisualContent), playableTypes.contains(where: { type.conforms(to: $0) }) {
            return isMovie(url) ? .video : .other
        }
        return .other
    }

    private static func isMovie(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    private static let playableTypes: [UTType] = AVURLAsset.audiovisualTypes().compactMap { UTType($0.rawValue) }
}
