// App-icon generator. Renders the Option Now icon (⌥ glyph on an indigo squircle)
// at all iconset sizes into the directory given as argv[1].
// Usage: swiftc make_icon.swift -o make_icon && ./make_icon AppIcon.iconset
import AppKit

func render(_ S: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let cg = gctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: S, height: S))

    // Tile (squircle) with a small margin, plus a soft drop shadow.
    let margin = S * 0.085
    let tile = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let radius = tile.width * 0.2237
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    cg.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.012)
    shadow.shadowBlurRadius = S * 0.035
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    cg.restoreGState()

    // Indigo→blue vertical gradient.
    cg.saveGState()
    path.addClip()
    let top = NSColor(calibratedRed: 0.46, green: 0.56, blue: 1.00, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.27, green: 0.32, blue: 0.80, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)

    // Top sheen for depth.
    let sheen = NSGradient(starting: NSColor.white.withAlphaComponent(0.20),
                           ending: NSColor.white.withAlphaComponent(0.0))!
    sheen.draw(in: CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2),
               angle: -90)

    // ⌥ hero glyph, centered, near-white with a soft shadow.
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    glyphShadow.shadowOffset = NSSize(width: 0, height: -S * 0.006)
    glyphShadow.shadowBlurRadius = S * 0.012
    glyphShadow.set()

    let fontSize = tile.width * 0.56
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.98),
        .paragraphStyle: para
    ]
    let str = NSAttributedString(string: "⌥", attributes: attrs)
    let bbox = str.size()
    str.draw(at: CGPoint(x: tile.midX - bbox.width / 2, y: tile.midY - bbox.height / 2))
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let specs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in specs {
    let data = render(size)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("wrote \(specs.count) PNGs to \(outDir)")
