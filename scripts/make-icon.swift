import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func rounded(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
rounded(tile, 185).addClip()
NSGradient(starting: NSColor(red: 0.36, green: 0.71, blue: 1.0, alpha: 1),
           ending: NSColor(red: 0.10, green: 0.42, blue: 0.88, alpha: 1))!.draw(in: tile, angle: -90)
ctx.restoreGState()

let sheet = CGRect(x: 200, y: 230, width: 624, height: 560)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
NSColor.white.setFill()
rounded(sheet, 44).fill()
ctx.restoreGState()

let rowHeight: CGFloat = 112
let widths: [CGFloat] = [300, 230, 330, 260]
for i in 0..<4 {
    let y = sheet.maxY - 48 - CGFloat(i + 1) * rowHeight
    if i % 2 == 1 {
        NSColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1).setFill()
        rounded(CGRect(x: sheet.minX + 24, y: y + 6, width: sheet.width - 48, height: rowHeight - 12), 22).fill()
    }
    let folder = NSColor(red: 0.29, green: 0.64, blue: 0.97, alpha: 1)
    folder.setFill()
    let fx = sheet.minX + 64, fy = y + 28
    rounded(CGRect(x: fx, y: fy + 46, width: 40, height: 20), 8).fill()
    rounded(CGRect(x: fx, y: fy, width: 92, height: 60), 12).fill()
    NSColor(red: 0.78, green: 0.83, blue: 0.90, alpha: 1).setFill()
    rounded(CGRect(x: fx + 128, y: y + 44, width: widths[i], height: 26), 13).fill()
}

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
