// Draws the Velo Maps app icon (1024x1024, no alpha) into the asset catalog.
//   swift scripts/make_icon.swift
import AppKit

let size = 1024
let out = "VeloMaps/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
import ImageIO
import UniformTypeIdentifiers
// App Store icons must have no alpha channel: draw into an RGB context that skips alpha.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let S = CGFloat(size)

// Brand red gradient, top lighter.
let grad = NSGradient(starting: NSColor(red: 0.90, green: 0.12, blue: 0.18, alpha: 1),
                      ending: NSColor(red: 0.62, green: 0.04, blue: 0.09, alpha: 1))!
grad.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: -90)

// Faint street grid, tilted like the 3D map.
ctx.saveGState()
ctx.translateBy(x: S / 2, y: S / 2); ctx.rotate(by: .pi / 9); ctx.translateBy(x: -S / 2, y: -S / 2)
NSColor(white: 1, alpha: 0.07).setStroke()
for i in stride(from: -400, through: 1400, by: 150) {
    let v = NSBezierPath(); v.move(to: NSPoint(x: CGFloat(i), y: -300)); v.line(to: NSPoint(x: CGFloat(i), y: 1300)); v.lineWidth = 14; v.stroke()
    let h = NSBezierPath(); h.move(to: NSPoint(x: -300, y: CGFloat(i))); h.line(to: NSPoint(x: 1300, y: CGFloat(i))); h.lineWidth = 14; h.stroke()
}
ctx.restoreGState()

// The V: a route line with round caps, soft shadow.
let v = NSBezierPath()
v.move(to: NSPoint(x: 282, y: 760))
v.line(to: NSPoint(x: 512, y: 270))
v.line(to: NSPoint(x: 742, y: 760))
v.lineWidth = 128; v.lineCapStyle = .round; v.lineJoinStyle = .round
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(white: 0, alpha: 0.28).cgColor)
NSColor.white.setStroke(); v.stroke()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Stop marker at the point of the V: red dot in a white ring.
let ring = NSBezierPath(ovalIn: NSRect(x: 512 - 96, y: 270 - 96, width: 192, height: 192))
NSColor.white.setFill(); ring.fill()
let dot = NSBezierPath(ovalIn: NSRect(x: 512 - 54, y: 270 - 54, width: 108, height: 108))
NSColor(red: 0.84, green: 0.07, blue: 0.13, alpha: 1).setFill(); dot.fill()

NSGraphicsContext.current = nil
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest), "could not write \(out)")
print("wrote \(out)")
