import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import LargeScore

@MainActor
struct NotesTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Score.self, Programme.self, ProgrammeEntry.self, Annotation.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
    }

    private func quartet() throws -> MusicFile {
        let url = try #require(Bundle.main.url(forResource: "evening-air-quartet.musicxml", withExtension: nil))
        return try MusicFile.read(try Data(contentsOf: url), fileName: "q.musicxml")
    }

    @Test func everyBarHasItsPlaceOnThePage() async throws {
        let laidOut = try await ScoreLoader().layOut(.sample(for: .bassoon), request: LayoutRequest(pageSize: CGSize(width: 900, height: 1200), staffHeight: 64))
        for page in laidOut.pages {
            #expect(page.measures.count == page.measureCount)
            // One staff of 64 pt, in page units (9/8 of a point), plus the bold lines themselves.
            let unit = page.viewBox.width / laidOut.request.pageSize.width
            #expect(page.measures.allSatisfy { !$0.isNull && $0.height >= 63.5 * unit && $0.height < (64 + 16 * 0.6) * unit })
        }
    }

    @Test func notesStayOnTheirBarAcrossSizes() async throws {
        let piece = Piece.sample(for: .bassoon)
        let small = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 900, height: 1200), staffHeight: 48))
        let large = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 900, height: 1200), staffHeight: 88))
        let a = BarGeometry(page: small.pages[0], firstBar: 1, request: small.request)
        let bar3 = try #require(a.box(of: 3))
        let tap = CGPoint(x: bar3.midX, y: bar3.minY - 12)
        let mark = try #require(a.mark(.breath, at: tap))
        #expect(mark.bar == 3)
        let b = BarGeometry(page: large.pages[0], firstBar: 1, request: large.request)
        let bigBar3 = try #require(b.box(of: 3))
        let placed = b.place(mark.position, in: bigBar3)
        // Same spot relative to the bar, scaled with the staff.
        #expect(abs((placed.y - bigBar3.minY) / b.space - (tap.y - bar3.minY) / a.space) < 0.01)
        #expect(placed.x > bigBar3.minX && placed.x < bigBar3.maxX)
    }

    @Test func inkKeepsItsShape() {
        let points = [CGPoint(x: 1.5, y: -2), CGPoint(x: 3.25, y: 0.5)]
        #expect(Mark.unpack(Mark.pack(points)) == points)
    }

    @Test func eraserFindsWhatsUnderTheFinger() {
        var geometry = BarGeometry(page: try! #require(SVGScene(svg: #"<svg viewBox="0 0 100 100"></svg>"#)), firstBar: 1,
                                   request: LayoutRequest(pageSize: CGSize(width: 100, height: 100), staffHeight: 16))
        geometry.bars = [(1, CGRect(x: 0, y: 40, width: 50, height: 16)), (2, CGRect(x: 50, y: 40, width: 50, height: 16))]
        let ink = geometry.mark(ink: [CGPoint(x: 10, y: 30), CGPoint(x: 20, y: 30)])!
        let circle = Mark(bar: 2, kind: .circle)
        #expect(ink.bar == 1)
        #expect(geometry.marks([ink, circle], near: CGPoint(x: 15, y: 31), radius: 4).map(\.id) == [ink.id])
        #expect(geometry.marks([ink, circle], near: CGPoint(x: 75, y: 48), radius: 4).map(\.id) == [circle.id])
    }

    @Test func storeAddsRemovesAndUndoes() throws {
        let context = try context()
        let file = try quartet()
        let score = Score(file: file, parts: [file.parts[2]])
        context.insert(score)
        try context.save()
        let store = NotesStore(pieceID: score.id.uuidString, context: context)
        #expect(store.canAnnotate)
        let breath = Mark(bar: 2, kind: .breath, position: CGPoint(x: 1, y: -1))
        store.add(breath)
        #expect(score.annotations?.count == 1)
        store.remove([breath])
        #expect(score.annotations?.isEmpty == true)
        store.undo()
        #expect(score.annotations?.count == 1)
        store.note = "Watch the conductor at B"
        #expect(NotesStore(pieceID: score.id.uuidString, context: context).marks == [breath])
        #expect(score.note == "Watch the conductor at B")
    }

    @Test func notesSurviveANewVersion() throws {
        let context = try context()
        let file = try quartet()
        let score = Score(file: file, parts: [file.parts[2]])
        context.insert(score)
        let store = NotesStore(pieceID: score.id.uuidString, context: context)
        store.add(Mark(bar: 5, kind: .fermata))
        #expect(score.barCount == 16)
        score.replaceMusic(with: file, parts: [])
        #expect(score.annotations?.count == 1)
    }

    @Test func sampleTakesNoNotes() throws {
        #expect(!NotesStore(pieceID: "sample", context: try context()).canAnnotate)
    }
}
