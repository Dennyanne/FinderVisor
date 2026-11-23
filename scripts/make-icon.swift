// Renders FinderVisor's app icon into an asset-catalog .appiconset.
// Usage: swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
//
// Design: a night-blue macOS squircle (the screen) with a light Finder-style window docked
// along its bottom edge, a folder inside it, and a chevron above it for the window rising.
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Draws the icon on a 1024x1024 canvas (origin bottom-left).
func drawIcon(_ ctx: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.clear(canvas)

    // Squircle body on Apple's 824 pt icon grid, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x1B2A6B))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [color(0x3B5BDB), color(0x1B2A6B), color(0x0B1238)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Faint glow behind the docked window.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x8FB3FF, 0.35), color(0x8FB3FF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 380), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 380), endRadius: 420, options: [])

    // Docked window: spans the body's width and sits on its bottom edge (clipped by the squircle).
    let window = CGRect(x: 100, y: 100, width: 824, height: 400)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 40, color: color(0x000000, 0.45))
    ctx.addPath(CGPath(roundedRect: window, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.setFillColor(color(0xF4F6FB))
    ctx.fillPath()
    ctx.restoreGState()

    // Title bar with three window buttons.
    let titleBar = CGRect(x: 100, y: 430, width: 824, height: 70)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: window, cornerWidth: 46, cornerHeight: 46, transform: nil))
    ctx.clip()
    ctx.setFillColor(color(0xDDE3F0))
    ctx.fill(titleBar)
    ctx.restoreGState()
    for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(color(hex))
        ctx.fillEllipse(in: CGRect(x: 160 + CGFloat(i) * 52, y: 448, width: 34, height: 34))
    }

    // Folder in the window.
    let folderBack = CGMutablePath()
    folderBack.move(to: CGPoint(x: 392, y: 380))
    folderBack.addLine(to: CGPoint(x: 470, y: 380))
    folderBack.addLine(to: CGPoint(x: 494, y: 356))
    folderBack.addLine(to: CGPoint(x: 632, y: 356))
    folderBack.addLine(to: CGPoint(x: 632, y: 230))
    folderBack.addLine(to: CGPoint(x: 392, y: 230))
    folderBack.closeSubpath()
    ctx.addPath(folderBack)
    ctx.setFillColor(color(0x4C8DF6))
    ctx.fillPath()
    let folderFront = CGPath(roundedRect: CGRect(x: 392, y: 190, width: 240, height: 150),
                             cornerWidth: 16, cornerHeight: 16, transform: nil)
    ctx.addPath(folderFront)
    ctx.setFillColor(color(0x6FA8FF))
    ctx.fillPath()

    // Chevron above the window: the Visor rises from the bottom edge.
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(50)
    ctx.setStrokeColor(color(0xFFFFFF, 0.95))
    ctx.move(to: CGPoint(x: 397, y: 655))
    ctx.addLine(to: CGPoint(x: 512, y: 765))
    ctx.addLine(to: CGPoint(x: 627, y: 655))
    ctx.strokePath()

    ctx.restoreGState()

    // Thin inner highlight on the squircle rim.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()
}

func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let master = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                           space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(master)
    let image = master.makeImage()!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// macOS app icon slots: (point size, scale).
let slots: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (size, scale) in slots {
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try render(pixels: size * scale).write(to: outDir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icons to \(outDir.path)")
