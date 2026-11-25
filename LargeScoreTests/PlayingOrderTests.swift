import Testing
import Foundation
import UIKit
@testable import LargeScore

/// Repeats written out where they're played, so the pedal only goes forward.
struct PlayingOrderTests {
    /// Four bars; bars 1 and 2 are repeated, and bar 4 has first and second endings
    /// when `endings` is set (4a, then 4b after a repeat from bar 3).
    static func piece(endings: Bool = false) -> String {
        let note = "<note><pitch><step>C</step><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>whole</type></note>"
        let attributes = "<attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>"
        var bars = """
        <measure number="1" id="m1"><barline location="left"><bar-style>heavy-light</bar-style><repeat direction="forward"></repeat></barline>\(attributes)\(note)</measure>
        <measure number="2" id="m2">\(note)<barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"></repeat></barline></measure>
        <measure number="3" id="m3">\(note)</measure>
        """
        if endings {
            bars = bars.replacingOccurrences(of: #"<measure number="3" id="m3">"#,
                                             with: #"<measure number="3" id="m3"><barline location="left"><repeat direction="forward"></repeat></barline>"#)
            bars += """
            <measure number="4" id="m4"><barline location="left"><ending number="1" type="start"></ending></barline>\(note)<barline location="right"><ending number="1" type="stop"></ending><repeat direction="backward"></repeat></barline></measure>
            <measure number="5" id="m5"><barline location="left"><ending number="2" type="start"></ending></barline>\(note)<barline location="right"><ending number="2" type="discontinue"></ending></barline></measure>
            """
        } else {
            bars += #"<measure number="4" id="m4">\#(note)</measure>"#
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
        <part id="P1">\(bars)</part></score-partwise>
        """
    }

    private func bars(_ xml: String, playingOrder: Bool, oneLine: Bool = false) async throws -> LaidOutPiece {
        let piece = Piece(id: UUID().uuidString, title: "Repeats", source: .stored(Data(xml.utf8)))
        return try await ScoreLoader().layOut(piece, request: LayoutRequest(pageSize: CGSize(width: 900, height: 1200),
                                                                             staffHeight: oneLine ? 195 : 48,
                                                                             oneLine: oneLine, playingOrder: playingOrder))
    }

    @Test func repeatsAreWrittenOut() async throws {
        let written = try await bars(Self.piece(), playingOrder: false)
        #expect(written.pageBars.flatMap { $0 } == [1, 2, 3, 4])
        let played = try await bars(Self.piece(), playingOrder: true)
        #expect(played.pageBars.flatMap { $0 } == [1, 2, 1, 2, 3, 4])
    }

    @Test func endingsAreFollowed() async throws {
        let played = try await bars(Self.piece(endings: true), playingOrder: true)
        #expect(played.pageBars.flatMap { $0 } == [1, 2, 1, 2, 3, 4, 3, 5])
    }

    @Test func playingOrderOnOneLine() async throws {
        let played = try await bars(Self.piece(), playingOrder: true, oneLine: true)
        // Screens overlap where a bar is wider than a screen: each drawn bar counted once.
        var ids: [String] = []
        var numbers: [Int] = []
        for (page, bars) in zip(played.pages, played.pageBars) {
            for (id, number) in zip(page.measureIDs, bars) where !ids.contains(id ?? "") {
                ids.append(id ?? "")
                numbers.append(number)
            }
        }
        #expect(numbers == [1, 2, 1, 2, 3, 4])
    }

    @Test func notesShowEachTimeTheirBarIsPlayed() async throws {
        let played = try await bars(Self.piece(), playingOrder: true)
        let geometry = BarGeometry(page: played.pages[0], numbers: played.pageBars[0], request: played.request)
        #expect(geometry.boxes(of: 2).count == 2)
        #expect(geometry.boxes(of: 4).count == 1)
    }

    @Test func renderPlayingOrder() async throws {
        let played = try await bars(Self.piece(endings: true), playingOrder: true)
        let size = CGSize(width: 900, height: 1200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ScoreCanvas.draw(played.pages[0], in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
        }
        try image.pngData()!.write(to: renderOutput("playing-order.png"))
    }
}

/// The key's sharps and flats on every note they apply to.
struct KeyReminderTests {
    @Test func notesTheKeyAltersGetTheirAccidental() {
        // F major: B is flat. B♭ gets a flat, B natural (already marked) and F are left.
        let xml = """
        <part id="P1"><measure><attributes><key><fifths>-1</fifths></key></attributes>
        <note><pitch><step>B</step><alter>-1</alter><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note>
        <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><accidental>natural</accidental></note>
        <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type></note>
        <note><pitch><step>B</step><alter>-1</alter><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><tie type="stop"></tie></note>
        </measure></part>
        """
        let result = KeyReminders.apply(xml)
        #expect(result.components(separatedBy: "<accidental>flat</accidental>").count == 2)
        #expect(result.contains("<type>quarter</type><accidental>flat</accidental></note>"))
        #expect(result.components(separatedBy: "<accidental>natural</accidental>").count == 2)
    }

    @Test func eachPartStartsInC() {
        let xml = #"<part id="P1"><fifths>2</fifths></part><part id="P2"><note><pitch><step>F</step><alter>1</alter><octave>4</octave></pitch><type>quarter</type></note></part>"#
        #expect(KeyReminders.apply(xml) == xml)
    }

    @Test func remindersEngrave() async throws {
        let url = try #require(Bundle.main.url(forResource: "evening-air", withExtension: "musicxml"))
        let piece = Piece(id: "k", title: "K", source: .stored(try Data(contentsOf: url)))
        var request = LayoutRequest(pageSize: CGSize(width: 900, height: 1200), staffHeight: 64)
        request.keyReminders = true
        let laidOut = try await ScoreLoader().layOut(piece, request: request)
        let page = try #require(laidOut.pages.first)
        let size = CGSize(width: 900, height: 1200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            ScoreCanvas.draw(page, in: ctx.cgContext, size: size, ink: UIColor.black.cgColor)
        }
        try image.pngData()!.write(to: renderOutput("key-reminders.png"))
    }
}
