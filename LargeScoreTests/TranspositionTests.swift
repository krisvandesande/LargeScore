import Testing
import Foundation
@testable import LargeScore

/// Parts written for another instrument, read in the player's key.
struct TranspositionTests {
    @Test func nearestIntervals() {
        // A baritone sax part (E♭) on a B♭ baritone: up a fourth, G becomes C.
        #expect(Transposition(from: .eFlat, to: .bFlat).interval == "+P4")
        #expect(Transposition(from: .eFlat, to: .bFlat).description == "Up a fourth")
        #expect(Transposition(from: .eFlat, to: .bFlat, octaves: -1).interval == "-P5")
        #expect(Transposition(from: .c, to: .bFlat).interval == "+M2")
        #expect(Transposition(from: .bFlat, to: .c).interval == "-M2")
        #expect(Transposition(from: .f, to: .bFlat).interval == "-P4")
        #expect(Transposition(from: .c, to: .eFlat).interval == "-m3")
        #expect(Transposition(from: .bFlat, to: .bFlat).isNothing)
    }

    @Test func bassClefPartsOnATrebleInstrument() {
        // A trombone part in C, bass clef, on a B♭ treble-clef baritone: up a ninth, treble clef.
        let t = Transposition(from: .cBass, to: .bFlat)
        #expect(t.interval == "+M9")
        #expect(t.description == "Up a ninth")
        #expect(t.changesClef)
        let xml = "<clef><sign>F</sign><line>4</line></clef>"
        #expect(t.clefs(in: xml) == "<clef><sign>G</sign><line>2</line></clef>")
        #expect(Transposition(from: .bFlat, to: .cBass).interval == "-M9")
    }

    @Test func aTransposedPieceEngravesInItsNewKey() async throws {
        let xml = MusicXMLEdit.withIDs(FixNotesTests.piece) // F major, starting on F4
        var piece = Piece(id: "t", title: "t", source: .stored(Data(xml.utf8)))
        piece.transposition = Transposition(from: .eFlat, to: .bFlat) // up a fourth: B♭ major
        let request = LayoutRequest(pageSize: CGSize(width: 800, height: 1100), staffHeight: 40, bold: false)
        let plain = try await ScoreLoader().layOut(Piece(id: "p", title: "p", source: .stored(Data(xml.utf8))), request: request)
        let moved = try await ScoreLoader().layOut(piece, request: request)
        let a = try #require(plain.pages.first?.noteBoxes["ls-n1"]), b = try #require(moved.pages.first?.noteBoxes["ls-n1"])
        // F4 (stem up, head at the foot of its box) becomes B♭4 (stem down, head at the top).
        #expect(b.minY > a.minY)
        // Two flats in the key now: one more flat glyph drawn than before.
        #expect(moved.pages[0].items.count > plain.pages[0].items.count)
    }

    @Test func baritoneSaxIsNotABaritone() {
        let sax = ScorePart(id: "P1", name: "Bariton-saxofoon", abbreviation: "", instrumentNames: [], sounds: [])
        let horn = ScorePart(id: "P2", name: "Bariton", abbreviation: "", instrumentNames: [], sounds: [])
        #expect(!Instrument.baritone.matches(sax))
        #expect(Instrument.saxophone.matches(sax))
        #expect(Instrument.baritone.matches(horn))
    }
}
