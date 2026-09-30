// Renders the foreground layers of AppIcon.icon (one donut segment per asset type:
// crypto / cash / NFTs). The background and glass effects live in icon.json.
// Usage: swift Support/make-icon-layers.swift
import AppKit

let assets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Sources/Folio/Resources/AppIcon.icon/Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let size = 1024
let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 300
let width: CGFloat = 150
let gap = width / radius + 0.14  // room for the round caps plus a visible gap

let segments: [(name: String, share: CGFloat, color: NSColor)] = [
    ("crypto", 0.50, NSColor(srgbRed: 1.00, green: 0.62, blue: 0.10, alpha: 1)),
    ("cash", 0.28, NSColor(srgbRed: 0.19, green: 0.78, blue: 0.80, alpha: 1)),
    ("nfts", 0.22, NSColor(srgbRed: 1.00, green: 0.33, blue: 0.55, alpha: 1)),
]

var angle = CGFloat.pi / 2  // 12 o'clock, going clockwise
for segment in segments {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let sweep = segment.share * 2 * .pi
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(segment.color.cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: angle - gap / 2,
               endAngle: angle - sweep + gap / 2, clockwise: true)
    ctx.strokePath()
    NSGraphicsContext.current = nil
    try rep.representation(using: .png, properties: [:])!.write(to: assets.appending(path: "\(segment.name).png"))
    angle -= sweep
}
print("Wrote layers to \(assets.path)")
