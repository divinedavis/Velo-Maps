// Velo Maps logo directions + the app icon (owner picked "Arrow", 2026-11-09).
//   swiftc -O scripts/make_icons.swift -o /tmp/icons && /tmp/icons <preview-dir> marketing/brand
// writes the 5 concept icons + overview to <preview-dir>; with a 2nd dir, also the full-bleed
// opaque icon-1024.png (copy into VeloMaps/Assets.xcassets/AppIcon.appiconset/) and arrow-mark.png.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments[1]
let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func newCtx(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func save(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); precondition(CGImageDestinationFinalize(d))
}
func vgrad(_ c: CGContext, _ rect: CGRect, _ top: CGColor, _ bottom: CGColor) {
    let g = CGGradient(colorsSpace: space, colors: [bottom, top] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
/// Inner bevel: highlight along the top inside edge, shade along the bottom (raised look).
func bevel(_ c: CGContext, _ p: CGPath, depth: CGFloat, light: CGFloat = 0.55, dark: CGFloat = 0.38) {
    let hole = CGMutablePath(); hole.addRect(CGRect(x: -2000, y: -2000, width: 5000, height: 5000)); hole.addPath(p)
    for (dy, col) in [(depth, hex(0x000000, dark)), (-depth * 0.8, hex(0xFFFFFF, light))] {
        c.saveGState(); c.addPath(p); c.clip()
        c.setShadow(offset: CGSize(width: 0, height: dy), blur: depth * 1.6, color: col)
        c.addPath(hole); c.setFillColor(hex(0x000000)); c.fillPath(using: .evenOdd)
        c.restoreGState()
    }
}
/// A raised, glossy shape: silver rim + drop shadow, gradient colour bands separated by
/// silver lines, a bevel on each band and a gloss on top.
func emboss(_ c: CGContext, _ body: CGPath, _ bands: [(CGPath, UInt32, UInt32)], rim: CGFloat = 18, shadow: CGFloat = 1) {
    let outline = body.copy(strokingWithWidth: rim * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).union(body)
    let box = outline.boundingBoxOfPath
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -26 * shadow), blur: 44 * shadow, color: hex(0x000000, 0.5))
    c.addPath(outline); c.setFillColor(hex(0xDDE1EA)); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(outline); c.clip(); vgrad(c, box, hex(0xFFFFFF), hex(0xB9C0CE)); c.restoreGState()
    bevel(c, outline, depth: rim * 0.5, light: 0.9, dark: 0.25)
    for (band, top, bottom) in bands {
        c.saveGState(); c.addPath(body); c.clip(); c.addPath(band); c.clip()
        vgrad(c, box, hex(top), hex(bottom)); c.restoreGState()
    }
    for (band, _, _) in bands where bands.count > 1 {   // silver separators
        c.saveGState(); c.addPath(body); c.clip()
        c.addPath(band); c.setStrokeColor(hex(0xE9ECF2)); c.setLineWidth(rim * 1.1); c.setLineJoin(.round); c.strokePath()
        c.restoreGState()
    }
    for (band, _, _) in bands {
        let inner = band.intersection(body).copy(strokingWithWidth: bands.count > 1 ? rim * 0.55 : 0.01, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let shape = band.intersection(body).subtracting(inner)
        bevel(c, shape, depth: rim * 0.9)
    }
    c.saveGState(); c.addPath(body); c.clip()          // gloss on the upper part
    let g = CGGradient(colorsSpace: space, colors: [hex(0xFFFFFF, 0), hex(0xFFFFFF, 0.30)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: box.midY), end: CGPoint(x: 0, y: box.maxY), options: [])
    c.restoreGState()
}
/// The tile: rounded square, gradient, soft lip.
var fullBleed = false, markOnly = false
func tile(_ c: CGContext, _ top: UInt32, _ bottom: UInt32) {
    if markOnly { return }
    let r = fullBleed ? CGRect(x: -400, y: -400, width: 1824, height: 1824) : CGRect(x: 72, y: 72, width: 880, height: 880)
    let p = fullBleed ? CGPath(rect: r, transform: nil) : CGPath(roundedRect: r, cornerWidth: 200, cornerHeight: 200, transform: nil)
    c.saveGState(); c.addPath(p); c.clip(); vgrad(c, r, hex(top), hex(bottom)); c.restoreGState()
    bevel(c, p, depth: 14, light: 0.35, dark: 0.35)
    c.saveGState(); c.addPath(p); c.clip()
    let g = CGGradient(colorsSpace: space, colors: [hex(0xFFFFFF, 0.16), hex(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: 360, y: 900), startRadius: 0, endCenter: CGPoint(x: 360, y: 900), endRadius: 700, options: [])
    c.restoreGState()
}
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) }); p.closeSubpath(); return p
}
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil) }
func diag(_ c0: CGFloat, _ c1: CGFloat, slope: CGFloat = -0.9) -> CGPath {     // region between two slanted lines
    func y(_ x: CGFloat, _ c: CGFloat) -> CGFloat { slope * (x - 512) + c }
    return poly([(-200, y(-200, c0)), (1300, y(1300, c0)), (1300, y(1300, c1)), (-200, y(-200, c1))])
}

let RED: (UInt32, UInt32) = (0xF0414A, 0xB80F1C), BLUE: (UInt32, UInt32) = (0x4F6BE8, 0x2235A8)
let GOLD: (UInt32, UInt32) = (0xFFD34D, 0xF2A516), SKY: (UInt32, UInt32) = (0x6CC4FF, 0x2B86D6)
let NAVY: (UInt32, UInt32) = (0x34449A, 0x18225E), SILVER: (UInt32, UInt32) = (0xFFFFFF, 0xD4D9E4)

var icons: [(String, String, (CGContext) -> Void)] = []

// 1 — Route Pin: a map pin in three slanted bands.
icons.append(("Route Pin", "A map pin in three raised bands (gold, Velo red, sky) on royal blue", { c in
    tile(c, 0x3E52C8, 0x1E2A80)
    let cx: CGFloat = 512, cy: CGFloat = 585, r: CGFloat = 228, tip = CGPoint(x: 512, y: 178)
    let a = acos(r / (cy - tip.y))
    let pin = CGMutablePath(); pin.move(to: tip)
    pin.addLine(to: CGPoint(x: cx + r * cos(-.pi / 2 + a), y: cy + r * sin(-.pi / 2 + a)))
    pin.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: -.pi / 2 + a, endAngle: 1.5 * .pi - a, clockwise: false)
    pin.closeSubpath()
    emboss(c, pin, [(diag(2000, 760), GOLD.0, GOLD.1), (diag(760, 500), RED.0, RED.1), (diag(500, -2000), SKY.0, SKY.1)])
}))

// 2 — Arrow: the navigation arrow, half silver half navy, on Velo red.
icons.append(("Arrow", "The navigation arrow, split silver and navy, on Velo red", { c in
    tile(c, 0xEE3B44, 0x9A0B16)
    let arrow = poly([(512, 820), (772, 214), (512, 356), (252, 214)])
    emboss(c, arrow, [(poly([(0, 0), (512, 0), (512, 1024), (0, 1024)]), SILVER.0, SILVER.1),
                      (poly([(512, 0), (1024, 0), (1024, 1024), (512, 1024)]), NAVY.0, NAVY.1)], rim: 20)
}))

// 3 — V Ribbon: the V as two raised strokes, red and blue, with a gold stop at the point.
icons.append(("V Ribbon", "The Velo V as two raised strokes (red, blue) meeting at a gold stop, on warm white", { c in
    tile(c, 0xFFFDF8, 0xE6DFD3)
    let l = CGMutablePath(); l.move(to: CGPoint(x: 300, y: 770)); l.addLine(to: CGPoint(x: 512, y: 300))
    let r = CGMutablePath(); r.move(to: CGPoint(x: 512, y: 300)); r.addLine(to: CGPoint(x: 724, y: 770))
    let w: CGFloat = 150
    let body = l.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)
        .union(r.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10))
    emboss(c, body, [(poly([(0, 0), (512, 0), (512, 1024), (0, 1024)]), RED.0, RED.1),
                     (poly([(512, 0), (1024, 0), (1024, 1024), (512, 1024)]), BLUE.0, BLUE.1)], shadow: 0.55)
    emboss(c, circle(512, 300, 78), [(circle(512, 300, 78), GOLD.0, GOLD.1)], rim: 16, shadow: 0.6)
}))

// 4 — Folded Map: three map panels with a raised red route and a destination dot.
icons.append(("Folded Map", "A folded map with a raised red route ending at a gold destination, on teal", { c in
    tile(c, 0x22B597, 0x0C6656)
    let xs: [CGFloat] = [218, 414, 610, 806], tops: [CGFloat] = [770, 820, 770, 820], h: CGFloat = 520
    var outline = xs.indices.map { (xs[$0], tops[$0]) }; outline += xs.indices.reversed().map { (xs[$0], tops[$0] - h) }
    let panels = (0..<3).map { i in poly([(xs[i], tops[i]), (xs[i + 1], tops[i + 1]), (xs[i + 1], tops[i + 1] - h), (xs[i], tops[i] - h)]) }
    emboss(c, poly(outline), panels.enumerated().map { i, p in (p, i % 2 == 0 ? 0xFFFFFF : 0xE4E8F0, i % 2 == 0 ? 0xE6EAF2 : 0xC3CAD8) }, rim: 14, shadow: 0.8)
    let route = CGMutablePath()
    route.move(to: CGPoint(x: 290, y: 380)); route.addCurve(to: CGPoint(x: 520, y: 560), control1: CGPoint(x: 380, y: 560), control2: CGPoint(x: 430, y: 400))
    route.addCurve(to: CGPoint(x: 720, y: 690), control1: CGPoint(x: 600, y: 700), control2: CGPoint(x: 650, y: 560))
    let rb = route.copy(strokingWithWidth: 58, lineCap: .round, lineJoin: .round, miterLimit: 10)
    emboss(c, rb, [(rb, RED.0, RED.1)], rim: 10, shadow: 0.35)
    emboss(c, circle(720, 690, 58), [(circle(720, 690, 58), GOLD.0, GOLD.1)], rim: 12, shadow: 0.45)
}))

// 5 — Road Ahead: a shield with a sunset sky, green fields and the road ahead with the red route.
icons.append(("Road Ahead", "A shield with a gold sky, green fields and the road ahead carrying the red route, on midnight", { c in
    tile(c, 0x2B3352, 0x0F1426)
    let sh = CGMutablePath()
    sh.move(to: CGPoint(x: 512, y: 190))
    sh.addCurve(to: CGPoint(x: 250, y: 560), control1: CGPoint(x: 330, y: 270), control2: CGPoint(x: 250, y: 400))
    sh.addLine(to: CGPoint(x: 250, y: 790)); sh.addQuadCurve(to: CGPoint(x: 512, y: 830), control: CGPoint(x: 380, y: 830))
    sh.addQuadCurve(to: CGPoint(x: 774, y: 790), control: CGPoint(x: 644, y: 830))
    sh.addLine(to: CGPoint(x: 774, y: 560))
    sh.addCurve(to: CGPoint(x: 512, y: 190), control1: CGPoint(x: 774, y: 400), control2: CGPoint(x: 694, y: 270))
    sh.closeSubpath()
    let horizon: CGFloat = 600
    let sky = poly([(0, horizon), (1024, horizon), (1024, 1024), (0, 1024)])
    let road = poly([(500, horizon), (524, horizon), (690, 0), (334, 0)])
    let fields = poly([(0, 0), (1024, 0), (1024, horizon), (0, horizon)]).subtracting(road)
    emboss(c, sh, [(sky, GOLD.0, GOLD.1), (fields, 0x5DD27A, 0x23934A), (road, 0x6A7080, 0x3A3F4C)], rim: 18)
    // the red route up the middle of the road
    c.saveGState(); c.addPath(sh); c.clip()
    let line = poly([(509, horizon), (515, horizon), (552, 0), (472, 0)])
    c.addPath(line); c.setFillColor(hex(RED.0)); c.fillPath()
    c.restoreGState()
    emboss(c, circle(512, horizon + 70, 44), [(circle(512, horizon + 70, 44), 0xFFFFFF, 0xF3E3C0)], rim: 0.01, shadow: 0)
}))

var rendered: [(String, String, CGImage)] = []
for (i, (name, caption, draw)) in icons.enumerated() {
    let c = newCtx(1024, 1024)
    draw(c)
    let img = c.makeImage()!
    save(img, "\(outDir)/0\(i + 1) \(name).png")
    rendered.append((name, caption, img))
}

// The chosen Arrow (owner, 11/9): full-bleed opaque app icon + transparent mark for marketing art.
if CommandLine.arguments.count > 2 {
    let arrow = icons[1].2
    fullBleed = true
    let a = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let k: CGFloat = 1024 / 880
    a.translateBy(x: 512, y: 512); a.scaleBy(x: k, y: k); a.translateBy(x: -512, y: -512)
    arrow(a); save(a.makeImage()!, CommandLine.arguments[2] + "/icon-1024.png")
    fullBleed = false; markOnly = true
    let m = newCtx(1024, 1024); arrow(m); save(m.makeImage()!, CommandLine.arguments[2] + "/arrow-mark.png")
    markOnly = false
    print("wrote app icon + mark")
}

// Overview: the five big, then each at home-screen size on a wallpaper.
let W = 3000, H = 1500
let o = newCtx(W, H)
NSGraphicsContext.current = NSGraphicsContext(cgContext: o, flipped: false)
o.setFillColor(hex(0x0B0C10)); o.fill(CGRect(x: 0, y: 0, width: W, height: H))
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    (s as NSString).draw(in: CGRect(x: x, y: y, width: w, height: size * 2.6),
                         withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: para])
}
text("Velo Maps — logo directions (raised, glossy, bold bands)", 0, CGFloat(H) - 150, CGFloat(W), size: 52, weight: .bold, color: .white)
for (i, (name, caption, img)) in rendered.enumerated() {
    let x = CGFloat(60 + i * 580)
    o.draw(img, in: CGRect(x: x, y: 640, width: 540, height: 540))
    text("\(i + 1)  \(name)", x, 560, 540, size: 40, weight: .bold, color: .white)
    text(caption, x + 20, 470, 500, size: 24, weight: .regular, color: NSColor(white: 0.75, alpha: 1))
}
// Home-screen size strip on a soft wallpaper.
let strip = CGRect(x: 60, y: 60, width: CGFloat(W) - 120, height: 360)
o.saveGState(); o.addPath(CGPath(roundedRect: strip, cornerWidth: 40, cornerHeight: 40, transform: nil)); o.clip()
let wg = CGGradient(colorsSpace: space, colors: [hex(0x8EC5FC), hex(0xE0C3FC)] as CFArray, locations: [0, 1])!
o.drawLinearGradient(wg, start: CGPoint(x: strip.minX, y: strip.minY), end: CGPoint(x: strip.maxX, y: strip.maxY), options: [])
o.restoreGState()
text("At home-screen size", 0, 425, CGFloat(W), size: 30, weight: .semibold, color: NSColor(white: 0.85, alpha: 1))
for (i, (name, _, img)) in rendered.enumerated() {
    let x = CGFloat(300 + i * 520)
    o.draw(img, in: CGRect(x: x - 10, y: 140, width: 200, height: 200))
    text("\(i + 1) \(name)", x - 60, 82, 300, size: 22, weight: .medium, color: NSColor(white: 0.1, alpha: 1))
}
NSGraphicsContext.current = nil
save(o.makeImage()!, "\(outDir)/00 Overview.png")
print("ok")
