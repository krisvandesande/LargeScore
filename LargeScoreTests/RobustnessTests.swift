import Testing
import Foundation
import CoreGraphics
@testable import LargeScore

/// What the hostile review of 2026-11-25 found, kept from coming back.
struct RobustnessTests {
    private static func sampleXML(_ name: String) throws -> String {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "musicxml"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// A piano part: two staves, treble and bass, `bars` bars of quarter notes.
    static func piano(bars: Int) -> String {
        var measures = ""
        for n in 1...bars {
            let attributes = n == 1 ? """
            <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>\
            <staves>2</staves><clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
            """ : ""
            let upper = String(repeating: "<note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>", count: 4)
            let lower = String(repeating: "<note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><voice>2</voice><type>quarter</type><staff>2</staff></note>", count: 4)
            measures += "<measure number=\"\(n)\">\(attributes)\(upper)<backup><duration>4</duration></backup>\(lower)</measure>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
        <part id="P1">\(measures)</part></score-partwise>
        """
    }

    // MARK: Engraving

    @Test func thinLinesComeBackAfterBold() async throws {
        let xml = try Self.sampleXML("evening-air")
        let thin = LayoutRequest(pageSize: CGSize(width: 900, height: 1200), staffHeight: 64, bold: false)
        var bold = thin
        bold.bold = true
        let used = VerovioEngraver()
        _ = try await used.engrave(musicXML: xml, request: bold)
        let after = try await used.engrave(musicXML: xml, request: thin)
        let fresh = try await VerovioEngraver().engrave(musicXML: xml, request: thin)
        // Every line's thickness, in drawing order: what Bold changes. (Verovio names
        // each load afresh, so the drawings themselves never compare equal.)
        let widths = { (score: EngravedScore) -> [String] in
            score.pages.flatMap { page in
                (try? NSRegularExpression(pattern: #"stroke-width="([^"]+)"|height="([^"]+)""#))?
                    .matches(in: page.svg, range: NSRange(page.svg.startIndex..., in: page.svg))
                    .compactMap { Range($0.range, in: page.svg).map { String(page.svg[$0]) } } ?? []
            }
        }
        #expect(widths(after) == widths(fresh))
        #expect(widths(after) != widths(try await VerovioEngraver().engrave(musicXML: xml, request: bold)))
    }

    @Test func aPageTooSmallForVerovioStillEngraves() async throws {
        let xml = try Self.sampleXML("evening-air")
        let tiny = LayoutRequest(pageSize: CGSize(width: 120, height: 120), staffHeight: 120)
        _ = try await VerovioEngraver().engrave(musicXML: xml, request: tiny)
        #expect(VerovioEngraver.options(for: tiny)["pageWidth"] as? Int == 100)
    }

    @Test func pianoStavesAreAsTallAsAskedOnOneLine() async throws {
        let piece = Piece(id: "piano", title: "Piano", source: .stored(Data(Self.piano(bars: 16).utf8)))
        let area = CGSize(width: 1008, height: 1262)
        let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: area, staffHeight: 195, oneLine: true))
        let page = try #require(laidOut.pages.first)
        let span = try #require(page.staffSpan)
        #expect(abs(span * ScoreCanvas.scale(of: page, in: area) - 195) < 2)
        // A bar spans both staves, so it is far taller than one.
        #expect(try #require(page.measures.first).height > span * 1.5)
    }

    @Test func oneLineScreensStartAtTheirOwnFirstBar() async throws {
        let piece = Piece(id: "long", title: "Long", source: .stored(Data(try Self.sampleXML("long-piece").utf8)))
        let laidOut = try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 1008, height: 1262),
                                                                                    staffHeight: 195, oneLine: true))
        for (index, page) in laidOut.pages.enumerated().dropFirst() {
            // The bar before ends on the screen's first bar line, inside the margin: not counted.
            let first = try #require(page.measures.first)
            #expect(first.maxX - page.viewBox.minX > page.viewBox.width * 0.1, "screen \(index + 1)")
            let previous = laidOut.firstBars[index - 1] + laidOut.pages[index - 1].measureCount
            #expect(laidOut.firstBars[index] == previous || laidOut.firstBars[index] == previous - 1, "screen \(index + 1)")
        }
    }

    @Test func malformedSVGNeitherHangsNorDraws() {
        // A number straight after a close used to loop for ever.
        let path = SVGPathParser.path("M0 0 L10 0 L10 10 Z 5 5 L 3 3")
        #expect(!path.isEmpty)
        #expect(SVGScene(svg: #"<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L1 1"/></svg>"#) == nil)
        #expect(SVGScene(svg: #"<svg viewBox="0 0 0 0"></svg>"#) == nil)
    }

    // MARK: Transposing

    @Test func clefsWithoutLineOrWithOctaveAreRewritten() {
        let t = Transposition(from: .bFlat, to: .cBass)
        let xml = """
        <clef><sign>G</sign></clef><clef number="2"><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef>\
        <time-modification></time-modification><clef><sign>C</sign><line>3</line></clef>
        """
        let result = t.clefs(in: xml)
        #expect(result == """
        <clef><sign>F</sign><line>4</line></clef><clef number="2"><sign>F</sign><line>4</line></clef>\
        <time-modification></time-modification><clef><sign>C</sign><line>3</line></clef>
        """)
        #expect(Transposition(from: .cBass, to: .bFlat, octaves: 1).description == "Up a sixteenth")
    }

    // MARK: Files

    @Test func zipSizesThatCantBeTrueAreRefused() throws {
        let url = try #require(Bundle.main.url(forResource: "evening-air-quartet", withExtension: "mxl"))
        var data = try Data(contentsOf: url)
        let entries = try ZipReader.entries(in: data)
        let score = try #require(entries.first { $0.name.hasSuffix(".musicxml") || $0.name.hasSuffix(".xml") && !$0.name.hasPrefix("META-INF") })
        #expect(score.method == 8)
        #expect(throws: (any Error).self) {
            try ZipReader.contents(of: ZipReader.Entry(name: score.name, method: 8, compressedSize: score.compressedSize,
                                                       size: Int(UInt32.max), localHeaderOffset: score.localHeaderOffset, crc: score.crc), in: data)
        }
        // A changed byte in the packed music is caught.
        let start = score.localHeaderOffset + 30 + Int(data[score.localHeaderOffset + 26]) + Int(data[score.localHeaderOffset + 28])
        data[start + score.compressedSize / 2] ^= 0x5A
        #expect(throws: (any Error).self) { try ZipReader.contents(of: score, in: data) }
        #expect(ZipReader.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func utf16WithoutAMarkIsRead() throws {
        let xml = try Self.sampleXML("evening-air")
        let data = try #require(xml.data(using: .utf16LittleEndian))
        #expect(!data.starts(with: [0xFF, 0xFE]))
        let file = try MusicFile.read(data, fileName: "utf16.musicxml")
        #expect(!file.parts.isEmpty)
    }

    @Test func aFileWithNoPartsDoesntHoldBackTheRest() throws {
        let good = try MusicFile.read(Data(try Self.sampleXML("evening-air").utf8), fileName: "good.musicxml")
        let empty = try MusicFile.read(Data(#"<?xml version="1.0"?><score-partwise version="4.0"></score-partwise>"#.utf8), fileName: "empty.musicxml")
        let session = ImportSession(files: [good, empty], failures: [], instruments: [.flute], library: [])
        #expect(session.candidates.count == 1)
        #expect(session.failures.map(\.reason) == [.noParts])
        #expect(session.isReady)
    }

    // MARK: Fix Notes

    @Test func barsThatDontAddUpIsQuickOnALongPiece() {
        let edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(Self.piano(bars: 1500)))
        let clock = ContinuousClock()
        let start = clock.now
        let wrong = edit.barsThatDontAddUp()
        #expect(wrong.isEmpty)
        #expect(clock.now - start < .seconds(2))
    }

    @Test func aRestOnTheLowerStaffBecomesANoteInItsClef() throws {
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(Self.piano(bars: 1)))
        // The lower staff's first note (ls-n5) made a rest, then a note again.
        try edit.edit(note: "ls-n5", .toggleRest)
        try edit.edit(note: "ls-n5", .toggleRest)
        let note = String(edit.xml[try #require(edit.elementRange("note", id: "ls-n5"))])
        #expect(note.contains("<step>D</step><octave>3</octave>"))
    }

    @Test func aDotNeedsAWrittenLength() throws {
        let xml = FixNotesTests.piece.replacingOccurrences(
            of: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>",
            with: #"<note><rest measure="yes"></rest><duration>4</duration><voice>1</voice></note>"#)
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(xml))
        #expect(throws: MusicXMLEdit.Failure.cannot) { try edit.edit(note: "ls-n4", .toggleDot) }
        // Made a note, it takes its length from its duration.
        try edit.edit(note: "ls-n4", .toggleRest)
        #expect(String(edit.xml[try #require(edit.elementRange("note", id: "ls-n4"))]).contains("<type>whole</type>"))
    }

    @Test func deletingANoteMovesTheNextVoicesBackup() throws {
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(Self.piano(bars: 1)))
        try edit.delete(note: "ls-n1")
        #expect(edit.xml.contains("<backup><duration>3</duration></backup>"))
        try edit.edit(note: "ls-n2", .length(.half))
        #expect(edit.xml.contains("<backup><duration>4</duration></backup>"))
        #expect(edit.barsThatDontAddUp().isEmpty)
    }

    @Test func aTimeSignatureLeavesTripletsAlone() throws {
        let xml = FixNotesTests.piece.replacingOccurrences(
            of: "<duration>1</duration><voice>1</voice><type>quarter</type></note>\n<note><pitch><step>G</step>",
            with: "<duration>1</duration><voice>1</voice><type>quarter</type><time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification></note>\n<note><pitch><step>G</step>")
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(xml))
        try edit.setTime(beats: 3, beatType: 4, bar: "ls-m1")
        #expect(edit.xml.contains("<time-modification><actual-notes>3</actual-notes>"))
        #expect(edit.xml.contains("<time><beats>3</beats><beat-type>4</beat-type></time>"))
        #expect(throws: MusicXMLEdit.Failure.cannot) { try edit.setTime(beats: 3, beatType: 0, bar: "ls-m1") }
    }

    @Test func partlyMarkedFilesGetUniqueIDs() {
        // The first note already carries the id the writer would give the second.
        var xml = FixNotesTests.piece
        let first = xml.range(of: "<note>")!
        xml.replaceSubrange(first, with: #"<note id="ls-n2">"#)
        let marked = MusicXMLEdit.withIDs(xml)
        let ids = marked.components(separatedBy: #"<note id=""#).dropFirst().map { $0.prefix { $0 != "\"" } }
        #expect(Set(ids).count == ids.count)
    }

    @Test func addedRestBarsHaveTappableNotes() throws {
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(FixNotesTests.piece.replacingOccurrences(
            of: "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>",
            with: #"<note><rest measure="yes"></rest><duration>4</duration><voice>1</voice></note>"#)))
        try edit.setRestBars(3, bar: "ls-m2")
        #expect(edit.xml.components(separatedBy: "<note>").count == 1)
    }
}
