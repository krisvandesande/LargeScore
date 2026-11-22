import Testing
import Foundation
@testable import LargeScore

/// Fixing what a recognition program got wrong, on the MusicXML itself.
struct FixNotesTests {
    /// One bar of 4/4 in F major (one flat), divisions 1: F4 quarter, G4 quarter, A4 half.
    static let piece = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Bassoon</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>1</divisions><key><fifths>-1</fifths></key>
    <time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note>
    <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note>
    <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
    </measure><measure number="2">
    <note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>
    </measure></part></score-partwise>
    """

    private func edit() -> MusicXMLEdit { MusicXMLEdit(xml: MusicXMLEdit.withIDs(Self.piece)) }

    private func note(_ id: String, in edit: MusicXMLEdit) throws -> String {
        String(edit.xml[try #require(edit.elementRange("note", id: id))])
    }

    @Test func everyNoteAndBarGetsAnID() {
        let xml = MusicXMLEdit.withIDs(Self.piece)
        #expect(xml.components(separatedBy: #"<note id="ls-n"#).count == 5)
        #expect(xml.contains(#"<measure id="ls-m1" number="1">"#))
        // Ids already there are kept, and a second pass adds none.
        #expect(MusicXMLEdit.withIDs(xml) == xml)
    }

    @Test func higherAndLowerStayInTheKey() throws {
        var e = edit()
        try e.edit(note: "ls-n3", .step(1))          // A4 → B♭4 in F major
        #expect(try note("ls-n3", in: e).contains("<pitch><step>B</step><alter>-1</alter><octave>4</octave></pitch>"))
        try e.edit(note: "ls-n4", .step(-7))         // C5 → C4, an octave down
        #expect(try note("ls-n4", in: e).contains("<step>C</step><octave>4</octave>"))
        try e.edit(note: "ls-n1", .step(-1))         // F4 → E4
        #expect(try note("ls-n1", in: e).contains("<step>E</step><octave>4</octave>"))
    }

    @Test func accidentalsAreWrittenAndSounded() throws {
        var e = edit()
        try e.edit(note: "ls-n1", .accidental(.sharp))
        let n = try note("ls-n1", in: e)
        #expect(n.contains("<alter>1</alter>"))
        #expect(n.contains("<accidental>sharp</accidental>"))
        try e.edit(note: "ls-n1", .accidental(.natural))
        let natural = try note("ls-n1", in: e)
        #expect(!natural.contains("<alter>"))
        #expect(natural.components(separatedBy: "<accidental>").count == 2)
    }

    @Test func aShorterNoteRescalesThePart() throws {
        var e = edit()
        try e.edit(note: "ls-n1", .length(.sixteenth))
        #expect(e.xml.contains("<divisions>4</divisions>"))
        #expect(try note("ls-n1", in: e).contains("<duration>1</duration>"))
        #expect(try note("ls-n1", in: e).contains("<type>16th</type>"))
        #expect(try note("ls-n2", in: e).contains("<duration>4</duration>"))
        #expect(try note("ls-n4", in: e).contains("<duration>16</duration>"))
        // The bar is now short, and is flagged.
        #expect(e.barsThatDontAddUp() == ["ls-m1"])
    }

    @Test func dotsAndLengthsAddUp() throws {
        var e = edit()
        #expect(e.barsThatDontAddUp().isEmpty)
        try e.edit(note: "ls-n1", .toggleDot)        // dotted quarter: 1.5
        #expect(e.xml.contains("<divisions>2</divisions>"))
        #expect(try note("ls-n1", in: e).contains("<duration>3</duration>"))
        #expect(e.barsThatDontAddUp() == ["ls-m1"])
        try e.edit(note: "ls-n2", .length(.eighth))  // 1.5 + 0.5 + 2 = 4
        #expect(e.barsThatDontAddUp().isEmpty)
        try e.edit(note: "ls-n1", .toggleDot)
        #expect(!(try note("ls-n1", in: e)).contains("<dot>"))
        #expect(try note("ls-n1", in: e).contains("<duration>2</duration>"))
    }

    @Test func tiesJoinTheNextNote() throws {
        var e = edit()
        try e.edit(note: "ls-n3", .toggleTie)
        #expect(try note("ls-n3", in: e).contains(#"<tie type="start"></tie>"#))
        #expect(try note("ls-n3", in: e).contains(#"<notations><tied type="start"></tied></notations>"#))
        #expect(try note("ls-n4", in: e).contains(#"<tie type="stop"></tie>"#))
        try e.edit(note: "ls-n3", .toggleTie)
        #expect(!e.xml.contains("<tie"))
        #expect(!e.xml.contains("<tied"))
        // The last note has nothing to tie to.
        #expect(throws: MusicXMLEdit.Failure.cannot) { try e.edit(note: "ls-n4", .toggleTie) }
    }

    @Test func restsAndNotesSwap() throws {
        var e = edit()
        try e.edit(note: "ls-n2", .toggleRest)
        #expect(try note("ls-n2", in: e).contains("<rest></rest>"))
        #expect(!(try note("ls-n2", in: e)).contains("<pitch>"))
        try e.edit(note: "ls-n2", .toggleRest)
        #expect(try note("ls-n2", in: e).contains("<step>B</step>"))
    }

    @Test func barsGetMarksTempoAndFermata() throws {
        var e = edit()
        try e.add(.rehearsal("A"), toBar: "ls-m1")
        try e.add(.tempo("Allegro & vivo"), toBar: "ls-m1")
        try e.add(.fermata, toBar: "ls-m2")
        #expect(e.xml.contains("<rehearsal>A</rehearsal>"))
        #expect(e.xml.contains("Allegro &amp; vivo"))
        #expect(try note("ls-n4", in: e).contains("<fermata"))
        #expect(throws: MusicXMLEdit.Failure.notFound) { try e.add(.fermata, toBar: "nope") }
    }

    @Test func editedMusicStillEngravesAndKnowsItsNotes() async throws {
        var e = edit()
        try e.edit(note: "ls-n1", .length(.eighth))
        try e.edit(note: "ls-n2", .toggleDot)
        try e.add(.rehearsal("B"), toBar: "ls-m2")
        let request = LayoutRequest(pageSize: CGSize(width: 800, height: 1100), staffHeight: 40, bold: false, lineGap: 4)
        let engraved = try await VerovioEngraver().engrave(musicXML: e.xml, request: request)
        let page = try #require(engraved.pages.first.flatMap { SVGScene(svg: $0.svg) })
        #expect(Set(page.noteBoxes.keys) == ["ls-n1", "ls-n2", "ls-n3", "ls-n4"])
        #expect(page.measureIDs == ["ls-m1", "ls-m2"])
        let box = try #require(page.noteBoxes["ls-n3"])
        #expect(page.note(at: CGPoint(x: box.midX, y: box.midY), reach: 10) == "ls-n3")
        #expect(page.measure(at: CGPoint(x: page.measures[1].midX, y: page.measures[1].midY), reach: 0) == "ls-m2")
    }

    @Test func importedFilesCarryIDs() throws {
        let url = try #require(Bundle.main.url(forResource: "converted-by-audiveris.mxl", withExtension: nil))
        let file = try MusicFile.read(try Data(contentsOf: url), fileName: "c.mxl")
        #expect(file.xml.contains(#" id="ls-n1""#))
        #expect(MusicXMLEdit(xml: file.xml).barsThatDontAddUp().isEmpty)
    }

    // MARK: What the real parts needed

    @Test func deleteAndAddNotes() throws {
        var e = edit()
        try e.delete(note: "ls-n2")
        #expect(e.elementRange("note", id: "ls-n2") == nil)
        #expect(e.barsThatDontAddUp() == ["ls-m1"])
        let added = try e.addNote(after: "ls-n1")
        #expect(added == "ls-n5")
        #expect(try note("ls-n5", in: e).contains("<step>F</step>"))
        #expect(e.barsThatDontAddUp().isEmpty)
        // Order kept: n1, the copy, n3.
        let order = e.xml.components(separatedBy: #"<note id=""#).dropFirst().map { $0.prefix(5) }
        #expect(order.prefix(3) == ["ls-n1", "ls-n5", "ls-n3"])
    }

    @Test func deletingAChordsFirstNoteKeepsTheRest() throws {
        let chord = Self.piece.replacingOccurrences(
            of: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>",
            with: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note><note><chord></chord><pitch><step>E</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>")
        var e = MusicXMLEdit(xml: MusicXMLEdit.withIDs(chord))
        try e.delete(note: "ls-n4")
        #expect(try note("ls-n5", in: e).contains("<chord") == false)
        #expect(e.barsThatDontAddUp().isEmpty)
    }

    @Test func anEmptyBarGetsANote() throws {
        let empty = Self.piece.replacingOccurrences(
            of: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>", with: "")
        var e = MusicXMLEdit(xml: MusicXMLEdit.withIDs(empty))
        let id = try e.addNote(toBar: "ls-m2")
        #expect(try note(id, in: e).contains("<step>B</step><octave>4</octave>"))
        try e.edit(note: id, .length(.whole))
        #expect(e.barsThatDontAddUp().isEmpty)
    }

    @Test func wordsCanBeCorrectedOrRemoved() throws {
        var e = edit()
        try e.add(.tempo("P000 pifJ mosso"), toBar: "ls-m1")
        try e.add(.rehearsal("B"), toBar: "ls-m1")
        let lyric = e.xml.replacingOccurrences(of: "<type>half</type></note>", with: "<type>half</type><lyric number=\"1\"><syllabic>single</syllabic><text>If</text></lyric></note>")
        e = MusicXMLEdit(xml: lyric)
        #expect(e.words(inBar: "ls-m1").map(\.text) == ["P000 pifJ mosso", "B", "If"])
        try e.setWords(inBar: "ls-m1", at: 0, to: "Poco più mosso")
        #expect(e.words(inBar: "ls-m1").first?.text == "Poco più mosso")
        try e.setWords(inBar: "ls-m1", at: 2, to: "")
        try e.setWords(inBar: "ls-m1", at: 1, to: "")
        #expect(e.words(inBar: "ls-m1").map(\.text) == ["Poco più mosso"])
        #expect(!e.xml.contains("<lyric"))
        #expect(e.xml.components(separatedBy: "<direction ").count == 2)
        #expect(!e.xml.contains("<direction-type></direction-type>"))
    }

    @Test func timeSignatureChangesFromABar() throws {
        var e = edit()
        try e.setTime(beats: 2, beatType: 4, bar: "ls-m2")
        let bar2 = String(e.xml[try #require(e.elementRange("measure", id: "ls-m2"))])
        #expect(bar2.contains("<attributes><time><beats>2</beats><beat-type>4</beat-type></time></attributes>"))
        // The whole note is now too long for 2/4.
        #expect(e.barsThatDontAddUp() == ["ls-m2"])
        try e.setTime(beats: 3, beatType: 4, bar: "ls-m1")
        #expect(e.xml.contains("<time><beats>3</beats><beat-type>4</beat-type></time><clef>"))
    }

    @Test func multiBarRestsGrowAndShrink() throws {
        let rests = Self.piece.replacingOccurrences(
            of: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>",
            with: "<note><rest measure=\"yes\"></rest><duration>4</duration><voice>1</voice></note></measure><measure number=\"3\"><note><pitch><step>D</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>")
        var e = MusicXMLEdit(xml: MusicXMLEdit.withIDs(rests))
        #expect(throws: MusicXMLEdit.Failure.cannot) { try e.setRestBars(6, bar: "ls-m1") }
        try e.setRestBars(6, bar: "ls-m2")
        #expect(e.xml.contains("<multiple-rest>6</multiple-rest>"))
        #expect(e.xml.components(separatedBy: "<measure ").count - 1 == 8)
        #expect(e.barNumbers()["ls-m3"] == 8)
        #expect(e.xml.contains(#"id="ls-m3" number="8""#))
        #expect(e.barsThatDontAddUp().isEmpty)
        try e.setRestBars(2, bar: "ls-m2")
        #expect(e.xml.contains("<multiple-rest>2</multiple-rest>"))
        #expect(e.barNumbers()["ls-m3"] == 4)
        try e.setRestBars(1, bar: "ls-m2")
        #expect(!e.xml.contains("multiple-rest"))
        #expect(e.barNumbers()["ls-m3"] == 3)
    }

    @Test func barNumbersStartAtZeroAfterAPickup() {
        let pickup = MusicXMLEdit.withIDs(Self.piece.replacingOccurrences(of: #"<measure number="1">"#, with: #"<measure number="0" implicit="yes">"#))
        #expect(MusicXMLEdit(xml: pickup).barNumbers() == ["ls-m1": 0, "ls-m2": 1])
    }

    @Test func dynamicsGoUnderANoteOrTheBar() throws {
        var e = edit()
        try e.addDynamic("f", bar: "ls-m1", at: "ls-n2")
        try e.addDynamic("mf", bar: "ls-m2", at: nil)
        let bar1 = String(e.xml[try #require(e.elementRange("measure", id: "ls-m1"))])
        #expect(bar1.range(of: "<f></f>")!.lowerBound > bar1.range(of: #"id="ls-n1""#)!.lowerBound)
        #expect(bar1.range(of: "<f></f>")!.lowerBound < bar1.range(of: #"id="ls-n2""#)!.lowerBound)
        #expect(e.xml.contains(#"<direction placement="below"><direction-type><dynamics><mf></mf></dynamics></direction-type></direction><note id="ls-n4""#))
        #expect(throws: MusicXMLEdit.Failure.cannot) { try e.addDynamic("loud", bar: "ls-m1", at: nil) }
        #expect(e.barsThatDontAddUp().isEmpty)
    }

    @Test func symbolWordsFromRecognitionGo() {
        let xml = #"<measure id="m"><direction><direction-type><words>.&gt; . .</words></direction-type></direction><direction><direction-type><words>Poco più mosso</words></direction-type></direction><note><lyric><text>-</text></lyric><lyric><text>mf</text></lyric></note></measure>"#
        let tidy = MusicXMLEdit.withoutSymbolWords(xml)
        #expect(tidy == #"<measure id="m"><direction><direction-type><words>Poco più mosso</words></direction-type></direction><note><lyric><text>mf</text></lyric></note></measure>"#)
    }
}
