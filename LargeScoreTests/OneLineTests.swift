import Testing
import UIKit
@testable import LargeScore

/// The largest sizes: the part as one line, cut into screens that end at bar lines.
@MainActor
struct OneLineTests {
    private func layOut(_ name: String, staff: CGFloat, area: CGSize = CGSize(width: 1008, height: 1262)) async throws -> LaidOutPiece {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "musicxml"))
        let xml = try String(contentsOf: url, encoding: .utf8)
        let piece = Piece(id: name, title: name, source: .stored(Data(xml.utf8)))
        return try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: area, staffHeight: staff, oneLine: true))
    }

    @Test func screensCoverEveryBarInOrder() async throws {
        let laidOut = try await layOut("long-piece", staff: 195)
        #expect(laidOut.pages.count > 3)
        // Every bar shows on some screen, and screens go forward.
        var seen = Set<Int>()
        for (index, page) in laidOut.pages.enumerated() {
            if let bars = laidOut.bars(onPage: index) { seen.formUnion(bars) }
            if index > 0 { #expect(page.viewBox.minX > laidOut.pages[index - 1].viewBox.minX) }
            #expect(abs(page.viewBox.width / page.viewBox.height - 1008.0 / 1262.0) < 0.001)
        }
        let total = try String(contentsOf: try #require(Bundle.main.url(forResource: "long-piece", withExtension: "musicxml")), encoding: .utf8)
            .components(separatedBy: "<measure ").count - 1
        #expect(seen == Set(1...total))
    }

    @Test func aStaffIsAsTallAsAsked() async throws {
        let laidOut = try await layOut("long-piece", staff: 230)
        let page = try #require(laidOut.pages.first)
        let staff = try #require(page.measures.first)
        let points = staff.height * ScoreCanvas.scale(of: page, in: CGSize(width: 1008, height: 1262))
        #expect(abs(points - 230) < 2)
    }

    @Test func renderScreens() async throws {
        let size = CGSize(width: 1008, height: 1262)
        let laidOut = try await layOut("long-piece", staff: 270)
        for index in 0..<min(3, laidOut.pages.count) {
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.clip(to: CGRect(origin: .zero, size: size))
                ScoreCanvas.draw(laidOut.pages[index], in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
            }
            try image.pngData()!.write(to: renderOutput("oneline-\(index + 1).png"))
        }
    }
}
