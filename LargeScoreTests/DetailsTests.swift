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
}
