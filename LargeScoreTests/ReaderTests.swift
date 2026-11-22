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
        #expect(settings.pageColour == .system)
        #expect(!settings.onboardingDone)
        settings.sizeStep = 6
        settings.instruments = [.viola, .cello]
        settings.pageColour = .dark
        settings.lineGap = 4
        let again = ReaderSettings(store: suite)
        #expect(again.sizeStep == 6)
        #expect(again.instruments == [.viola, .cello])
        #expect(again.instrument == .viola)
        #expect(again.pageColour == .dark)
        #expect(again.lineGap == 4)
        #expect(again.layoutRequest(for: CGSize(width: 900, height: 1200)).lineGap == 4)
        #expect(again.staffHeight == 88)
    }

    @Test func buildOnesSingleInstrumentCarriesOver() throws {
        let suite = try #require(UserDefaults(suiteName: "settings-migrate"))
        suite.removePersistentDomain(forName: "settings-migrate")
        suite.set("bassoon", forKey: "instrument")
        #expect(ReaderSettings(store: suite).instruments == [.bassoon])
    }

    @Test func boldThickensGlyphs() throws {
        let suite = try #require(UserDefaults(suiteName: "settings-bold"))
        suite.removePersistentDomain(forName: "settings-bold")
        let settings = ReaderSettings(store: suite)
        #expect(settings.glyphWeight > 0)
        settings.boldLines = false
        #expect(settings.glyphWeight == 0)
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
        let loader = ScoreLoader()
        let piece = Piece.sample(for: .bassoon)
        let laidOut = try await loader.layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 1248, height: 820), staffHeight: 72))
        let total = laidOut.pages.reduce(0) { $0 + $1.measureCount }
        #expect(total == 16)
        #expect(laidOut.bars(onPage: 0)?.lowerBound == 1)
        #expect(laidOut.pages.allSatisfy { !$0.systems.isEmpty && $0.systems.allSatisfy { !$0.isNull } })
    }
}

/// Pages with room for less than another line have their music centred.
@MainActor
struct CentredPageTests {
    @Test func fullPagesAreCentredTheLastIsNot() async throws {
        let url = try #require(Bundle.main.url(forResource: "long-piece", withExtension: "musicxml"))
        let xml = try String(contentsOf: url, encoding: .utf8)
        let piece = Piece(id: "long", title: "long", source: .stored(Data(xml.utf8)))
        var request = LayoutRequest(pageSize: CGSize(width: 1008, height: 1262), staffHeight: 64)
        request.centred = true
        let laidOut = try await ScoreLoader().layOut(piece, request: request)
        let plain = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: request.pageSize, staffHeight: 64))
        func gaps(_ page: SVGScene) -> (above: CGFloat, below: CGFloat) {
            let lines = page.systems.filter { !$0.isNull }
            let content = lines.dropFirst().reduce(lines[0]) { $0.union($1) }
            return (content.minY - page.viewBox.minY, page.viewBox.maxY - content.maxY)
        }
        for (i, page) in plain.pages.enumerated() {
            let g = gaps(page), c = gaps(laidOut.pages[i])
            print("CENTRE page \(i + 1): lines \(page.systems.count) plain above \(Int(g.above)) below \(Int(g.below)) → centred above \(Int(c.above)) below \(Int(c.below))")
        }
        for page in laidOut.pages.dropLast() {
            let g = gaps(page)
            #expect(abs(g.above - g.below) < 1)
        }
        // Moved, not re-engraved: the same lines, lower down.
        #expect(laidOut.pages[1].systems.count == plain.pages[1].systems.count)
        #expect(laidOut.pages[1].measures[0].minY > plain.pages[1].measures[0].minY)
        // The last page, mostly empty, keeps its music at the top.
        let last = try #require(laidOut.pages.last), plainLast = try #require(plain.pages.last)
        if gaps(plainLast).below > 600 {
            #expect(last.measures[0].minY == plainLast.measures[0].minY)
        }
    }
}

@MainActor
struct SpacingMigrationTests {
    @Test func earlierChoicesBecomeGaps() throws {
        for (choice, gap) in [("less", 0), ("normal", 1), ("more", 4)] {
            let suite = try #require(UserDefaults(suiteName: "spacing-\(choice)"))
            suite.removePersistentDomain(forName: "spacing-\(choice)")
            suite.set(choice, forKey: "lineSpacing")
            #expect(ReaderSettings(store: suite).lineGap == gap)
        }
    }
}
