import Foundation
import CoreGraphics
import SwiftData

/// A note on the music: handwriting or a ready-made mark, fixed to a bar. Positions
/// are in staff spaces from the bar's top-left staff corner, so a note stays on its
/// bar and grows with the music whatever the size, spacing or orientation.
@Model
final class Annotation {
    var id: UUID = UUID()
    /// The bar, counted from 1 in the order the music is engraved.
    var bar: Int = 1
    var kind: String = MarkKind.ink.rawValue
    var x: Double = 0
    var y: Double = 0
    /// Handwriting: the points as x, y pairs in staff spaces, 32-bit floats.
    var points: Data?
    var createdAt: Date = Date.now
    var score: Score?

    init(mark: Mark) {
        id = mark.id
        bar = mark.bar
        kind = mark.kind.rawValue
        x = Double(mark.position.x)
        y = Double(mark.position.y)
        points = mark.points.isEmpty ? nil : Mark.pack(mark.points)
    }

    var mark: Mark {
        Mark(id: id, bar: bar, kind: MarkKind(rawValue: kind) ?? .ink,
             position: CGPoint(x: x, y: y), points: points.map(Mark.unpack) ?? [])
    }
}

nonisolated enum MarkKind: String, CaseIterable, Identifiable, Sendable {
    case ink, breath, fermata, finger1, finger2, finger3, finger4, finger5, watch, circle, highlight
    var id: String { rawValue }

    /// The SMuFL character for marks the music font has.
    var glyph: UInt32? {
        switch self {
        case .breath: 0xE4CE      // breathMarkComma
        case .fermata: 0xE4C0     // fermataAbove
        case .finger1: 0xED11
        case .finger2: 0xED12
        case .finger3: 0xED13
        case .finger4: 0xED14
        case .finger5: 0xED15
        default: nil
        }
    }

    /// Marks that belong to the whole bar rather than to a point in it.
    var isWholeBar: Bool { self == .circle || self == .highlight }
}

/// A note as a value, for drawing and placing without touching the store.
nonisolated struct Mark: Identifiable, Equatable, Sendable {
    var id = UUID()
    var bar: Int
    var kind: MarkKind
    /// For a point mark, where it sits; for ink, unused.
    var position: CGPoint = .zero
    /// For ink, the line's points.
    var points: [CGPoint] = []

    static func pack(_ points: [CGPoint]) -> Data {
        var floats: [Float32] = []
        floats.reserveCapacity(points.count * 2)
        for p in points { floats.append(Float32(p.x)); floats.append(Float32(p.y)) }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data) -> [CGPoint] {
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float32.self)) }
        return stride(from: 0, to: floats.count - 1, by: 2).map { CGPoint(x: CGFloat(floats[$0]), y: CGFloat(floats[$0 + 1])) }
    }
}

/// Converting between page points and bar-anchored staff spaces.
nonisolated struct BarGeometry {
    /// Each bar's staff area on the page, with its bar number.
    var bars: [(number: Int, box: CGRect)]
    /// One staff space in page units. Verovio's page units aren't points: the page is
    /// scaled to its drawn size, so the space comes from the page, not the request.
    var space: CGFloat

    init(page: SVGScene, firstBar: Int, request: LayoutRequest) {
        bars = page.measures.enumerated().compactMap { index, box in
            box.isNull ? nil : (firstBar + index, box)
        }
        let unitsPerPoint = request.pageSize.width > 0 ? page.viewBox.width / request.pageSize.width : 1
        space = request.staffHeight / 4 * unitsPerPoint
    }

    /// The bar a point belongs to: the one containing it, else the nearest.
    func bar(at point: CGPoint) -> (number: Int, box: CGRect)? {
        if let inside = bars.first(where: { $0.box.insetBy(dx: 0, dy: -space * 4).contains(point) }) { return inside }
        return bars.min { distance($0.box, point) < distance($1.box, point) }
    }

    func box(of bar: Int) -> CGRect? { bars.first { $0.number == bar }?.box }

    func anchor(_ point: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: (point.x - box.minX) / space, y: (point.y - box.minY) / space)
    }

    func place(_ point: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + point.x * space, y: box.minY + point.y * space)
    }

    /// A finished line of handwriting, fixed to the bar under its first point.
    func mark(ink line: [CGPoint]) -> Mark? {
        guard let first = line.first, let bar = bar(at: first) else { return nil }
        return Mark(bar: bar.number, kind: .ink, points: line.map { anchor($0, in: bar.box) })
    }

    func mark(_ kind: MarkKind, at point: CGPoint) -> Mark? {
        guard let bar = bar(at: point) else { return nil }
        return Mark(bar: bar.number, kind: kind, position: anchor(point, in: bar.box))
    }

    /// The marks within `radius` of a point on this page, for the eraser.
    func marks(_ marks: [Mark], near point: CGPoint, radius: CGFloat) -> [Mark] {
        marks.filter { mark in
            guard let box = box(of: mark.bar) else { return false }
            switch mark.kind {
            case .ink:
                let placed = mark.points.map { place($0, in: box) }
                if placed.count == 1 { return hypot(placed[0].x - point.x, placed[0].y - point.y) <= radius }
                return zip(placed, placed.dropFirst()).contains { Self.distance(from: point, to: $0, $1) <= radius }
            case .circle, .highlight:
                return box.insetBy(dx: -radius, dy: -radius).contains(point)
            default:
                let at = place(mark.position, in: box)
                return hypot(at.x - point.x, at.y - point.y) <= radius + space * 2
            }
        }
    }

    /// From a point to the nearest place on a line segment.
    static func distance(from p: CGPoint, to a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func distance(_ box: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(box.minX - point.x, 0, point.x - box.maxX)
        let dy = max(box.minY - point.y, 0, point.y - box.maxY)
        return hypot(dx, dy)
    }
}
