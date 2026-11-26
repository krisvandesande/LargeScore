import XCTest

/// Setting a key read wrongly, and moving music to another key.
nonisolated final class KeyTests: XCTestCase {
    /// One bar in C: B, B with a printed flat, B again (takes the flat), E, and an F
    /// tied over from the bar before.
    static let bar = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Trombone</part-name></score-part></part-list>
    <part id="P1"><measure number="1" id="m1"><attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>F</sign><line>4</line></clef></attributes>
    <note id="n1"><pitch><step>B</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note id="n2"><pitch><step>B</step><alter>-1</alter><octave>3</octave></pitch><duration>1</duration><type>quarter</type><accidental>flat</accidental></note>
    <note id="n3"><pitch><step>B</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note id="n4"><pitch><step>E</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
    </measure>
    <measure number="2" id="m2"><note id="n5"><pitch><step>E</step><octave>3</octave></pitch><duration>1</duration><tie type="stop"/><type>quarter</type></note>
    <note id="n6"><pitch><step>E</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note>
    <note id="n7"><pitch><step>F</step><alter>1</alter><octave>3</octave></pitch><duration>2</duration><type>half</type><accidental>sharp</accidental></note>
    </measure></part></score-partwise>
    """

    @MainActor private func pitch(_ xml: String, _ id: String) -> String {
        let note = xml.firstMatch("(<note id=\"\(id)\"[\\s\\S]*?</note>)") ?? ""
        let step = note.firstMatch(#"<step>([A-G])</step>"#) ?? "?"
        let alter = note.firstMatch(#"<alter>(-?\d+)</alter>"#) ?? "0"
        let octave = note.firstMatch(#"<octave>(\d+)</octave>"#) ?? "?"
        return "\(step)\(alter)/\(octave)"
    }

    @MainActor func testSettingTheKeySpellsNotesByIt() throws {
        var edit = MusicXMLEdit(xml: Self.bar)
        try edit.setKey(-2, fromBar: "m1")
        XCTAssertEqual(edit.firstKey, -2)
        XCTAssertEqual(edit.xml.count(of: "<fifths>"), 1)
        XCTAssertEqual(pitch(edit.xml, "n1"), "B-1/3")   // the key's flat
        XCTAssertEqual(pitch(edit.xml, "n2"), "B-1/3")   // printed flat stays
        XCTAssertEqual(pitch(edit.xml, "n4"), "E-1/3")
        XCTAssertEqual(pitch(edit.xml, "n5"), "E0/3")    // tied over: as it was
        XCTAssertEqual(pitch(edit.xml, "n6"), "E-1/3")   // next bar: the key again
        XCTAssertEqual(pitch(edit.xml, "n7"), "F1/3")    // printed sharp stays
        // Back to no flats: a printed accidental still carries through its bar.
        try edit.setKey(0, fromBar: "m1")
        XCTAssertEqual(pitch(edit.xml, "n1"), "B0/3")
        XCTAssertEqual(pitch(edit.xml, "n3"), "B-1/3")
        XCTAssertEqual(MusicXMLEdit(xml: edit.xml).barsThatDontAddUp(), [])
    }

    @MainActor func testAKeyIsAddedWhereNoneWasWritten() throws {
        let noKey = Self.bar.replacingOccurrences(of: "<key><fifths>0</fifths></key>", with: "")
        var edit = MusicXMLEdit(xml: noKey)
        try edit.setKey(1, fromBar: "m1")
        XCTAssertTrue(edit.xml.contains("<divisions>1</divisions><key><fifths>1</fifths></key><time>"))
        XCTAssertEqual(pitch(edit.xml, "n7"), "F1/3")
    }

    @MainActor func testIntervals() {
        XCTAssertTrue(MusicXMLEdit.interval(from: 0, to: 2, up: true) == (1, 2))     // C to D up a second
        XCTAssertTrue(MusicXMLEdit.interval(from: 0, to: 2, up: false) == (-6, -10)) // down a seventh
        XCTAssertTrue(MusicXMLEdit.interval(from: -2, to: 0, up: false) == (-6, -10)) // B flat to C, down a seventh
        XCTAssertTrue(MusicXMLEdit.interval(from: 0, to: -1, up: true) == (3, 5))    // C to F up a fourth
    }

    @MainActor func testTransposingMovesNotesKeysAndAccidentals() throws {
        var edit = MusicXMLEdit(xml: Self.bar)
        edit.transpose(toKey: 2, up: true)                 // C to D, up a second
        XCTAssertEqual(edit.firstKey, 2)
        XCTAssertEqual(pitch(edit.xml, "n1"), "C1/4")      // B to C sharp, across the octave
        XCTAssertEqual(pitch(edit.xml, "n2"), "C0/4")      // B flat to C
        XCTAssertTrue((edit.xml.firstMatch(#"(<note id="n2"[\s\S]*?</note>)"#) ?? "").contains("<accidental>natural</accidental>"))
        XCTAssertEqual(pitch(edit.xml, "n7"), "G1/3")      // F sharp to G sharp
        XCTAssertTrue((edit.xml.firstMatch(#"(<note id="n7"[\s\S]*?</note>)"#) ?? "").contains("<accidental>sharp</accidental>"))
        edit.transpose(toKey: 0, up: false)                // and back
        XCTAssertEqual(pitch(edit.xml, "n1"), "B0/3")
        XCTAssertEqual(pitch(edit.xml, "n7"), "F1/3")
    }

    @MainActor func testChordNamesMove() {
        let chord = Self.bar.replacingOccurrences(of: "<note id=\"n1\"", with: "<harmony><root><root-step>B</root-step><root-alter>-1</root-alter></root><kind>major</kind></harmony><note id=\"n1\"")
        var edit = MusicXMLEdit(xml: chord)
        edit.transpose(toKey: 2, up: true)
        XCTAssertTrue(edit.xml.contains("<root><root-step>C</root-step></root>"))
    }

    @MainActor func testAMissingKeyIsPointedOut() throws {
        let model = FixModel(xml: Self.bar.replacingOccurrences(of: "<key><fifths>0</fifths></key>", with: ""))
        XCTAssertTrue(model.keyMissing)
        XCTAssertFalse(model.timeMissing)
        model.setKey(-2, fromStart: true)
        XCTAssertFalse(model.keyMissing)
        XCTAssertEqual(model.edit.firstKey, -2)
    }

    /// A bass clef read where the PDF has a treble clef: the notes stay on their lines.
    @MainActor func testClefKeepsNotesOnTheirLines() throws {
        var edit = MusicXMLEdit(xml: Self.bar)
        XCTAssertEqual(edit.clef(atBar: "m1"), .bass)
        try edit.setKey(-2, fromBar: "m1")
        try edit.setClef(.treble, fromBar: "m1")
        XCTAssertEqual(edit.clef(atBar: "m2"), .treble)
        XCTAssertTrue(edit.xml.contains("<clef><sign>G</sign><line>2</line></clef>"))
        XCTAssertEqual(pitch(edit.xml, "n1"), "G0/5")    // above the staff, as B was in the bass clef
        XCTAssertEqual(pitch(edit.xml, "n2"), "G-1/5")   // its printed flat stays a flat
        XCTAssertEqual(pitch(edit.xml, "n3"), "G-1/5")   // and carries through the bar
        XCTAssertEqual(pitch(edit.xml, "n4"), "C0/5")    // E in the bass clef: C here
        XCTAssertEqual(pitch(edit.xml, "n6"), "C0/5")
        XCTAssertEqual(pitch(edit.xml, "n7"), "D1/5")    // F sharp's line: D, sharp as printed
        try edit.setClef(.bass, fromBar: "m1")
        XCTAssertEqual(pitch(edit.xml, "n4"), "E-1/3")   // back, with the key's flat again
    }

    /// A trombone part in C, bass clef, rewritten for B flat in the treble clef: up a
    /// ninth, two sharps more, treble clef, every note keeping its new pitch.
    @MainActor func testRewritingForAnotherInstrument() {
        var edit = MusicXMLEdit(xml: Self.bar)
        edit.transpose(for: Transposition(from: .cBass, to: .bFlat))
        XCTAssertEqual(edit.firstKey, 2)
        XCTAssertEqual(edit.clef(atBar: "m1"), .treble)
        XCTAssertEqual(pitch(edit.xml, "n1"), "C1/5")    // B3 up a ninth
        XCTAssertEqual(pitch(edit.xml, "n4"), "F1/4")    // E3 up a ninth: F sharp, the key's
        XCTAssertEqual(pitch(edit.xml, "n7"), "G1/4")    // F sharp 3: G sharp 4
    }
}
