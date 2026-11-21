import Testing
import Foundation
import SwiftData
@testable import LargeScore

private func sample(_ name: String) throws -> Data {
    let url = try #require(Bundle.main.url(forResource: name, withExtension: nil))
    return try Data(contentsOf: url)
}

struct MusicFileTests {
    @Test func compressedAndPlainReadTheSame() throws {
        let mxl = try MusicFile.read(sample("evening-air-quartet.mxl"), fileName: "evening-air-quartet.mxl")
        let plain = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "evening-air-quartet.musicxml")
        #expect(mxl.xml == plain.xml)
        #expect(mxl.title == "Evening Air for Four")
        #expect(mxl.composer == "Test piece")
        #expect(mxl.parts.map(\.name) == ["Flute", "Clarinet in B♭", "Fagot", "Horn in F"])
        #expect(mxl.parts[2].sounds == ["wind.reed.bassoon"])
        #expect(mxl.parts[2].abbreviation == "Fg.")
    }

    @Test func instrumentPicksItsPart() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        #expect(file.suggestedPart(for: [.bassoon])?.id == "P3")
        #expect(file.suggestedPart(for: [.clarinet])?.id == "P2")
        #expect(file.suggestedPart(for: [.horn])?.id == "P4")
        #expect(file.suggestedPart(for: [.flute])?.id == "P1")
        #expect(file.suggestedPart(for: [.violin]) == nil)
        #expect(file.suggestedPart(for: []) == nil)
    }

    @Test func namesWithoutSoundIDs() {
        let part = { (name: String) in ScorePart(id: "P", name: name) }
        #expect(Instrument.bassoon.matches(part("Fagott 1")))
        #expect(!Instrument.bassoon.matches(part("Contrabassoon")))
        #expect(!Instrument.clarinet.matches(part("Bass Clarinet")))
        #expect(!Instrument.horn.matches(part("English Horn")))
        #expect(!Instrument.violin.matches(part("Violoncello")))
        #expect(Instrument.cello.matches(part("Violoncello")))
        #expect(Instrument.viola.matches(part("Altviool")))
    }

    @Test func firstInstrumentThatPlaysWins() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        #expect(file.suggestedPart(for: [.violin, .horn, .bassoon])?.id == "P4")
        #expect(file.suggestedPart(for: [.bassoon, .horn])?.id == "P3")
    }

    @Test func severalPartsReadTogether() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let two = try #require(PartSplitter.keeping(partIDs: ["P3", "P1"], in: file.xml))
        #expect(PartSplitter.parts(in: two).map(\.id) == ["P1", "P3"])
        #expect(!two.contains("print-object=\"no\""))
        // Rehearsal marks and tempo once, on the top part.
        #expect(two.components(separatedBy: "<rehearsal>A</rehearsal>").count == 2)
        #expect(two.components(separatedBy: "Andante").count == 2)
        #expect(two.components(separatedBy: "<p></p>").count == 3) // dynamics stay with each part
        var chosen = [file.parts[2]]
        chosen = PartPicking.toggle(file.parts[0], in: chosen, order: file.parts)
        #expect(chosen.map(\.id) == ["P1", "P3"])
        chosen = PartPicking.toggle(file.parts[2], in: chosen, order: file.parts)
        chosen = PartPicking.toggle(file.parts[0], in: chosen, order: file.parts)
        #expect(chosen.map(\.id) == ["P1"]) // never down to none
    }

    @Test func titleFallsBackToFileName() throws {
        let xml = #"<?xml version="1.0"?><score-partwise><part-list><score-part id="P1"><part-name>Oboe</part-name></score-part></part-list><part id="P1"></part></score-partwise>"#
        let file = try MusicFile.read(Data(xml.utf8), fileName: "Mars march.musicxml")
        #expect(file.title == "Mars march")
        #expect(file.suggestedPart(for: [])?.id == "P1") // the only part
    }

    @Test func utf16Files() throws {
        let xml = #"<?xml version="1.0" encoding="UTF-16"?><score-partwise><work><work-title>Mélodie</work-title></work><part-list><score-part id="P1"><part-name>Oboe</part-name></score-part></part-list></score-partwise>"#
        var data = Data([0xFF, 0xFE])
        data.append(xml.data(using: .utf16LittleEndian)!)
        #expect(try MusicFile.read(data, fileName: "m.xml").title == "Mélodie")
    }

    @Test func refusesWhatItCantRead() {
        #expect(throws: MusicFile.Failure.timewise) {
            try MusicFile.read(Data("<score-timewise></score-timewise>".utf8), fileName: "t.xml")
        }
        #expect(throws: MusicFile.Failure.notMusicXML) {
            try MusicFile.read(Data("<html></html>".utf8), fileName: "page.xml")
        }
        #expect(throws: MusicFile.Failure.damaged) {
            try MusicFile.read(Data([0x50, 0x4B, 0x03, 0x04, 0, 0, 0]), fileName: "broken.mxl")
        }
    }

    @Test func onePartHidesItsName() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let one = try #require(PartSplitter.keeping(partID: "P3", in: file.xml))
        #expect(one.contains(#"<part-name print-object="no">Fagot</part-name>"#))
        #expect(!one.contains("Flute"))
    }
}

@MainActor
struct ImportSessionTests {
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Score.self, Programme.self, ProgrammeEntry.self, Annotation.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func addsWithTheSuggestedPart() async throws {
        let context = try context()
        let url = try #require(Bundle.main.url(forResource: "evening-air-quartet.mxl", withExtension: nil))
        let (files, failures) = await ImportSession.read([url])
        #expect(failures.isEmpty)
        let session = ImportSession(files: files, failures: [], instruments: [.bassoon], library: [])
        #expect(session.isReady)
        #expect(session.apply(to: context) == 1)
        let scores = try context.fetch(FetchDescriptor<Score>())
        #expect(scores.count == 1)
        #expect(scores[0].partName == "Fagot")
        #expect(scores[0].partCount == 4)
        #expect(try scores[0].piece.musicXML().contains("<step>F</step>"))
    }

    @Test func notReadyWithoutAPart() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let session = ImportSession(files: [file], failures: [], instruments: [.violin], library: [])
        #expect(!session.isReady)
    }

    @Test func replaceKeepsThePartAndCanBeUndone() throws {
        let context = try context()
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let score = Score(file: file, parts: [file.parts[3]])
        context.insert(score)
        var newer = file
        newer.xml = file.xml.replacingOccurrences(of: "Andante", with: "Adagio")
        let session = ImportSession(files: [newer], failures: [], instruments: [.bassoon], library: [score])
        #expect(session.candidates[0].existing === score)
        #expect(session.candidates[0].parts.map(\.id) == ["P4"]) // the piece's own part, not the bassoon
        session.apply(to: context)
        #expect(try context.fetch(FetchDescriptor<Score>()).count == 1)
        #expect(score.partName == "Horn in F")
        #expect(String(decoding: score.musicXML!, as: UTF8.self).contains("Adagio"))
        #expect(score.previousMusicXML != nil)
        score.restorePrevious()
        #expect(String(decoding: score.musicXML!, as: UTF8.self).contains("Andante"))
        #expect(score.previousMusicXML == nil)
    }

    @Test func addAsNewKeepsBoth() throws {
        let context = try context()
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let score = Score(file: file, parts: [file.parts[2]])
        context.insert(score)
        let session = ImportSession(files: [file], failures: [], instruments: [.bassoon], library: [score])
        session.candidates[0].replace = false
        session.apply(to: context)
        #expect(try context.fetch(FetchDescriptor<Score>()).count == 2)
    }

    @Test func scoreKeepsSeveralParts() throws {
        let file = try MusicFile.read(sample("evening-air-quartet.musicxml"), fileName: "q.musicxml")
        let score = Score(file: file, parts: [file.parts[0], file.parts[2]])
        #expect(score.partIDs == ["P1", "P3"])
        #expect(score.partName == "Flute, Fagot")
        #expect(score.piece.partIDs == ["P1", "P3"])
        score.replaceMusic(with: file, parts: [])
        #expect(score.partIDs == ["P1", "P3"])
    }

    @Test func sameTitleIgnoresCaseAndSpacing() {
        #expect(Score.key("Evening  Air", "Test Piece") == Score.key("evening air", "test piece"))
        #expect(Score.key("Evening Air", nil) != Score.key("Evening Air", "Someone"))
    }
}
