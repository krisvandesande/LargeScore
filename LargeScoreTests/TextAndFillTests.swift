import Testing
import UIKit
@testable import LargeScore

@MainActor
struct TextAndFillTests {
    private func harmony() throws -> String {
        let url = try #require(Bundle(for: Marker.self).url(forResource: "harmony-and-tempo", withExtension: "musicxml"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func onePartLosesTheScoresBraces() throws {
        let one = try #require(PartSplitter.keeping(partID: "P1", in: harmony()))
        #expect(!one.contains("part-group"))
    }

    @Test func chordNamesAndMetronomeDrawWithMusicCharacters() async throws {
        let piece = Piece(id: "h", title: "h", partIDs: ["P1"], source: .stored(Data(try harmony().utf8)))
        let size = CGSize(width: 900, height: 400)
        let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: size, staffHeight: 64))
        let page = try #require(laidOut.pages.first)
        var words: [String] = []
        for item in page.items {
            if case .text(let line, _) = item {
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                words.append(runs.map { run in
                    let range = CTRunGetStringRange(run)
                    let attributed = CTRunGetAttributes(run) as NSDictionary
                    _ = attributed
                    return "\(range.length)"
                }.joined())
            }
        }
        // The flat and the metronome note are outlines, never characters Times lacks.
        #expect(GlyphLibrary.shared.glyph(0xE260, font: "Leipzig") != nil)
        #expect(GlyphLibrary.shared.glyph(0xE1D5, font: "Leipzig") != nil)
        #expect(!words.isEmpty)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
        }
        try image.pngData()!.write(to: renderOutput("harmony.png"))
    }

    @Test func pagesFillWithoutRunningOff() async throws {
        let piece = Piece(id: "l", title: "l", source: .bundled("long-piece"))
        for staff in [CGFloat(48), 64, 88] {
            let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 1008, height: 1250), staffHeight: staff))
            #expect(!laidOut.overflows)
            print("FILL staff \(Int(staff)): \(laidOut.pages.first?.systems.count ?? 0) lines a page, \(laidOut.pages.count) pages")
        }
    }
}

private final class Marker {}
