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

    static func == (a: Piece, b: Piece) -> Bool {
        a.id == b.id && a.partIDs == b.partIDs && a.version == b.version && a.transposition == b.transposition
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(partIDs)
        hasher.combine(version)
        hasher.combine(transposition)
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
    var firstBars: [Int]

    /// True when a page's music reaches past its bottom edge.
    var overflows: Bool {
        pages.contains { page in
            page.systems.contains { !$0.isNull && $0.maxY > page.viewBox.maxY }
        }
    }

    func bars(onPage index: Int) -> ClosedRange<Int>? {
        guard pages.indices.contains(index), pages[index].measureCount > 0 else { return nil }
        let first = firstBars[index]
        return first...(first + pages[index].measureCount - 1)
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
        var laidOut = await Self.read(try await engraver.engrave(musicXML: xml, request: request))
        // Pages are filled tightly; if anything under a page's last line runs off the
        // page, engrave again with more room at the foot, as often as needed.
        while laidOut.overflows, request.bottomRoom < 400 {
            request.bottomRoom += 60
            laidOut = await Self.read(try await engraver.engrave(musicXML: xml, request: request))
        }
        return laidOut
    }

    /// Splitting out one part reads the whole file: kept off the main thread.
    @concurrent
    nonisolated private static func prepare(_ piece: Piece) async throws -> String {
        try piece.musicXML()
    }

    @concurrent
    nonisolated private static func read(_ score: EngravedScore) async -> LaidOutPiece {
        let pages = score.pages.compactMap { SVGScene(svg: $0.svg) }
        var firstBars: [Int] = []
        var next = 1
        for page in pages {
            firstBars.append(next)
            next += page.measureCount
        }
        return LaidOutPiece(request: score.request, pages: pages, firstBars: firstBars)
    }
}
