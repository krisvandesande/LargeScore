import Testing
import Foundation
@testable import LargeScore

struct DetailsTests {
    @Test func detailsAreReadBackFirst() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LargeScore/Resources/Samples/converted-by-audiveris.mxl")
        let file = try MusicFile.read(Data(contentsOf: url), fileName: "piece.mxl")
        let xml = MusicXMLEdit.settingDetails(file.xml, title: "Alte Kameraden", composer: "Carl Teike", arranger: "R & J")
        let again = try MusicFile.read(Data(xml.utf8), fileName: "other.musicxml")
        #expect(again.title == "Alte Kameraden")
        #expect(again.composer == "Carl Teike")
        #expect(again.arranger == "R & J")
        #expect(again.parts.count == file.parts.count)
        // Set again: replaced, not added twice; an empty arranger is removed.
        let twice = MusicXMLEdit.settingDetails(xml, title: "Kameraden", composer: "C. Teike", arranger: "")
        #expect(twice.components(separatedBy: "<work-title>").count == 2)
        let read = try MusicFile.read(Data(twice.utf8), fileName: "x.musicxml")
        #expect(read.title == "Kameraden")
        #expect(read.composer == "C. Teike")
        #expect(read.arranger == nil)
    }

    @Test func libraryIDIsWrittenOnceAndSurvivesDetails() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LargeScore/Resources/Samples/converted-by-audiveris.mxl")
        let file = try MusicFile.read(Data(contentsOf: url), fileName: "piece.mxl")
        #expect(MusicXMLEdit.libraryID(in: file.xml) == nil)
        let marked = MusicXMLEdit.settingLibraryID(file.xml, id: "A1")
        #expect(MusicXMLEdit.libraryID(in: marked) == "A1")
        let again = MusicXMLEdit.settingLibraryID(marked, id: "B2")
        #expect(MusicXMLEdit.libraryID(in: again) == "B2")
        #expect(again.components(separatedBy: "large-score-id").count == 2)
        // Still reads as the same music, and a details edit keeps the id.
        let read = try MusicFile.read(Data(again.utf8), fileName: "x.musicxml")
        #expect(read.parts.count == file.parts.count)
        let edited = MusicXMLEdit.settingDetails(again, title: "New", composer: "", arranger: "")
        #expect(MusicXMLEdit.libraryID(in: edited) == "B2")
        // The piece finds it in its stored bytes.
        let score = Score(file: read, parts: Array(read.parts.prefix(1)))
        #expect(score.hasLibraryID("B2"))
        #expect(!score.hasLibraryID("A1"))
    }
}
