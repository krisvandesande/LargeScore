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
}
