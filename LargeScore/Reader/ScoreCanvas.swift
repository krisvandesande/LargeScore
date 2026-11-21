import SwiftUI
import CoreText

/// Draws one engraved page in a single colour, fitted to the view. For a half-page
/// turn, `upper` is the next page, drawn above `split` (in page units) with this page
/// below it and a rule between.
struct ScoreCanvas: View {
    let scene: SVGScene
    var upper: SVGScene? = nil
    var split: CGFloat? = nil
    var ink: Color = .black
    /// Extra weight on note heads, clefs and other glyphs, in page units: an outline
    /// in the ink around every filled shape. Zero draws them as engraved.
    var glyphWeight: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let cgInk = ink.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                guard let upper, let split else {
                    Self.draw(scene, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight)
                    return
                }
                let box = scene.viewBox
                let scale = min(size.width / box.width, size.height / box.height)
                let y = (split - box.minY) * scale
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: -size.height, width: size.width * 3, height: size.height + y))
                Self.draw(upper, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight)
                cg.restoreGState()
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: y, width: size.width * 3, height: size.height * 2))
                Self.draw(scene, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight)
                cg.restoreGState()
                cg.setFillColor(cgInk)
                cg.fill(CGRect(x: 0, y: y - 2, width: size.width, height: 4))
            }
        }
        .accessibilityHidden(true)
    }

    /// Draws the page fitted into `size`, in one colour.
    static func draw(_ scene: SVGScene, in cg: CGContext, size: CGSize, ink: CGColor, text: Bool = true, glyphWeight: CGFloat = 0) {
        let box = scene.viewBox
        let scale = min(size.width / box.width, size.height / box.height)
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -box.minX, y: -box.minY)
        cg.setFillColor(ink)
        cg.setStrokeColor(ink)
        for item in scene.items {
            switch item {
            case .fill(let path):
                cg.addPath(path)
                if glyphWeight > 0 {
                    cg.setLineWidth(glyphWeight)
                    cg.setLineJoin(.round)
                    cg.drawPath(using: .fillStroke)
                } else {
                    cg.fillPath()
                }
            case .stroke(let path, let width, let round):
                cg.setLineWidth(width)
                cg.setLineCap(round ? .round : .butt)
                cg.setLineJoin(round ? .round : .miter)
                cg.addPath(path)
                cg.strokePath()
            case .text(let run):
                if text { draw(run, in: cg, color: ink) }
            }
        }
        cg.restoreGState()
    }

    private static func draw(_ run: SVGScene.TextRun, in cg: CGContext, color: CGColor) {
        let font = FontCache.font(size: run.size, bold: run.bold, italic: run.italic)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: run.string, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let dx: CGFloat = switch run.anchor {
        case .start: 0
        case .middle: -width / 2
        case .end: -width
        }
        cg.saveGState()
        cg.translateBy(x: run.position.x + dx, y: run.position.y)
        cg.scaleBy(x: 1, y: -1)
        cg.textPosition = .zero
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

/// Fonts for the music's words, made once per size and style rather than on every draw.
nonisolated enum FontCache {
    // NSCache is thread-safe; CTFont is immutable.
    nonisolated(unsafe) private static let cache = NSCache<NSString, CTFont>()

    static func font(size: CGFloat, bold: Bool, italic: Bool) -> CTFont {
        let key = "\(size)-\(bold)-\(italic)" as NSString
        if let font = cache.object(forKey: key) { return font }
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = CTFontCreateWithName("Times New Roman" as CFString, size, nil)
        let font = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
        cache.setObject(font, forKey: key)
        return font
    }
}
