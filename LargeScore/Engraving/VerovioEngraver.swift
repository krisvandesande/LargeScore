import Foundation
import VerovioToolkit

/// Engraves with Verovio. One toolkit, used from one actor, so calls never overlap.
actor VerovioEngraver: Engraver {
    /// Made on first use, inside the actor.
    private lazy var toolkit = VerovioToolkit(
        VerovioResources.bundle.resourceURL!.appendingPathComponent("data").path
    )
    private var cache: [CacheKey: EngravedScore] = [:]
    /// Most recently used last. A long piece's pages run to megabytes, and resizing a
    /// Mac window makes a new layout for every size it passes through.
    private var recent: [CacheKey] = []
    static let cacheLimit = 8

    private struct CacheKey: Hashable {
        var source: Int
        var request: LayoutRequest
    }

    /// Verovio draws a staff as 8 half-spaces of `unit` (default 9) tenths of a millimetre;
    /// with `scale` 100 one Verovio unit is one SVG unit. The page is sized so that a
    /// staff comes out `staffHeight` points tall when the page is drawn at `pageSize`.
    nonisolated static func options(for request: LayoutRequest) -> [String: Any] {
        let unitsPerPoint = 72.0 / Double(request.staffHeight)
        var options: [String: Any] = [
            // Inside Verovio's own limits: a value outside them is refused, and the
            // toolkit keeps the last piece's page.
            "pageWidth": Self.units(request.pageSize.width, unitsPerPoint, max: 100_000),
            "pageHeight": Self.units(request.pageSize.height, unitsPerPoint, max: 60_000),
            // Equal on both sides, so the staff sits in the middle; just enough for a
            // three-digit bar number, which Verovio centres on the staff's left edge.
            "pageMarginLeft": 25,
            "pageMarginRight": 25,
            "pageMarginTop": 40,
            "pageMarginBottom": request.bottomRoom,
            "scale": 100,
            // One line: no line breaks, and the page as wide and tall as the music.
            "breaks": request.oneLine ? "none" : "auto",
            "adjustPageHeight": request.oneLine,
            "adjustPageWidth": request.oneLine,
            "svgViewBox": true,
            "svgRemoveXlink": true,
            "header": "none",
            "footer": "none",
            "font": "Leipzig",
            "spacingSystem": request.lineGap,
            // Verovio's own minimum between staves (12) stacks on top of what hangs
            // between them: at 0 a page of 64 pt staves holds 7 lines, not 6.
            "spacingStaff": 0,
            // Verovio follows the file's repeats and jumps and draws each bar where it is
            // played; a repeated bar keeps its id with "-rend2" added.
            "expandAlways": request.playingOrder,
        ]
        // Always set: the toolkit keeps options between pieces, and an empty value is none.
        options["transpose"] = request.transpose ?? ""
        // Thin is Verovio's own, close to print. Bold takes every line to near the
        // top of what Verovio allows, so the difference is plain at a glance.
        if request.bold {
            options["staffLineWidth"] = 0.30
            options["stemWidth"] = 0.40
            options["barLineWidth"] = 0.60
            options["thickBarlineThickness"] = 1.4
            options["ledgerLineThickness"] = 0.40
            options["hairpinThickness"] = 0.35
            options["slurMidpointThickness"] = 0.9
            options["slurEndpointThickness"] = 0.18
            options["tieMidpointThickness"] = 0.75
            options["tupletBracketThickness"] = 0.35
        } else {
            // Verovio's own values, set again: the toolkit keeps a bold engrave's widths.
            options["staffLineWidth"] = 0.15
            options["stemWidth"] = 0.20
            options["barLineWidth"] = 0.30
            options["thickBarlineThickness"] = 1.0
            options["ledgerLineThickness"] = 0.25
            options["hairpinThickness"] = 0.2
            options["slurMidpointThickness"] = 0.6
            options["slurEndpointThickness"] = 0.1
            options["tieMidpointThickness"] = 0.5
            options["tupletBracketThickness"] = 0.2
        }
        // Above 88 pt a busy bar nears the page's width; Verovio's tighter spacing keeps
        // whole bars on the page up to 120 pt on an upright 13-inch iPad (measured on
        // real parts), and puts more bars on each page. Below that, its own spacing.
        let tight = request.staffHeight > 88
        options["spacingLinear"] = tight ? 0.15 : 0.25
        options["spacingNonLinear"] = tight ? 0.45 : 0.6
        return options
    }

    nonisolated private static func units(_ points: CGFloat, _ unitsPerPoint: Double, max: Int) -> Int {
        let value = (Double(points) * unitsPerPoint).rounded()
        guard value.isFinite else { return 100 }
        return Swift.min(Swift.max(Int(value), 100), max)
    }

    func engrave(musicXML: String, request: LayoutRequest) async throws -> EngravedScore {
        let key = CacheKey(source: musicXML.hashValue, request: request)
        if let cached = cache[key] {
            recent.removeAll { $0 == key }
            recent.append(key)
            return cached
        }

        let clock = ContinuousClock()
        let start = clock.now
        let json = try JSONSerialization.data(withJSONObject: Self.options(for: request))
        guard toolkit.setOptions(String(decoding: json, as: UTF8.self)) else { throw EngravingError.unreadable }
        guard toolkit.loadData(musicXML) else { throw EngravingError.unreadable }
        let count = toolkit.getPageCount()
        guard count > 0 else { throw EngravingError.empty }
        let pages = (1...count).map { EngravedPage(number: $0, svg: toolkit.renderToSVG($0, false)) }
        let score = EngravedScore(request: request, pages: pages, duration: clock.now - start)
        cache[key] = score
        recent.append(key)
        while recent.count > Self.cacheLimit { cache[recent.removeFirst()] = nil }
        return score
    }
}
