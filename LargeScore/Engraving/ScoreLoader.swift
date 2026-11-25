import Foundation
import CoreGraphics

/// A piece the app can open: the bundled sample, or a score from the library with
/// the part to show.
nonisolated struct Piece: Identifiable, Hashable, Sendable {
    enum Source: Sendable {
        case bundled(String)
        case stored(Data)
    }

    var id: String
    var title: String
    var composer: String?
    var partIDs: [String] = []
    var source: Source
    /// Changes whenever the music or the part changes.
    var version: Date = .distantPast
    /// Read in another key, for a part written for another instrument.
    var transposition: Transposition?

    /// Bytes of stored music: changes when music synced from iCloud arrives, which
    /// leaves the version as it was.
    var size: Int {
        if case .stored(let data) = source { data.count } else { -1 }
    }

    /// Stored music that hasn't arrived yet (still on its way from iCloud).
    var isMissing: Bool { size == 0 }

    static func == (a: Piece, b: Piece) -> Bool {
        a.id == b.id && a.partIDs == b.partIDs && a.version == b.version && a.transposition == b.transposition
            && a.size == b.size
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(partIDs)
        hasher.combine(version)
        hasher.combine(transposition)
        hasher.combine(size)
    }

    /// The score as the engraver gets it: one part only.
    func musicXML() throws -> String {
        let xml: String
        switch source {
        case .bundled(let resource):
            guard let url = Bundle.main.url(forResource: resource, withExtension: "musicxml") else {
                throw EngravingError.unreadable
            }
            xml = try String(contentsOf: url, encoding: .utf8)
        case .stored(let data):
            xml = String(decoding: data, as: UTF8.self)
        }
        let kept = partIDs.isEmpty ? xml : PartSplitter.keeping(partIDs: partIDs, in: xml) ?? xml
        return transposition?.clefs(in: kept) ?? kept
    }

    static func sample(for instrument: Instrument?) -> Piece {
        Piece(id: "sample", title: "Evening Air", composer: nil, partIDs: [],
              source: .bundled((instrument ?? .flute).sampleName))
    }
}

/// A piece engraved and read into scenes for one layout.
nonisolated struct LaidOutPiece: Sendable {
    var request: LayoutRequest
    var pages: [SVGScene]
    /// The first bar number on each page, counted from 1.
    /// Each page's first bar, as the score numbers it.
    var firstBars: [Int]
    /// The number, as the score numbers it, of every bar in each page's `measures`. In
    /// playing order a repeated bar comes again with its own number.
    var pageBars: [[Int]]

    init(request: LayoutRequest, pages: [SVGScene], pageBars: [[Int]]) {
        self.request = request
        self.pages = pages
        self.pageBars = pageBars
        var previous = 0
        firstBars = pageBars.map { bars in
            let first = bars.first ?? previous + 1
            previous = bars.last ?? first
            return first
        }
    }

    /// How far the music reaches past a page's bottom edge, at most; 0 when it fits.
    var overflow: CGFloat {
        pages.map { page in
            page.systems.filter { !$0.isNull }.map { $0.maxY - page.viewBox.maxY }.max() ?? 0
        }.max().map { max($0, 0) } ?? 0
    }

    var overflows: Bool { overflow > 0 }

    func bars(onPage index: Int) -> ClosedRange<Int>? {
        guard pageBars.indices.contains(index), let low = pageBars[index].min(), let high = pageBars[index].max() else { return nil }
        return low...high
    }
}

/// One engraver for the whole app; engraving runs on its actor, reading the pages
/// into scenes runs off the main thread too.
@Observable
final class ScoreLoader {
    private let engraver = VerovioEngraver()

    func layOut(_ piece: Piece, request: LayoutRequest) async throws -> LaidOutPiece {
        let xml = try await Self.prepare(piece)
        var request = request
        request.transpose = piece.transposition?.interval
        try Task.checkCancellation()
        var laidOut = try await Self.read(try await engraver.engrave(musicXML: xml, request: request))
        // Pages are filled tightly; if anything under a page's last line runs off the
        // page, engrave again with more room at the foot, while that helps. A line
        // taller than the page on its own runs off however much room there is.
        while laidOut.overflows, !request.oneLine, request.bottomRoom < 400 {
            try Task.checkCancellation()
            request.bottomRoom += 60
            let roomier = try await Self.read(try await engraver.engrave(musicXML: xml, request: request))
            guard roomier.overflow < laidOut.overflow else { break }
            laidOut = roomier
        }
        try Task.checkCancellation()
        return laidOut
    }

    /// Splitting out one part reads the whole file: kept off the main thread.
    @concurrent
    nonisolated private static func prepare(_ piece: Piece) async throws -> String {
        try piece.musicXML()
    }

    @concurrent
    nonisolated private static func read(_ score: EngravedScore) async throws -> LaidOutPiece {
        // A page that can't be read would shift every later bar number: none, or all.
        var pages = score.pages.compactMap { SVGScene(svg: $0.svg, withoutRepeatDots: score.request.playingOrder) }
        guard !pages.isEmpty, pages.count == score.pages.count else { throw EngravingError.empty }
        if score.request.oneLine {
            // Without line breaks Verovio makes one page; should a very long part ever
            // come out on more, the screens carry on through each in turn.
            let numbers = Self.barNumbers(pages.flatMap(\.measureIDs))
            var screens: [OneLine.Screen] = []
            for line in pages {
                screens += OneLine.screens(of: line, area: score.request.pageSize, staffHeight: score.request.staffHeight)
            }
            guard !screens.isEmpty else { throw EngravingError.empty }
            return LaidOutPiece(request: score.request, pages: screens.map(\.scene),
                                pageBars: screens.map { Self.numbered($0.scene.measureIDs, numbers) })
        }
        if score.request.centred {
            pages = pages.enumerated().map { index, page in Self.centred(page, last: index == pages.count - 1) }
        }
        let numbers = Self.barNumbers(pages.flatMap(\.measureIDs))
        return LaidOutPiece(request: score.request, pages: pages, pageBars: pages.map { Self.numbered($0.measureIDs, numbers) })
    }

    /// Bar numbers by id, counted from 1 in the order bars first appear. Verovio draws a
    /// repeated bar again with "-rend2" added to its id: it keeps the number it was
    /// written with, so notes on it show each time it's played.
    nonisolated static func barNumbers(_ ids: [String?]) -> [String: Int] {
        var numbers: [String: Int] = [:]
        var next = 1
        for (index, id) in ids.enumerated() {
            let key = id.map(writtenID) ?? "#\(index)"
            if numbers[key] == nil { numbers[key] = next; next += 1 }
        }
        return numbers
    }

    nonisolated static func writtenID(_ id: String) -> String {
        guard let range = id.range(of: #"-rend\d+$"#, options: .regularExpression) else { return id }
        return String(id[..<range.lowerBound])
    }

    nonisolated private static func numbered(_ ids: [String?], _ numbers: [String: Int]) -> [Int] {
        var last = 0
        return ids.map { id in
            let n = id.flatMap { numbers[writtenID($0)] } ?? last + 1
            last = n
            return n
        }
    }

    /// The page's music moved to sit in the middle, top to bottom. Every page but the
    /// last is full (the next line didn't fit, even if the room looks close); the last
    /// is centred only when the room under it is less than another line, so the end
    /// of a piece keeps its music at the top, where reading starts.
    nonisolated static func centred(_ page: SVGScene, last isLastPage: Bool) -> SVGScene {
        let lines = page.systems.filter { !$0.isNull }
        guard let first = lines.first, let lastLine = lines.last else { return page }
        let content = lines.reduce(first) { $0.union($1) }
        let above = content.minY - page.viewBox.minY
        let below = page.viewBox.maxY - content.maxY
        // One more line: the distance from one line's top to the next, or a line's own height.
        let pitch = lines.count > 1 ? (lastLine.minY - first.minY) / CGFloat(lines.count - 1) : content.height
        guard !isLastPage || below < pitch else { return page }
        return page.shifted(by: (below - above) / 2)
    }
}
