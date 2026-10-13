#!/usr/bin/swift
// Minimal installer artwork: title, website, and a single installation arrow.
import AppKit
let W: CGFloat = 640, H: CGFloat = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * 2), pixelsHigh: Int(H * 2),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func ink(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}
ctx.setFillColor(ink(0.93, 0.97, 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let text = NSAttributedString(string: value, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ])
    let size = text.size()
    text.draw(at: CGPoint(x: (W - size.width) / 2, y: H - top - size.height))
}
text("UP Sysdash", top: 42, size: 28, weight: .semibold, color: ink(0.08, 0.17, 0.28))
text("unboundplanet.com", top: 351, size: 12, weight: .medium, color: ink(0.14, 0.42, 0.69))
ctx.setStrokeColor(ink(0.17, 0.57, 0.91).cgColor)
ctx.setLineWidth(2.5)
ctx.setLineCap(.round)
let y = H - 198
ctx.move(to: CGPoint(x: 272, y: y)); ctx.addLine(to: CGPoint(x: 368, y: y)); ctx.strokePath()
ctx.move(to: CGPoint(x: 360, y: y + 6)); ctx.addLine(to: CGPoint(x: 368, y: y))
ctx.addLine(to: CGPoint(x: 360, y: y - 6)); ctx.strokePath()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let data = rep.representation(using: .png, properties: [:])!
guard data.count <= 1_000_000 else { fatalError("Installer background exceeds 1 MB") }
try data.write(to: output)
print("Minimal PNG background: \(data.count) bytes")
