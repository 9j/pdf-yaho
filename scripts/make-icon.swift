// Draws the Pagecraft app icon. Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Tile with shadow, on Apple's 824pt grid inside 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x3B2FC9)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x6D5BFF), rgb(0x4B33D9), rgb(0x2A1D9E)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 860, y: 100), options: [])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 860), startRadius: 0, endCenter: CGPoint(x: 300, y: 860), endRadius: 520, options: [])
ctx.restoreGState()

// Page, tilted, with folded corner.
ctx.saveGState()
ctx.translateBy(x: 512, y: 500)
ctx.rotate(by: -7 * .pi / 180)
let w: CGFloat = 430, h: CGFloat = 560, fold: CGFloat = 104
let page = CGMutablePath()
page.move(to: CGPoint(x: -w / 2 + 24, y: -h / 2))
page.addLine(to: CGPoint(x: w / 2 - 24, y: -h / 2))
page.addQuadCurve(to: CGPoint(x: w / 2, y: -h / 2 + 24), control: CGPoint(x: w / 2, y: -h / 2))
page.addLine(to: CGPoint(x: w / 2, y: h / 2 - fold))
page.addLine(to: CGPoint(x: w / 2 - fold, y: h / 2))
page.addLine(to: CGPoint(x: -w / 2 + 24, y: h / 2))
page.addQuadCurve(to: CGPoint(x: -w / 2, y: h / 2 - 24), control: CGPoint(x: -w / 2, y: h / 2))
page.addLine(to: CGPoint(x: -w / 2, y: -h / 2 + 24))
page.addQuadCurve(to: CGPoint(x: -w / 2 + 24, y: -h / 2), control: CGPoint(x: -w / 2, y: -h / 2))
page.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0x0B0640, 0.45))
ctx.addPath(page); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
// Fold flap.
let flap = CGMutablePath()
flap.move(to: CGPoint(x: w / 2, y: h / 2 - fold))
flap.addLine(to: CGPoint(x: w / 2 - fold + 14, y: h / 2 - fold + 6))
flap.addQuadCurve(to: CGPoint(x: w / 2 - fold, y: h / 2), control: CGPoint(x: w / 2 - fold + 4, y: h / 2 - fold + 2))
flap.closeSubpath()
ctx.addPath(flap); ctx.setFillColor(rgb(0xD9D6F2)); ctx.fillPath()

// Text lines.
func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ color: CGColor, height: CGFloat = 22) {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
    ctx.setFillColor(color); ctx.fillPath()
}
let left = -w / 2 + 52
bar(left, 170, 210, rgb(0x2A2550), height: 30)
let grey = rgb(0xC9C7D9)
let lines: [(CGFloat, CGFloat)] = [(100, 320), (52, 300), (4, 326), (-44, 260), (-92, 310)]
for (y, width) in lines { bar(left, y, width, grey) }
// Highlighter stroke over two lines.
ctx.saveGState()
ctx.setBlendMode(.multiply)
for (y, width) in [(CGFloat(52), CGFloat(300)), (4, 250)] {
    ctx.addPath(CGPath(roundedRect: CGRect(x: left - 10, y: y - 12, width: width + 20, height: 46), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.setFillColor(rgb(0xFFD21F, 0.85)); ctx.fillPath()
}
ctx.restoreGState()

// Signature.
let sig = CGMutablePath()
sig.move(to: CGPoint(x: left + 4, y: -190))
sig.addCurve(to: CGPoint(x: left + 70, y: -150), control1: CGPoint(x: left + 20, y: -120), control2: CGPoint(x: left + 60, y: -110))
sig.addCurve(to: CGPoint(x: left + 120, y: -205), control1: CGPoint(x: left + 80, y: -190), control2: CGPoint(x: left + 96, y: -230))
sig.addCurve(to: CGPoint(x: left + 175, y: -160), control1: CGPoint(x: left + 140, y: -185), control2: CGPoint(x: left + 150, y: -140))
sig.addCurve(to: CGPoint(x: left + 250, y: -195), control1: CGPoint(x: left + 200, y: -180), control2: CGPoint(x: left + 215, y: -215))
sig.addCurve(to: CGPoint(x: left + 320, y: -170), control1: CGPoint(x: left + 280, y: -178), control2: CGPoint(x: left + 300, y: -165))
ctx.addPath(sig)
ctx.setStrokeColor(rgb(0x3B2FC9)); ctx.setLineWidth(11); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
bar(left, -232, 330, rgb(0xE4E2F0), height: 6)
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
