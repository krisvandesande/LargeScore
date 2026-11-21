import Foundation
import VerovioToolkit

/// Engraves with Verovio. One toolkit, used from one actor, so calls never overlap.
actor VerovioEngraver: Engraver {
    /// Made on first use, inside the actor.
    private lazy var toolkit = VerovioToolkit(
        VerovioResources.bundle.resourceURL!.appendingPathComponent("data").path
    )
    private var cache: [CacheKey: EngravedScore] = [:]

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
            "pageWidth": Int((Double(request.pageSize.width) * unitsPerPoint).rounded()),
            "pageHeight": Int((Double(request.pageSize.height) * unitsPerPoint).rounded()),
            "pageMarginLeft": 50,
            "pageMarginRight": 0,
            "pageMarginTop": 60,
            "pageMarginBottom": 300,
            "scale": 100,
            "breaks": "auto",
            "adjustPageHeight": false,
            "svgViewBox": true,
            "svgRemoveXlink": true,
            "header": "none",
            "footer": "none",
            "font": "Leipzig",
            "spacingSystem": 14,
        ]
        if request.bold {
            options["staffLineWidth"] = 0.25
            options["stemWidth"] = 0.3
            options["barLineWidth"] = 0.4
        }
        return options
    }

    func engrave(musicXML: String, request: LayoutRequest) async throws -> EngravedScore {
        let key = CacheKey(source: musicXML.hashValue, request: request)
        if let cached = cache[key] { return cached }

        let clock = ContinuousClock()
        let start = clock.now
        let json = try JSONSerialization.data(withJSONObject: Self.options(for: request))
        _ = toolkit.setOptions(String(decoding: json, as: UTF8.self))
        guard toolkit.loadData(musicXML) else { throw EngravingError.unreadable }
        let count = toolkit.getPageCount()
        guard count > 0 else { throw EngravingError.empty }
        let pages = (1...count).map { EngravedPage(number: $0, svg: toolkit.renderToSVG($0, false)) }
        let score = EngravedScore(request: request, pages: pages, duration: clock.now - start)
        cache[key] = score
        return score
    }
}
