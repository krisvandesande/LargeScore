import Foundation
import CoreGraphics

/// A Verovio page read once into paths and text, ready to draw at any size and colour.
/// Covers what Verovio writes: nested `svg` with viewBox, `g` and `use` with transforms,
/// `path`, `rect`, `ellipse`, `polygon`, `polyline`, and `text` with `tspan`.
nonisolated struct SVGScene: @unchecked Sendable {
    enum Item {
        case fill(CGPath)
        case stroke(CGPath, width: CGFloat, round: Bool)
        case text(TextRun)
    }

    struct TextRun {
        var string: String
        var position: CGPoint
        var size: CGFloat
        var bold: Bool
        var italic: Bool
        var anchor: Anchor
        enum Anchor { case start, middle, end }
    }

    var viewBox: CGRect
    var items: [Item]

    init?(svg: String) {
        let builder = SceneBuilder()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = builder
        guard parser.parse(), let box = builder.viewBox else { return nil }
        viewBox = box
        items = builder.items
    }
}

// MARK: - Building

nonisolated private final class SceneBuilder: NSObject, XMLParserDelegate {
    var viewBox: CGRect?
    var items: [SVGScene.Item] = []

    private struct Frame {
        var transform: CGAffineTransform
        var classes: Set<String>
        var bold: Bool
        var defID: String?
    }

    private var stack: [Frame] = []
    private var defs: [String: CGMutablePath] = [:]
    private var inDefs = 0
    private var currentDef: String?

    // Text being collected.
    private var textOrigin: CGPoint?
    private var textAnchor: SVGScene.TextRun.Anchor = .start
    private var textSize: CGFloat = 0
    private var textBold = false
    private var textItalic = false
    private var textBuffer = ""
    private var tspanSizes: [CGFloat] = []

    private var ctm: CGAffineTransform { stack.last?.transform ?? .identity }
    private var classes: Set<String> { stack.last?.classes ?? [] }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        var frame = stack.last ?? Frame(transform: .identity, classes: [], bold: false, defID: nil)
        if let t = a["transform"] { frame.transform = Self.transform(t).concatenating(frame.transform) }
        if let c = a["class"] { frame.classes.formUnion(c.split(separator: " ").map(String.init)) }
        if a["font-weight"] == "bold" { frame.bold = true }
        // Verovio marks editing placeholders with a circle that browsers hide with CSS.
        if frame.classes.contains("placeholder") {
            stack.append(frame)
            return
        }

        switch element {
        case "svg":
            let box = a["viewBox"].flatMap(Self.rect) ?? .zero
            if viewBox == nil {
                viewBox = box
            } else if let outer = viewBox, box.width > 0, box.height > 0 {
                // A nested svg without width and height fills its parent's viewport.
                let scale = CGAffineTransform(scaleX: outer.width / box.width, y: outer.height / box.height)
                    .translatedBy(x: -box.minX, y: -box.minY)
                frame.transform = scale.concatenating(frame.transform)
            }
        case "defs":
            inDefs += 1
        case "g" where inDefs > 0 && currentDef == nil:
            if let id = a["id"] {
                currentDef = id
                defs[id] = CGMutablePath()
                frame.transform = a["transform"].map(Self.transform) ?? .identity
                frame.defID = id
            }
        case "path":
            if let d = a["d"] { add(path: SVGPathParser.path(d), attributes: a, frame: frame) }
        case "rect":
            let r = CGRect(x: num(a["x"]), y: num(a["y"]), width: num(a["width"]), height: num(a["height"]))
            add(path: CGPath(rect: r, transform: nil), attributes: a, frame: frame, closed: true)
        case "ellipse", "circle":
            let rx = num(a["rx"] ?? a["r"]), ry = num(a["ry"] ?? a["r"])
            let r = CGRect(x: num(a["cx"]) - rx, y: num(a["cy"]) - ry, width: rx * 2, height: ry * 2)
            add(path: CGPath(ellipseIn: r, transform: nil), attributes: a, frame: frame, closed: true)
        case "polygon", "polyline":
            let pts = Self.numbers(a["points"] ?? "")
            let path = CGMutablePath()
            for i in stride(from: 0, to: pts.count - 1, by: 2) {
                let p = CGPoint(x: pts[i], y: pts[i + 1])
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            if element == "polygon" { path.closeSubpath() }
            add(path: path, attributes: a, frame: frame, closed: element == "polygon")
        case "use":
            let ref = (a["href"] ?? a["xlink:href"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if let glyph = defs[ref] {
                let offset = CGAffineTransform(translationX: num(a["x"]), y: num(a["y"]))
                var t = offset.concatenating(frame.transform)
                if let copy = glyph.copy(using: &t) { items.append(.fill(copy)) }
            }
        case "text":
            textOrigin = CGPoint(x: num(a["x"]), y: num(a["y"])).applying(frame.transform)
            textAnchor = a["text-anchor"] == "middle" ? .middle : a["text-anchor"] == "end" ? .end : .start
            textBuffer = ""
            textSize = 0
            textBold = frame.bold || !frame.classes.isDisjoint(with: ["reh", "tempo", "ending", "fing"])
            textItalic = !frame.classes.isDisjoint(with: ["dynam", "mNum", "dir"])
            tspanSizes = []
        case "tspan":
            if let s = a["font-size"], let size = Double(s.replacingOccurrences(of: "px", with: "")), size > 0 {
                // Font sizes are in the element's own units; scale them like the coordinates.
                let scale = sqrt(abs(frame.transform.a * frame.transform.d))
                textSize = CGFloat(size) * scale
            }
            if frame.bold { textBold = true }
        default:
            break
        }
        stack.append(frame)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if textOrigin != nil { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let frame = stack.popLast()
        switch element {
        case "defs":
            inDefs -= 1
        case "g":
            if let id = frame?.defID, id == currentDef { currentDef = nil }
        case "text":
            let words = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let origin = textOrigin, !words.isEmpty, textSize > 0 {
                items.append(.text(.init(string: words, position: origin, size: textSize,
                                         bold: textBold, italic: textItalic, anchor: textAnchor)))
            }
            textOrigin = nil
        default:
            break
        }
    }

    private func add(path: CGPath, attributes a: [String: String], frame: Frame, closed: Bool = false) {
        var t = frame.transform
        if let def = currentDef, let target = defs[def] {
            target.addPath(path, transform: t)
            return
        }
        guard let placed = path.copy(using: &t) else { return }
        let strokeWidth = a["stroke-width"].flatMap(Double.init)
        let hidden = a["fill-opacity"] == "0"
        let isClosed = closed || SVGPathParser.isClosed(a["d"] ?? "")
        if strokeWidth == nil || (isClosed && !hidden) {
            items.append(.fill(placed))
        }
        if let w = strokeWidth {
            let scale = sqrt(abs(t.a * t.d))
            items.append(.stroke(placed, width: CGFloat(w) * scale, round: a["stroke-linecap"] == "round"))
        }
    }

    private func num(_ s: String?) -> CGFloat { CGFloat(Double(s ?? "") ?? 0) }

    static func rect(_ s: String) -> CGRect? {
        let n = numbers(s)
        return n.count == 4 ? CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) : nil
    }

    static func numbers(_ s: String) -> [CGFloat] {
        s.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0).map { CGFloat($0) } }
    }

    /// `translate(…)`, `scale(…)` and `matrix(…)`, applied left to right as SVG does.
    static func transform(_ s: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let scanner = Scanner(string: s)
        while !scanner.isAtEnd {
            guard let name = scanner.scanUpToString("("), scanner.scanString("(") != nil,
                  let args = scanner.scanUpToString(")"), scanner.scanString(")") != nil else { break }
            let n = numbers(args)
            let t: CGAffineTransform
            switch name.trimmingCharacters(in: .whitespaces) {
            case "translate": t = CGAffineTransform(translationX: n.first ?? 0, y: n.count > 1 ? n[1] : 0)
            case "scale": t = CGAffineTransform(scaleX: n.first ?? 1, y: n.count > 1 ? n[1] : (n.first ?? 1))
            case "matrix" where n.count == 6: t = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            default: t = .identity
            }
            result = t.concatenating(result)
        }
        return result
    }
}

// MARK: - Path data

nonisolated enum SVGPathParser {
    static func isClosed(_ d: String) -> Bool {
        if d.contains("z") || d.contains("Z") { return true }
        let n = SceneBuilder.numbers(String(d.map { $0.isLetter ? " " : $0 }))
        return n.count >= 4 && n[0] == n[n.count - 2] && n[1] == n[n.count - 1] && n.count > 4
    }

    /// The path commands Verovio and SMuFL glyphs use: M L H V C S Q T Z, upper and lower case.
    static func path(_ d: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = Tokens(d)
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuad: CGPoint?
        var command: Character = "M"

        while let next = tokens.next() {
            if case .command(let c) = next { command = c } else { tokens.pushBack(next) }
            let relative = command.isLowercase
            func point() -> CGPoint? {
                guard let x = tokens.number(), let y = tokens.number() else { return nil }
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.uppercased().first! {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p); current = p; start = p
                command = relative ? "l" : "L" // further pairs are lines
                lastControl = nil; lastQuad = nil
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p); current = p
                lastControl = nil; lastQuad = nil
            case "H":
                guard let x = tokens.number() else { return path }
                current.x = relative ? current.x + x : x
                path.addLine(to: current); lastControl = nil; lastQuad = nil
            case "V":
                guard let y = tokens.number() else { return path }
                current.y = relative ? current.y + y : y
                path.addLine(to: current); lastControl = nil; lastQuad = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2; current = p; lastQuad = nil
            case "S":
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                lastControl = c2; current = p; lastQuad = nil
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                lastQuad = c; current = p; lastControl = nil
            case "T":
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
                lastQuad = c; current = p; lastControl = nil
            case "Z":
                path.closeSubpath(); current = start
                lastControl = nil; lastQuad = nil
            default:
                return path
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private struct Tokens {
        private let chars: [Character]
        private var i = 0
        private var pushed: Token?

        init(_ s: String) { chars = Array(s) }

        mutating func pushBack(_ t: Token) { pushed = t }

        mutating func number() -> CGFloat? {
            guard let t = next() else { return nil }
            if case .number(let n) = t { return n }
            pushBack(t); return nil
        }

        mutating func next() -> Token? {
            if let p = pushed { pushed = nil; return p }
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i].isNewline { i += 1 }
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter && c != "e" && c != "E" { i += 1; return .command(c) }
            var s = ""
            var seenDot = false
            if c == "-" || c == "+" { s.append(c); i += 1 }
            while i < chars.count {
                let d = chars[i]
                if d.isNumber { s.append(d) }
                else if d == "." && !seenDot { seenDot = true; s.append(d) }
                else if (d == "e" || d == "E") { s.append(d); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]) } else { continue }
                }
                else { break }
                i += 1
            }
            return Double(s).map { .number(CGFloat($0)) }
        }
    }
}
