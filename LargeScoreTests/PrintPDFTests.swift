import Testing
import UIKit
@testable import LargeScore

/// Prints a part to a vector PDF at print size (A4, a 7 mm staff), the way notation
/// software exports one, for testing PDF conversion. Not part of the app.
@MainActor
struct PrintPDFTests {
    @Test func printBassoonPart() async throws {
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        let area = CGSize(width: 595 - 2 * 48, height: 842 - 2 * 48)
        let url = try #require(Bundle.main.url(forResource: "evening-air-quartet.musicxml", withExtension: nil))
        let xml = try String(contentsOf: url, encoding: .utf8)
        let piece = Piece(id: "pdf", title: "Evening Air for Four", partIDs: ["P3"], source: .stored(Data(xml.utf8)))
        let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: area, staffHeight: 20, bold: false, lineGap: 4))
        let data = UIGraphicsPDFRenderer(bounds: a4).pdfData { ctx in
            for page in laidOut.pages {
                ctx.beginPage()
                ctx.cgContext.translateBy(x: 48, y: 48)
                ScoreCanvas.draw(page, in: ctx.cgContext, size: area, ink: UIColor.black.cgColor)
            }
        }
        try data.write(to: renderOutput("evening-air-bassoon.pdf"))
        print("PDF pages: \(laidOut.pages.count)")
    }
}
