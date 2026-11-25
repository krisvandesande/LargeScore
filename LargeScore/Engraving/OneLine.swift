import Foundation
import CoreGraphics

/// For sizes where a busy bar is wider than a page: the part engraved as one long line
/// (Verovio without line breaks), cut into screens a reader turns through like pages.
/// A screen ends at the last bar line that fits, so bars stay whole; only a bar wider
/// than the screen is split, and the next screen then picks up a little before the cut.
nonisolated enum OneLine {
    struct Screen {
        var scene: SVGScene
        /// The number, from 1, of the first bar the screen shows.
        var firstBar: Int
    }

    /// Margins as the reader's pages keep them, in points.
    static let margin: CGFloat = 24

    static func screens(of line: SVGScene, area: CGSize, staffHeight: CGFloat) -> [Screen] {
        let staves = line.measures.filter { !$0.isNull }
        guard !staves.isEmpty, let content = line.systems.first(where: { !$0.isNull }),
              area.width > 0, area.height > 0 else { return [] }
        // Points per page unit, so one staff comes out `staffHeight` points tall (a piano
        // part's bars span two). A part of one-line staves (percussion) has no staff
        // height to measure: Verovio's own five-line staff is 72 units at scale 100,
        // drawn here at 10 viewBox units each.
        let span = line.staffSpan ?? 720
        let scale = staffHeight / span
        let width = area.width / scale
        let height = area.height / scale
        let usable = width - 2 * margin / scale
        // Centred top to bottom when the line fits; else from its top.
        let top = content.height < height ? content.midY - height / 2 : content.minY - margin / scale
        let barLines = staves.map(\.maxX).sorted()
        let itemBounds = line.items.map(SVGScene.bounds)

        var screens: [Screen] = []
        var start = content.minX
        while true {
            let rect = CGRect(x: start - margin / scale, y: top, width: width, height: height)
            let end = start + usable
            let last = end >= content.maxX - 1
            // The last bar line on this screen, if it leaves at least a third of a screen behind it.
            let barLine = last ? nil : barLines.last { $0 <= end && $0 > start + usable / 3 }
            let scene = line.window(rect, itemBounds: itemBounds, cutoff: barLine ?? .infinity, start: start)
            // The bar before ends on the screen's first bar line, a hair inside the margin.
            let firstIndex = line.measures.firstIndex { !$0.isNull && $0.maxX > start + 1 } ?? 0
            screens.append(Screen(scene: scene, firstBar: firstIndex + 1))
            if last { break }
            // Next screen from that bar line; a bar wider than the screen carries on a
            // little before the cut.
            start = barLine ?? start + usable * 0.85
        }
        return screens
    }
}
