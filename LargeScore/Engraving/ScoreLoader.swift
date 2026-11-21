import Foundation
import CoreGraphics

/// A piece the app can open. Until adding music arrives, the bundled sample.
nonisolated struct Piece: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var composer: String?
    var resource: String

    func musicXML() throws -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "musicxml") else {
            throw EngravingError.unreadable
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func sample(for instrument: Instrument?) -> Piece {
        Piece(id: "sample", title: "Evening Air", composer: nil,
              resource: (instrument ?? .flute).sampleName)
    }
}

/// A piece engraved and read into scenes for one layout.
nonisolated struct LaidOutPiece: Sendable {
    var request: LayoutRequest
    var pages: [SVGScene]
    /// The first bar number on each page, counted from 1.
    var firstBars: [Int]

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
        let xml = try piece.musicXML()
        let score = try await engraver.engrave(musicXML: xml, request: request)
        return await Self.read(score)
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
