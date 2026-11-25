import Foundation
import CoreGraphics
import CoreText
import VerovioToolkit

/// One stretch of an SVG `text` with a single style: what Verovio writes as a leaf
/// `tspan`. Chord symbols and tempo marks mix sizes and fonts inside one `text`.
nonisolated struct TextSpan {
    var string: String
    /// Font size in page units.
    var size: CGFloat
    var bold: Bool
    var italic: Bool
    /// A SMuFL music font (Leipzig, Bravura…) whose characters are drawn from
    /// Verovio's own glyph outlines; nil for words, drawn in Times.
    var musicFont: String?
    /// Vertical shift from the line's baseline, in page units (SVG `dy`).
    var shift: CGFloat = 0
}

/// Lays spans out left to right from an anchor point, as SVG does, into ready-to-draw
/// pieces: lines of words and outlines of music characters.
nonisolated enum TextLayout {
    enum Anchor { case start, middle, end }

    enum Piece {
        case words(CTLine, origin: CGPoint)
        case glyph(CGPath)
    }

    static let musicFonts: Set<String> = ["Leipzig", "Bravura", "Leland", "Petaluma", "Gootville"]

    static func layOut(_ spans: [TextSpan], at origin: CGPoint, anchor: Anchor) -> (pieces: [Piece], bounds: CGRect) {
        // Measure first, so a centred or right-aligned run can be placed.
        struct Measured { var span: TextSpan; var width: CGFloat; var line: CTLine?; var glyphs: [(CGPath, CGFloat)] }
        var measured: [Measured] = []
        for span in spans where !span.string.isEmpty && span.size > 0 {
            if let family = span.musicFont {
                var glyphs: [(CGPath, CGFloat)] = []
                var width: CGFloat = 0
                for scalar in span.string.unicodeScalars {
                    guard let glyph = GlyphLibrary.shared.glyph(scalar.value, font: family) else { continue }
                    let advance = glyph.advance * span.size / 1000
                    glyphs.append((glyph.path, width))
                    width += advance
                }
                measured.append(Measured(span: span, width: width, line: nil, glyphs: glyphs))
            } else {
                let font = FontCache.font(size: span.size, bold: span.bold, italic: span.italic)
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                ]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: span.string, attributes: attributes))
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                measured.append(Measured(span: span, width: width, line: line, glyphs: []))
            }
        }
        let total = measured.reduce(0) { $0 + $1.width }
        var x = origin.x - (anchor == .middle ? total / 2 : anchor == .end ? total : 0)
        var pieces: [Piece] = []
        var bounds = CGRect.null
        for item in measured {
            let baseline = origin.y + item.span.shift
            if let line = item.line {
                pieces.append(.words(line, origin: CGPoint(x: x, y: baseline)))
                bounds = bounds.union(CGRect(x: x, y: baseline - item.span.size * 0.75, width: item.width, height: item.span.size))
            } else {
                let scale = item.span.size / 1000
                for (path, offset) in item.glyphs {
                    // Glyph outlines are drawn y-up in font units; the path data flips them.
                    var t = CGAffineTransform(translationX: x + offset, y: baseline).scaledBy(x: scale, y: scale)
                    if let placed = path.copy(using: &t) {
                        pieces.append(.glyph(placed))
                        bounds = bounds.union(placed.boundingBoxOfPath)
                    }
                }
            }
            x += item.width
        }
        return (pieces, bounds)
    }
}

/// Outlines and widths of SMuFL characters, read from Verovio's data folder once each.
nonisolated final class GlyphLibrary: @unchecked Sendable {
    static let shared = GlyphLibrary()

    struct Glyph {
        var path: CGPath
        var advance: CGFloat
    }

    private let lock = NSLock()
    private var glyphs: [String: Glyph?] = [:]
    private var advances: [String: [UInt32: CGFloat]] = [:]
    private let folder = VerovioResources.bundle.resourceURL!.appendingPathComponent("data")

    func glyph(_ code: UInt32, font: String) -> Glyph? {
        let hex = String(format: "%04X", code)
        let key = font + hex
        lock.lock(); defer { lock.unlock() }
        if let known = glyphs[key] { return known }
        let widths = advances[font] ?? loadAdvances(font)
        advances[font] = widths
        var glyph: Glyph?
        let url = folder.appendingPathComponent(font).appendingPathComponent(hex + ".xml")
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let d = Self.attribute("d", in: text) {
            var flip = CGAffineTransform(scaleX: 1, y: -1)
            if let path = SVGPathParser.path(d).copy(using: &flip) {
                glyph = Glyph(path: path, advance: widths[code] ?? path.boundingBoxOfPath.maxX)
            }
        }
        glyphs[key] = glyph
        return glyph
    }

    private func loadAdvances(_ font: String) -> [UInt32: CGFloat] {
        guard let text = try? String(contentsOf: folder.appendingPathComponent(font + ".xml"), encoding: .utf8) else { return [:] }
        var result: [UInt32: CGFloat] = [:]
        let pattern = try! NSRegularExpression(pattern: #"<g c="([0-9A-F]+)"[^>]*?h-a-x="([0-9.]+)""#)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let c = Range(match.range(at: 1), in: text), let w = Range(match.range(at: 2), in: text),
                  let code = UInt32(text[c], radix: 16), let width = Double(text[w]) else { continue }
            result[code] = CGFloat(width)
        }
        return result
    }

    private static func attribute(_ name: String, in text: String) -> String? {
        guard let start = text.range(of: " \(name)=\"") else { return nil }
        guard let end = text[start.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(text[start.upperBound..<end])
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
