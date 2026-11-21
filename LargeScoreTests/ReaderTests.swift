import Testing
import Foundation
import CoreGraphics
@testable import LargeScore

struct PageTurnerTests {
    @Test func wholePageTurns() {
        var turner = PageTurner(pageCount: 3, halfPageTurns: false)
        let r1 = turner.forward()
        #expect(r1)
        #expect(turner.page == 1)
        let r2 = turner.forward()
        #expect(r2)
        let r3 = turner.forward()
        #expect(!r3)
        #expect(turner.page == 2)
        let r4 = turner.back()
        #expect(r4)
        #expect(turner.page == 1)
    }

    @Test func halfPageTurnsGoTopFirst() {
        var turner = PageTurner(pageCount: 2, halfPageTurns: true)
        let r5 = turner.forward()
        #expect(r5)
        #expect(turner.page == 0 && turner.halfway)
        let r6 = turner.forward()
        #expect(r6)
        #expect(turner.page == 1 && !turner.halfway)
        let r7 = turner.forward()
        #expect(!r7)
        let r8 = turner.back()
        #expect(r8)
        #expect(turner.page == 0 && !turner.halfway)
    }

    @Test func backFromHalfwayRestoresThePage() {
        var turner = PageTurner(pageCount: 3, halfPageTurns: true)
        turner.forward()
        let r9 = turner.back()
        #expect(r9)
        #expect(turner.page == 0 && !turner.halfway)
        let r10 = turner.back()
        #expect(!r10)
    }

    @Test func fewerPagesKeepsAValidPlace() {
        var turner = PageTurner(pageCount: 5, halfPageTurns: true, page: 4)
        turner.update(pageCount: 2, halfPageTurns: true)
        #expect(turner.page == 1)
        #expect(!turner.halfway)
    }
}

struct HalfPageSplitTests {
    private func lines(_ tops: [CGFloat], height: CGFloat = 100) -> [CGRect] {
        tops.map { CGRect(x: 0, y: $0, width: 500, height: height) }
    }

    @Test func splitsBelowTheNextPagesUpperLines() throws {
        let page = lines([0, 200, 400, 600], height: 120)
        let y = try #require(HalfPageSplit.split(current: page, next: page, pageHeight: 1000))
        // Lines ending by 600: the first three end at 120, 320, 520.
        #expect(y > 520 && y < 600)
    }

    @Test func movesUpRatherThanCutAThisPageLine() throws {
        let next = lines([0, 200, 400], height: 120)
        let current = lines([0, 180, 500], height: 120) // 500...620 spans 530
        let y = try #require(HalfPageSplit.split(current: current, next: next, pageHeight: 1000))
        #expect(y <= 500)
        #expect(!current.contains { $0.minY < y && $0.maxY > y })
    }

    @Test func noSplitWhenNothingFits() {
        let tall = lines([0], height: 900)
        #expect(HalfPageSplit.split(current: tall, next: tall, pageHeight: 1000) == nil)
    }
}

struct ReaderSettingsTests {
    @Test func defaultsAndPersistence() throws {
        let suite = try #require(UserDefaults(suiteName: "settings-test"))
        suite.removePersistentDomain(forName: "settings-test")
        let settings = ReaderSettings(store: suite)
        #expect(settings.sizeStep == ReaderSettings.defaultSizeStep)
        #expect(settings.boldLines)
        #expect(settings.pageColour == .light)
        #expect(!settings.onboardingDone)
        settings.sizeStep = 6
        settings.instrument = .viola
        settings.pageColour = .dark
        let again = ReaderSettings(store: suite)
        #expect(again.sizeStep == 6)
        #expect(again.instrument == .viola)
        #expect(again.pageColour == .dark)
        #expect(again.staffHeight == 88)
    }

    @Test func sampleClefFollowsTheInstrument() {
        #expect(Instrument.bassoon.sampleName == "evening-air")
        #expect(Instrument.viola.sampleName == "evening-air-alto")
        #expect(Instrument.flute.sampleName == "evening-air-treble")
        for instrument in Instrument.allCases {
            #expect(Bundle.main.url(forResource: instrument.sampleName, withExtension: "musicxml") != nil)
        }
    }
}

struct LaidOutPieceTests {
    @Test func barsPerPageAddUp() async throws {
        let loader = await ScoreLoader()
        let piece = Piece.sample(for: .bassoon)
        let laidOut = try await loader.layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 1248, height: 820), staffHeight: 72))
        let total = laidOut.pages.reduce(0) { $0 + $1.measureCount }
        #expect(total == 16)
        #expect(laidOut.bars(onPage: 0)?.lowerBound == 1)
        #expect(laidOut.pages.allSatisfy { !$0.systems.isEmpty && $0.systems.allSatisfy { !$0.isNull } })
    }
}
