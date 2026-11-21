import Testing
import UIKit
@testable import LargeScore

@MainActor
struct MarkRenderTests {
    @Test func renderBarMarks() async throws {
        let size = CGSize(width: 1008, height: 1200)
        let laidOut = try await ScoreLoader().layOut(.sample(for: .bassoon), request: LayoutRequest(pageSize: size, staffHeight: 64))
        let page = laidOut.pages[0]
        let geometry = BarGeometry(page: page, firstBar: 1, request: laidOut.request)
        print("VIEWBOX", page.viewBox, "SYSTEMS", page.systems.map { Int($0.minY) })
        print("BOXES", geometry.bars.map { "\($0.number): y\(Int($0.box.minY))-\(Int($0.box.maxY)) x\(Int($0.box.minX))" })
        let marks = [Mark(bar: 5, kind: .circle), Mark(bar: 6, kind: .highlight)]
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor,
                             marks: (marks, geometry, UIColor.red.cgColor))
        }
        try image.pngData()!.write(to: renderOutput("marks.png"))
    }
}
