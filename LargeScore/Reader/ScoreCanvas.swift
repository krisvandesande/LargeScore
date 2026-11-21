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

    var body: some View {
        Canvas { context, size in
            let cgInk = ink.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                guard let upper, let split else {
                    Self.draw(scene, in: cg, size: size, ink: cgInk)
                    return
                }
                let box = scene.viewBox
                let scale = min(size.width / box.width, size.height / box.height)
                let y = (split - box.minY) * scale
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: -size.height, width: size.width * 3, height: size.height + y))
                Self.draw(upper, in: cg, size: size, ink: cgInk)
                cg.restoreGState()
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: y, width: size.width * 3, height: size.height * 2))
                Self.draw(scene, in: cg, size: size, ink: cgInk)
                cg.restoreGState()
                cg.setFillColor(cgInk)
                cg.fill(CGRect(x: 0, y: y - 2, width: size.width, height: 4))
            }
        }
        .accessibilityHidden(true)
    }

    /// Draws the page fitted into `size`, in one colour.
    static func draw(_ scene: SVGScene, in cg: CGContext, size: CGSize, ink: CGColor, text: Bool = true) {
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
                cg.fillPath()
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
        var traits: CTFontSymbolicTraits = []
        if run.bold { traits.insert(.traitBold) }
        if run.italic { traits.insert(.traitItalic) }
        let base = CTFontCreateWithName("Times New Roman" as CFString, run.size, nil)
        let font = CTFontCreateCopyWithSymbolicTraits(base, run.size, nil, traits, traits) ?? base
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
