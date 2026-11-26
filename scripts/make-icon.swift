// Draws the app icon: the low-vision symbol (Mark Caron, public domain, Noun Project 1702963),
// redrawn from its measured geometry, as the head of an eighth note: a stem and flag on its right tip.
// Run: swift scripts/make-icon.swift <light|dark|tinted> <out.png> [plain]
// "plain" draws the symbol alone at its original placement, to compare with the 512 px original.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let variant = args[1], outPath = args[2]
let stemW = Symbol.stroke // the stem as thick as the slash and bars
let plain = args.count > 3 && args[3] == "plain"

// Symbol units: the original 512 px drawing, with the eye's centre at the origin.
enum Symbol {
    static let halfWidth: CGFloat = 211.9, halfHeight: CGFloat = 128
    // Upper-right quarter of the outline as one cubic (fits the original within 0.23 px rms).
    static let tipHandle = CGPoint(x: 157.6, y: -68.0), topHandle = CGPoint(x: 78, y: -128)
    static let iris: CGFloat = 99.5, pupil: CGFloat = 52.5
    static let slashFrom = CGPoint(x: -158.5, y: -158.5), slashTo = CGPoint(x: 162.25, y: 162.25)
    static let stroke: CGFloat = 25.7           // slash thickness; bars are the same
    static let slashLeftEdge: CGFloat = -18.2    // x - y on the slash's lower-left side
    static let barStart: CGFloat = -207.5, barPeriod: CGFloat = 73.6, barWidth: CGFloat = 36.1 // in x + y
}

// Drawn in a 1024 canvas; ICON_PIXELS draws it straight at another size, sharp at
// every one (the Mac icon's 16 to 1024 px), rather than shrinking the 1024 picture.
let size: CGFloat = 1024
let pixels = CGFloat(Double(ProcessInfo.processInfo.environment["ICON_PIXELS"] ?? "") ?? 1024)
let ctx = CGContext(data: nil, width: Int(pixels), height: Int(pixels), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    // The light icon is opaque with no alpha channel, as the App Store requires.
                    bitmapInfo: (variant == "light" ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
ctx.translateBy(x: 0, y: pixels); ctx.scaleBy(x: 1, y: -1) // top-left origin, y down
ctx.scaleBy(x: pixels / size, y: pixels / size)

let accent = CGColor(srgbRed: 0, green: 0x40 / 255, blue: 0xA0 / 255, alpha: 1)
let background: CGColor?, art: CGColor
switch variant {
case "dark":   background = nil; art = CGColor(srgbRed: 0x7F / 255, green: 0xB0 / 255, blue: 1, alpha: 1)
case "tinted": background = nil; art = CGColor(gray: 1, alpha: 1)
default:       background = accent; art = CGColor(gray: 1, alpha: 1)
}
if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }

// Place the symbol: scale and centre the whole drawing (eye, slash ends, stem and flag).
let stemTop: CGFloat = plain ? -128 : -330
let flagScale: CGFloat = 0.7
let artTop = stemTop, artBottom = Symbol.slashTo.y + Symbol.stroke / 2 / 2.squareRoot()
if plain { // the original's own placement, at twice its size
    ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: 2, y: 2)
} else {
    let artLeft = -Symbol.halfWidth, artRight = Symbol.halfWidth + 150 * flagScale
    let scale = 800 / max(artRight - artLeft, artBottom - artTop)
    ctx.translateBy(x: size / 2 - 2 - (artLeft + artRight) / 2 * scale, y: size / 2 - (artTop + artBottom) / 2 * scale)
    ctx.scaleBy(x: scale, y: scale)
}

func almond() -> CGPath {
    let p = CGMutablePath(), w = Symbol.halfWidth, h = Symbol.halfHeight
    let t = Symbol.tipHandle, u = Symbol.topHandle
    p.move(to: CGPoint(x: w, y: 0))
    p.addCurve(to: CGPoint(x: 0, y: -h), control1: t, control2: u)
    p.addCurve(to: CGPoint(x: -w, y: 0), control1: CGPoint(x: -u.x, y: u.y), control2: CGPoint(x: -t.x, y: t.y))
    p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -t.x, y: -t.y), control2: CGPoint(x: -u.x, y: -u.y))
    p.addCurve(to: CGPoint(x: w, y: 0), control1: CGPoint(x: u.x, y: -u.y), control2: CGPoint(x: t.x, y: -t.y))
    p.closeSubpath()
    return p
}

/// Paints the background colour, or clears to transparent where there is none.
func knockOut(_ draw: () -> Void) {
    ctx.saveGState()
    if let background { ctx.setFillColor(background); ctx.setStrokeColor(background) } else { ctx.setBlendMode(.clear) }
    draw()
    ctx.restoreGState()
}

func circle(_ r: CGFloat) -> CGRect { CGRect(x: -r, y: -r, width: r * 2, height: r * 2) }

/// Eye with its iris ring cut out (the background shows through) and the pupil.
/// Drawn by clearing, so it works on a transparent background too.
/// The iris is cut out unclipped, so the bar edges leave no seams inside it.
func drawEye() {
    ctx.saveGState(); eyeClip(); ctx.setFillColor(art); ctx.addPath(almond()); ctx.fillPath(); ctx.restoreGState()
    knockOut { ctx.fillEllipse(in: circle(Symbol.iris)) }
    ctx.saveGState(); eyeClip(); ctx.setFillColor(art); ctx.fillEllipse(in: circle(Symbol.pupil)); ctx.restoreGState()
}

/// Everything right of the slash, plus the bars on its left.
func eyeClip() {
    let p = CGMutablePath(), far: CGFloat = 2000, k = Symbol.slashLeftEdge
    p.addLines(between: [CGPoint(x: k - far, y: -far), CGPoint(x: far, y: -far),
                         CGPoint(x: far, y: far), CGPoint(x: k + far, y: far)])
    p.closeSubpath()
    var s = Symbol.barStart
    while s < 2 * Symbol.halfWidth {
        // band s <= x + y <= s + width, only on the slash's left (x - y < k)
        let s2 = s + Symbol.barWidth
        p.addLines(between: [CGPoint(x: (s + k) / 2, y: (s - k) / 2), CGPoint(x: (s2 + k) / 2, y: (s2 - k) / 2),
                             CGPoint(x: (s2 + k) / 2 - far, y: (s2 - k) / 2 + far),
                             CGPoint(x: (s + k) / 2 - far, y: (s - k) / 2 + far)])
        p.closeSubpath()
        s += Symbol.barPeriod
    }
    ctx.addPath(p); ctx.clip()
}

func slash() -> CGPath {
    let a = Symbol.slashFrom, b = Symbol.slashTo, n = Symbol.stroke / 2 / 2.squareRoot()
    let p = CGMutablePath()
    p.addLines(between: [CGPoint(x: a.x + n, y: a.y - n), CGPoint(x: b.x + n, y: b.y - n),
                         CGPoint(x: b.x - n, y: b.y + n), CGPoint(x: a.x - n, y: a.y + n)])
    p.closeSubpath()
    return p
}

/// Stem on the pupil's right side and an eighth-note flag at its top.
func stemAndFlag(hull: Bool) -> CGPath {
    let x = Symbol.halfWidth, x0 = x - stemW, top = stemTop, bottom: CGFloat = 0, s = flagScale
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x0, y: bottom))
    p.addLine(to: CGPoint(x: x0, y: top))
    p.addLine(to: CGPoint(x: x, y: top))
    p.addCurve(to: CGPoint(x: x + 150 * s, y: top + 230 * s),
               control1: CGPoint(x: x + 10 * s, y: top + 90 * s), control2: CGPoint(x: x + 150 * s, y: top + 120 * s))
    p.addCurve(to: CGPoint(x: x + 64 * s, y: top + 450 * s),
               control1: CGPoint(x: x + 152 * s, y: top + 320 * s), control2: CGPoint(x: x + 112 * s, y: top + 400 * s))
    if hull {
        p.addLine(to: CGPoint(x: x, y: top + 520 * s))
    } else {
        p.addCurve(to: CGPoint(x: x + 104 * s, y: top + 290 * s),
                   control1: CGPoint(x: x + 98 * s, y: top + 400 * s), control2: CGPoint(x: x + 112 * s, y: top + 340 * s))
        p.addCurve(to: CGPoint(x: x, y: top + 205 * s),
                   control1: CGPoint(x: x + 96 * s, y: top + 235 * s), control2: CGPoint(x: x + 40 * s, y: top + 210 * s))
    }
    p.addLine(to: CGPoint(x: x, y: bottom))
    p.closeSubpath()
    return p
}

drawEye()
ctx.setFillColor(art); ctx.addPath(slash()); ctx.fillPath()
if !plain { ctx.setFillColor(art); ctx.addPath(stemAndFlag(hull: false)); ctx.fillPath() }

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote", url.path)
