import Testing
import UIKit
@testable import LargeScore

/// Kris's real parts, converted by Audiveris, from the gitignored "Demo Scores"
/// folder: engraved at print size beside nothing but themselves, for a look against
/// the PDFs. Skipped where the folder isn't there.
@MainActor
struct DemoScoreTests {
    nonisolated static let folder = URL(fileURLWithPath: "/Users/kris/Developer/LargeScore/Demo Scores")

    nonisolated static var files: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["mxl", "musicxml"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test(.enabled(if: !files.isEmpty)) func engraveDemoScores() async throws {
        let loader = ScoreLoader()
        for url in Self.files {
            let file = try MusicFile.read(try Data(contentsOf: url), fileName: url.lastPathComponent)
            let piece = Piece(id: url.lastPathComponent, title: file.title, composer: file.composer,
                              partIDs: file.parts.prefix(1).map(\.id), source: .stored(Data(file.xml.utf8)))
            let size = CGSize(width: 1200, height: 1700)
            let laidOut = try await loader.layOut(piece, request: LayoutRequest(pageSize: size, staffHeight: 40, bold: false, lineGap: 4))
            let edit = MusicXMLEdit(xml: file.xml)
            let wrong = edit.barsThatDontAddUp()
            let notes = file.xml.components(separatedBy: "<note ").count - 1
            let rests = file.xml.components(separatedBy: "<rest").count - 1
            print("DEMO \(url.lastPathComponent): title \(file.title), parts \(file.parts.map(\.name)), bars \(file.barCount), notes+rests \(notes) (rests \(rests)), pages \(laidOut.pages.count), wrong bars \(wrong.count): \(wrong.prefix(30))")
            for (index, page) in laidOut.pages.enumerated() {
                let image = UIGraphicsImageRenderer(size: size).image { ctx in
                    UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                    ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
                }
                try image.pngData()!.write(to: renderOutput("demo-\(url.deletingPathExtension().lastPathComponent)-\(index + 1).png"))
            }
        }
    }

    /// The fixes the real parts need, applied to their conversions.
    @Test(.enabled(if: !files.isEmpty)) func fixTheRealParts() async throws {
        func load(_ prefix: String) throws -> MusicXMLEdit? {
            guard let url = Self.files.first(where: { $0.lastPathComponent.hasPrefix(prefix) }) else { return nil }
            return MusicXMLEdit(xml: try MusicFile.read(try Data(contentsOf: url), fileName: url.lastPathComponent).xml)
        }
        if var alaaf = try load("Alaaf") {
            let before = alaaf.barsThatDontAddUp().count
            let bar = try #require(alaaf.barsThatDontAddUp().first { (alaaf.barNumbers()[$0] ?? 0) > 25 })
            try alaaf.setTime(beats: 2, beatType: 4, bar: bar)
            print("FIX Alaaf: 2/4 at bar \(alaaf.barNumbers()[bar] ?? 0): bars that don't add up \(before) → \(alaaf.barsThatDontAddUp().count)")
            #expect(alaaf.barsThatDontAddUp().count < before - 20)
        }
        if var klezmer = try load("A Klezmer") {
            let rest = try #require(klezmer.xml.range(of: "<multiple-rest>1</multiple-rest>"))
            let start = try #require(klezmer.xml.range(of: "<measure ", options: .backwards, range: klezmer.xml.startIndex..<rest.lowerBound))
            let id = try #require(String(klezmer.xml[start.lowerBound...].prefix(80)).firstMatch(#"\bid="([^"]+)""#))
            let bars = klezmer.barNumbers()
            let last = bars.values.max() ?? 0
            try klezmer.setRestBars(6, bar: id)
            print("FIX Klezmer: rest at bar \(bars[id] ?? 0) made 6 bars; last bar \(last) → \(klezmer.barNumbers().values.max() ?? 0)")
            #expect(klezmer.barNumbers().values.max() == last + 5)
            let piece = Piece(id: "k", title: "k", partIDs: [], source: .stored(Data(klezmer.xml.utf8)))
            let size = CGSize(width: 1200, height: 1700)
            let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: size, staffHeight: 40, bold: false, lineGap: 4))
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ScoreCanvas.draw(laidOut.pages[0], in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
            }
            try image.pngData()!.write(to: renderOutput("demo-klezmer-fixed-1.png"))
        }
        if var ragtime = try load("Alexander") {
            let numbers = ragtime.barNumbers()
            let byNumber = Dictionary(numbers.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
            let bar1 = try #require(byNumber[1]), bar5 = try #require(byNumber[5])
            // The word "Mf" sits in whichever bar Audiveris put it: find it.
            let wordBar = try #require(numbers.keys.first { ragtime.words(inBar: $0).contains { $0.text == "Mf" } })
            let index = try #require(ragtime.words(inBar: wordBar).firstIndex { $0.text == "Mf" })
            try ragtime.setWords(inBar: wordBar, at: index, to: "")
            try ragtime.addDynamic("f", bar: bar1, at: nil)
            try ragtime.addDynamic("mf", bar: bar5, at: nil)
            print("FIX Ragtime: Mf word in bar \(numbers[wordBar] ?? 0) removed, f and mf added; bars that don't add up: \(ragtime.barsThatDontAddUp().count)")
            let piece = Piece(id: "r", title: "r", partIDs: [], source: .stored(Data(ragtime.xml.utf8)))
            let size = CGSize(width: 1200, height: 500)
            let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: size, staffHeight: 40, bold: false, lineGap: 4))
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ScoreCanvas.draw(laidOut.pages[0], in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
            }
            try image.pngData()!.write(to: renderOutput("demo-ragtime-fixed.png"))
        }
    }
}
