// Draws the app icon: five white staff lines on the accent blue, one oversized
// quarter note across them. Run: swift scripts/make-icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1) // top-left origin

ctx.setFillColor(CGColor(srgbRed: 0, green: 0x40 / 255, blue: 0xA0 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
ctx.setFillColor(white)
let space: CGFloat = 104, line: CGFloat = 22
let top = (CGFloat(size) - space * 4) / 2 + 40
for i in 0..<5 {
    ctx.fill(CGRect(x: 0, y: top + CGFloat(i) * space - line / 2, width: CGFloat(size), height: line))
}
// Note head on the second space from the bottom, tilted like an engraved head.
let headCenter = CGPoint(x: 452, y: top + space * 2.5)
ctx.saveGState()
ctx.translateBy(x: headCenter.x, y: headCenter.y)
ctx.rotate(by: -20 * .pi / 180)
ctx.fillEllipse(in: CGRect(x: -140, y: -98, width: 280, height: 196))
ctx.restoreGState()
// Stem up from the head's right edge: its outer side on the ellipse's rightmost
// point (135.8 from the centre at -20 degrees), ending inside the head.
let stemRight = headCenter.x + 135
let stemTop = top - space * 1.6
ctx.fill(CGRect(x: stemRight - 28, y: stemTop, width: 28, height: headCenter.y - 30 - stemTop))

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote", url.path)
