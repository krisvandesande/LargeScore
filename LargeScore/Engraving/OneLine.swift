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
        guard let firstStaff = staves.first, firstStaff.height > 0,
              let content = line.systems.first(where: { !$0.isNull }) else { return [] }
        // Points per page unit, so a staff comes out `staffHeight` points tall.
        let scale = staffHeight / firstStaff.height
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
            let scene = line.window(rect, itemBounds: itemBounds, cutoff: barLine ?? .infinity)
            let firstIndex = line.measures.firstIndex { !$0.isNull && $0.intersects(rect) } ?? 0
            screens.append(Screen(scene: scene, firstBar: firstIndex + 1))
            if last { break }
            // Next screen from that bar line; a bar wider than the screen carries on a
            // little before the cut.
            start = barLine ?? start + usable * 0.85
        }
        return screens
    }
}
