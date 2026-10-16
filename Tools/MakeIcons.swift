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
func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor { rgb(CGFloat((v >> 16) & 255), CGFloat((v >> 8) & 255), CGFloat(v & 255), a) }
let white = rgb(255, 255, 255), soft = rgb(183, 196, 216)
// Yield-curve ribbons in the hub's Yield, Market and Turkey card colours.
let ribbonColors: [UInt32] = [0xA269FF, 0x00BAFF, 0xFF365E]

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

func back(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let g = CGGradient(colorsSpace: nil, colors: [hex(0x1A1240), hex(0x05060F)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: .zero, end: CGPoint(x: w * 0.3, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func glow(_ c: CGContext, _ p: CGPoint, _ r: CGFloat, _ color: UInt32, _ a: CGFloat) {
    let g = CGGradient(colorsSpace: nil, colors: [hex(color, a), hex(color, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
}

/// Three curves rising left to right inside `r`, faded out towards the left so the wordmark stays clear.
func ribbons(_ c: CGContext, _ r: CGRect, fadeFrom: CGFloat, fadeTo: CGFloat) {
    let u = r.height / 480
    c.saveGState()
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    for (j, color) in ribbonColors.enumerated() {
        let jj = CGFloat(j)
        for t in 0..<3 {
            c.setStrokeColor(hex(color, t == 2 ? 1 : 0.18)); c.setLineWidth((t == 2 ? 7 : CGFloat(30 - t * 10)) * u); c.setLineCap(.round)
            c.move(to: CGPoint(x: r.minX - 20 * u, y: r.minY + r.height * (0.80 - jj * 0.08)))
            c.addCurve(to: CGPoint(x: r.maxX + 20 * u, y: r.minY + r.height * (0.22 + jj * 0.10)),
                       control1: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * (0.85 - jj * 0.05)),
                       control2: CGPoint(x: r.minX + r.width * 0.45, y: r.minY + r.height * (0.15 + jj * 0.1)))
            c.strokePath()
        }
    }
    let dot = CGPoint(x: r.minX + r.width * 0.86, y: r.minY + r.height * 0.24)
    glow(c, dot, 90 * u, 0xFFFFFF, 0.5)
    c.setFillColor(white); c.fillEllipse(in: CGRect(x: dot.x - 12 * u, y: dot.y - 12 * u, width: 24 * u, height: 24 * u))
    // Erase towards the left: fully clear before fadeFrom, untouched after fadeTo.
    c.setBlendMode(.destinationOut)
    let fade = CGGradient(colorsSpace: nil, colors: [white, white, rgb(255, 255, 255, 0)] as CFArray, locations: [0, fadeFrom, fadeTo])!
    c.drawLinearGradient(fade, start: .zero, end: CGPoint(x: c.width == 0 ? 1 : CGFloat(c.width), y: 0), options: [])
    c.endTransparencyLayer()
    c.restoreGState()
}

func middle(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    ribbons(c, CGRect(x: 0, y: 0, width: w, height: h), fadeFrom: 0.6, fadeTo: 0.85)
}

func text(_ c: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: CGColor, font: String = "Didot", kern: CGFloat = 0) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                          NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                                                          NSAttributedString.Key(kCTKernAttributeName as String): kern])
    let line = CTLineCreateWithAttributedString(attr)
    c.saveGState(); c.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    c.textPosition = CGPoint(x: x, y: y + size * 0.85); CTLineDraw(line, c); c.restoreGState()
}

/// "P | ANALYTICS" over "MARKETS · DATA", like the hub's wordmark. Laid out on an 800×480 grid scaled by `u`.
func wordmark(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, _ u: CGFloat) {
    text(c, "P", x, y + 96 * u, 250 * u, white)
    c.setFillColor(rgb(255, 255, 255, 0.8)); c.fill(CGRect(x: x + 192 * u, y: y + 130 * u, width: 3 * u, height: 221 * u))
    text(c, "ANALYTICS", x + 220 * u, y + 178 * u, 46 * u, white, kern: 3 * u)
    text(c, "MARKETS · DATA", x + 222 * u, y + 250 * u, 19 * u, soft, font: "HelveticaNeue-Medium", kern: 5 * u)
}

func front(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    wordmark(c, w * 0.06, 0, h / 480)
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
                default: front(c, w, h)
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
            ribbons(c, CGRect(x: w * 0.30, y: 0, width: w * 0.70, height: h), fadeFrom: 0.42, fadeTo: 0.62)
            wordmark(c, w * 0.05, h * 0.02, h / 480 * 0.85)
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
