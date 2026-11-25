// The Mac icon for Large Score Converter: the iPad icon in the macOS rounded square
// (824 of 1024 px, 185 px corners, a soft shadow below), at every size an
// AppIcon.appiconset for macOS needs.
// Run: swift scripts/make-mac-icon.swift LargeScore/Assets.xcassets/AppIcon.appiconset/icon-1024.png Converter/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let source = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: source) as CFURL, nil),
      let art = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("no source image") }

func render(_ px: Int) -> CGImage {
    let s = CGFloat(px), k = s / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let rect = CGRect(x: 100 * k, y: 100 * k + 10 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: CGColor(gray: 0, alpha: 0.3))
    ctx.addPath(shape); ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(art, in: rect)
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
