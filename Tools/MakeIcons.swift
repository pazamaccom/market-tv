// Regenerates the layered tvOS app icon and top-shelf images.
// Usage: swift Tools/MakeIcons.swift MarketTV/Assets.xcassets
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MarketTV/Assets.xcassets"
let brand = root + "/App Icon & Top Shelf Image.brandassets"
let fm = FileManager.default
let info: [String: Any] = ["author": "xcode", "version": 1]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a) }
let navy = rgb(10, 26, 51), gridC = rgb(22, 44, 78), blue = rgb(7, 91, 203, 150.0 / 255), white = rgb(255, 255, 255), soft = rgb(183, 196, 216)
let pts: [(CGFloat, CGFloat)] = [(0, 0.62), (0.12, 0.55), (0.24, 0.66), (0.36, 0.48), (0.48, 0.52), (0.60, 0.36), (0.72, 0.42), (0.84, 0.24), (0.96, 0.30)]

func writeJSON(_ obj: Any, _ path: String) {
    try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
}

func render(_ w: Int, _ h: Int, opaque: Bool, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward, matching the design coordinates.
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    draw(ctx, CGFloat(w), CGFloat(h))
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
    try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

func linePoints(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> [CGPoint] {
    pts.map { CGPoint(x: x0 + (x1 - x0) * $0.0 / 0.96, y: y0 + (y1 - y0) * $0.1) }
}

func back(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    c.setFillColor(navy); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    c.setStrokeColor(gridC); c.setLineWidth(max(1, h / 240))
    for i in 1..<6 { let y = h * CGFloat(i) / 6; c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)) }
    c.strokePath()
}

func middle(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let x0 = w * 0.08, x1 = w * 0.92, p = linePoints(x0, x1, h * 0.15, h * 0.95)
    c.setFillColor(blue); c.addLines(between: p + [CGPoint(x: x1, y: h * 0.92), CGPoint(x: x0, y: h * 0.92)]); c.closePath(); c.fillPath()
}

func text(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: CGColor, bold: Bool = true) {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                          NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
    let line = CTLineCreateWithAttributedString(attr)
    c.saveGState(); c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    c.textPosition = CGPoint(x: x, y: y + size * 0.85); CTLineDraw(line, c); c.restoreGState()
}

func front(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, label: Bool) {
    let p = linePoints(w * 0.08, w * 0.92, h * 0.15, h * 0.95), lw = max(3, h / 40)
    c.setStrokeColor(white); c.setLineWidth(lw); c.setLineJoin(.round); c.setLineCap(.round)
    c.addLines(between: p); c.strokePath()
    let e = p.last!, r = lw * 1.6
    c.setFillColor(white); c.fillEllipse(in: CGRect(x: e.x - r, y: e.y - r, width: 2 * r, height: 2 * r))
    if label { text(c, "MARKET TV", w * 0.08, h * 0.06, h * 0.13, white) }
}

func stack(_ name: String, _ size: (Int, Int), _ scales: [Int]) {
    let dir = "\(brand)/\(name).imagestack"
    writeJSON(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Middle.imagestacklayer"], ["filename": "Back.imagestacklayer"]]], dir + "/Contents.json")
    for layer in ["Front", "Middle", "Back"] {
        let ld = "\(dir)/\(layer).imagestacklayer", cd = ld + "/Content.imageset"
        writeJSON(["info": info], ld + "/Contents.json")
        var images: [[String: String]] = []
        for s in scales {
            let file = layer.lowercased() + (s == 1 ? "" : "@\(s)x") + ".png"
            let img = render(size.0 * s, size.1 * s, opaque: layer == "Back") { c, w, h in
                switch layer {
                case "Back": back(c, w, h)
                case "Middle": middle(c, w, h)
                default: front(c, w, h, label: true)
                }
            }
            save(img, cd + "/" + file)
            images.append(["filename": file, "idiom": "tv", "scale": "\(s)x"])
        }
        writeJSON(["images": images, "info": info], cd + "/Contents.json")
    }
}

func shelf(_ name: String, _ size: (Int, Int)) {
    let dir = "\(brand)/\(name).imageset"
    var images: [[String: String]] = []
    for s in [1, 2] {
        let file = "shelf" + (s == 1 ? "" : "@2x") + ".png"
        let img = render(size.0 * s, size.1 * s, opaque: true) { c, w, h in
            back(c, w, h)
            c.saveGState(); c.translateBy(x: w * 0.38, y: 0)
            middle(c, w * 0.6, h); front(c, w * 0.6, h, label: false)
            c.restoreGState()
            text(c, "Market TV", w * 0.05, h * 0.36, h * 0.16, white)
            text(c, "US Market Health · Downturn · Today", w * 0.05, h * 0.56, h * 0.055, soft, bold: false)
        }
        save(img, dir + "/" + file)
        images.append(["filename": file, "idiom": "tv", "scale": "\(s)x"])
    }
    writeJSON(["images": images, "info": info], dir + "/Contents.json")
}

writeJSON(["info": info], root + "/Contents.json")
stack("App Icon", (400, 240), [1, 2])
stack("App Icon - App Store", (1280, 768), [1])
shelf("Top Shelf Image", (1920, 720))
shelf("Top Shelf Image Wide", (2320, 720))
writeJSON(["info": info, "assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
]], brand + "/Contents.json")
print("Icons written to \(brand)")
