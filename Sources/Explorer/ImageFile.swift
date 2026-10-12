import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageFile {
    enum Failure: LocalizedError {
        case unreadable
        case unwritable

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Cannot read the image."
            case .unwritable: return "Cannot save the image."
            }
        }
    }

    static func load(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        if CGImageSourceGetCount(source) > 1, let data = try? Data(contentsOf: url) {
            return NSImage(data: data)
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func turn(_ url: URL, clockwise: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { throw Failure.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let current = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let next = turned(current, clockwise: clockwise)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).explorer-turn")
        defer { try? FileManager.default.removeItem(at: temp) }

        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else { throw Failure.unwritable }
        let lossless = CGImageDestinationCopyImageSource(
            destination, source, [kCGImageDestinationOrientation: next] as CFDictionary, nil)
        if !lossless {
            try reencode(source, type: type, orientation: next, properties: properties, to: temp)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func reencode(_ source: CGImageSource, type: CFString, orientation: UInt32,
                                 properties: [CFString: Any], to temp: URL) throws {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else { throw Failure.unreadable }
        var output = properties
        output[kCGImagePropertyOrientation] = orientation
        output[kCGImageDestinationLossyCompressionQuality] = 0.95
        CGImageDestinationAddImage(destination, image, output as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unwritable }
    }

    private static func turned(_ orientation: UInt32, clockwise: Bool) -> UInt32 {
        let plain: [UInt32] = [1, 6, 3, 8]
        let mirrored: [UInt32] = [2, 7, 4, 5]
        let cycle = plain.contains(orientation) ? plain : mirrored
        let index = cycle.firstIndex(of: orientation) ?? 0
        return cycle[(index + (clockwise ? 1 : 3)) % 4]
    }
}
