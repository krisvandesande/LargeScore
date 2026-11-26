// The Mac icon for Large Score Converter: the iPad icon in the macOS rounded square
// (824 of 1024 px, 185 px corners, a soft shadow below), at every size an
// AppIcon.appiconset for macOS needs. The artwork is drawn by make-icon.swift at the
// size each icon shows it (ICON_PIXELS), so small sizes stay sharp.
// Run: swift scripts/make-mac-icon.swift <folder of icon-<px>.png artwork> Converter/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let artDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]

/// The artwork drawn at exactly `px` pixels.
func artwork(_ px: Int) -> CGImage {
    let url = URL(fileURLWithPath: "\(artDir)/icon-\(px).png")
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("no artwork at \(px) px") }
    return image
}

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px), k = s / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    // Whole pixels, so the drawn artwork lands one to one.
    let side = (824 * k).rounded(), inset = ((s - side) / 2).rounded(.down)
    let rect = CGRect(x: inset, y: inset + (10 * k).rounded(), width: side, height: side)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(artwork(Int(side)), in: rect)
    return ctx.makeImage()!
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon-\(points)@\(scale)x.png"
        let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(points * scale), nil)
        CGImageDestinationFinalize(dest)
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
