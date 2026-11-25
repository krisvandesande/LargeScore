import Testing
import Foundation
import CoreGraphics
@testable import LargeScore

struct PieceSettingsTests {
    private func fresh(_ name: String) throws -> ReaderSettings {
        let suite = try #require(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        return ReaderSettings(store: suite)
    }

    @Test func aPieceReadsDifferentlyFromTheRest() throws {
        let settings = try fresh("piece-own")
        settings.set(.keyReminders, to: true, for: "a")
        settings.set(.pageColour, to: ReaderSettings.PageColour.yellowOnBlack.rawValue, for: "a")
        #expect(settings.bool(.keyReminders, for: "a"))
        #expect(!settings.bool(.keyReminders, for: "b"))
        #expect(settings.layoutRequest(for: CGSize(width: 900, height: 1200), piece: "a").keyReminders)
        #expect(!settings.layoutRequest(for: CGSize(width: 900, height: 1200), piece: "b").keyReminders)
        #expect(settings.pageInk(system: .light, piece: "a") == ReaderSettings.yellowInk)
        #expect(settings.pageInk(system: .light, piece: "b") == .black)
        #expect(settings.hasOwnSettings("a"))
        #expect(!settings.hasOwnSettings("b"))
    }

    @Test func theSameAsEveryPieceIsNotKept() throws {
        let settings = try fresh("piece-same")
        settings.set(.boldLines, to: false, for: "a")
        #expect(settings.isOwn(.boldLines, for: "a"))
        settings.set(.boldLines, to: true, for: "a")
        #expect(!settings.isOwn(.boldLines, for: "a"))
        #expect(!settings.hasOwnSettings("a"))
    }

    @Test func clearingGoesBackToAllMusic() throws {
        let settings = try fresh("piece-clear")
        settings.setSize(8, for: "a")
        settings.set(.playingOrder, to: true, for: "a")
        settings.clearOwnSettings("a")
        #expect(settings.sizeStep(for: "a") == settings.sizeStep)
        #expect(!settings.bool(.playingOrder, for: "a"))
        #expect(!settings.hasOwnSettings("a"))
    }

    @Test func ownSettingsAreKept() throws {
        let name = "piece-kept"
        let suite = try #require(UserDefaults(suiteName: name))
        suite.removePersistentDomain(forName: name)
        ReaderSettings(store: suite).set(.halfPageTurns, to: true, for: "a")
        #expect(ReaderSettings(store: suite).bool(.halfPageTurns, for: "a"))
    }
}

struct PieceFactsTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    @Test func everythingKnownIsALine() {
        let facts = PieceFacts.facts(PieceFacts.Input(
            arranger: "J. Smith", partName: "Bassoon", barCount: 64, transposition: "Up a fourth",
            programmes: ["Spring", "Christmas", "Spring"], ownSettings: true,
            lastOpenedAt: now, addedAt: now, now: now))
        #expect(facts.map(\.kind) == PieceFacts.Kind.allCases)
        #expect(facts.first { $0.kind == .bars }?.text == "64 bars")
        #expect(facts.first { $0.kind == .programmes }?.text == "In Spring and Christmas")
    }

    @Test func aNewPieceSaysWhenItWasAdded() {
        let facts = PieceFacts.facts(PieceFacts.Input(
            arranger: "  ", partName: "", barCount: 0, transposition: nil,
            programmes: [], ownSettings: false, lastOpenedAt: nil, addedAt: now, now: now))
        #expect(facts.map(\.kind) == [.played])
        #expect(facts[0].text.hasPrefix("Added "))
    }
}
