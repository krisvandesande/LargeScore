import Testing
import UIKit
@testable import LargeScore

/// Writes Thin and Bold renders of the sample to build/thickness-*.png for a look.
@MainActor
struct ThicknessRenderTests {
    @Test func renderPortraitPage() async throws {
        let loader = ScoreLoader()
        let size = CGSize(width: 904, height: 1180)
        for staff in [CGFloat(56), 64, 72] {
            let laidOut = try await loader.layOut(.sample(for: .bassoon), request: LayoutRequest(pageSize: size, staffHeight: staff, bold: true))
            let page = try #require(laidOut.pages.first)
            print("LINES staff \(Int(staff)): \(page.systems.count) lines on page 1, \(laidOut.pages.count) pages")
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor, glyphWeight: staff / 4 * 0.07)
            }
            try image.pngData()!.write(to: URL(fileURLWithPath: "/Users/kris/Developer/LargeScore/build/portrait-\(Int(staff)).png"))
        }
    }

    @Test func renderThinAndBold() async throws {
        let loader = ScoreLoader()
        let size = CGSize(width: 900, height: 300)
        for bold in [false, true] {
            let laidOut = try await loader.layOut(.sample(for: .bassoon), request: LayoutRequest(pageSize: size, staffHeight: 64, bold: bold))
            let page = try #require(laidOut.pages.first)
            let image = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor,
                                 glyphWeight: bold ? 64 / 4 * 0.07 : 0)
            }
            try image.pngData()!.write(to: URL(fileURLWithPath: "/Users/kris/Developer/LargeScore/build/thickness-\(bold ? "bold" : "thin").png"))
        }
    }
}
