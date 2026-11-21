import SwiftUI
import UIKit
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
    /// Notes on this page and, for a half turn, on the next one.
    var marks: [Mark] = []
    var geometry: BarGeometry? = nil
    var upperMarks: [Mark] = []
    var upperGeometry: BarGeometry? = nil
    var notesInk: Color = Palette.notes

    var body: some View {
        Canvas { context, size in
            let cgInk = ink.resolve(in: context.environment).cgColor
            let notesColour = notesInk.resolve(in: context.environment).cgColor
            context.withCGContext { cg in
                guard let upper, let split else {
                    Self.draw(scene, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight,
                              marks: geometry.map { (marks, $0, notesColour) })
                    return
                }
                let box = scene.viewBox
                let scale = min(size.width / box.width, size.height / box.height)
                let y = (split - box.minY) * scale
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: -size.height, width: size.width * 3, height: size.height + y))
                Self.draw(upper, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight,
                          marks: upperGeometry.map { (upperMarks, $0, notesColour) })
                cg.restoreGState()
                cg.saveGState()
                cg.clip(to: CGRect(x: -size.width, y: y, width: size.width * 3, height: size.height * 2))
                Self.draw(scene, in: cg, size: size, ink: cgInk, glyphWeight: glyphWeight,
                          marks: geometry.map { (marks, $0, notesColour) })
                cg.restoreGState()
                cg.setFillColor(cgInk)
                cg.fill(CGRect(x: 0, y: y - 2, width: size.width, height: 4))
            }
        }
        .accessibilityHidden(true)
    }

    /// Draws the page fitted into `size`, in one colour.
    /// The scale the page is drawn at in a view of `size`: page units to points.
    static func scale(of scene: SVGScene, in size: CGSize) -> CGFloat {
        min(size.width / scene.viewBox.width, size.height / scene.viewBox.height)
    }

    static func draw(_ scene: SVGScene, in cg: CGContext, size: CGSize, ink: CGColor, text: Bool = true, glyphWeight: CGFloat = 0,
                     marks: (marks: [Mark], geometry: BarGeometry, colour: CGColor)? = nil) {
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
            case .text(let line, let origin):
                guard text else { continue }
                cg.saveGState()
                cg.translateBy(x: origin.x, y: origin.y)
                cg.scaleBy(x: 1, y: -1)
                cg.textPosition = .zero
                CTLineDraw(line, cg)
                cg.restoreGState()
            }
        }
        if let marks {
            drawMarks(marks.marks, geometry: marks.geometry, in: cg, colour: marks.colour)
        }
        cg.restoreGState()
    }
}

extension ScoreCanvas {
    /// Notes over the music, in page units (the page is drawn at one point a unit).
    static func drawMarks(_ marks: [Mark], geometry: BarGeometry, in cg: CGContext, colour: CGColor) {
        let space = geometry.space
        cg.saveGState()
        cg.setStrokeColor(colour)
        cg.setFillColor(colour)
        for mark in marks {
            guard let box = geometry.box(of: mark.bar) else { continue }
            switch mark.kind {
            case .ink:
                guard let first = mark.points.first else { continue }
                let path = CGMutablePath()
                path.move(to: geometry.place(first, in: box))
                for point in mark.points.dropFirst() { path.addLine(to: geometry.place(point, in: box)) }
                if mark.points.count == 1 { path.addLine(to: geometry.place(first, in: box)) }
                cg.addPath(path)
                cg.setLineWidth(space * 0.22)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.strokePath()
            case .circle:
                cg.setLineWidth(space * 0.25)
                cg.strokeEllipse(in: box.insetBy(dx: -space * 1.2, dy: -space * 2.2))
            case .highlight:
                cg.saveGState()
                // A pale fill keeps the music readable on it; the outline in the notes'
                // colour gives the mark itself enough contrast (6.5:1 light, 9.2:1 dark).
                let area = box.insetBy(dx: -space * 0.4, dy: -space * 1.2)
                cg.setFillColor(UIColor.systemYellow.withAlphaComponent(0.35).cgColor)
                cg.fill(area)
                cg.restoreGState()
                cg.setLineWidth(space * 0.15)
                cg.stroke(area)
            case .watch:
                let at = geometry.place(mark.position, in: box)
                let side = space * 3
                if let image = UIImage(systemName: "eyeglasses")?.withTintColor(UIColor(cgColor: colour), renderingMode: .alwaysOriginal) {
                    UIGraphicsPushContext(cg)
                    image.draw(in: CGRect(x: at.x - side / 2, y: at.y - side / 2, width: side, height: side))
                    UIGraphicsPopContext()
                }
            default:
                guard let code = mark.kind.glyph, let glyph = GlyphLibrary.shared.glyph(code, font: "Leipzig") else { continue }
                let at = geometry.place(mark.position, in: box)
                // One em of the music font is one staff height; fingerings a little smaller.
                let em = space * 4 * (code >= 0xED10 ? 0.8 : 1)
                var t = CGAffineTransform(translationX: at.x - glyph.advance * em / 2000, y: at.y).scaledBy(x: em / 1000, y: em / 1000)
                if let placed = glyph.path.copy(using: &t) {
                    cg.addPath(placed)
                    cg.fillPath()
                }
            }
        }
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
