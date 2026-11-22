import Foundation

/// Small corrections to a MusicXML file, for what music recognition gets wrong: a
/// note's pitch, accidental, length, dot, tie or rest, and a rehearsal mark, tempo
/// word or fermata on a bar. Notes and bars are found by their `id`, which
/// `withIDs` gives every one and which Verovio keeps on what it draws, so a tap on
/// the page finds exactly the note in the file.
///
/// Works on the file as `PartSplitter`'s echo writes it: every element with an
/// opening and closing tag, attributes in order.
nonisolated struct MusicXMLEdit {
    enum Failure: Error, Equatable {
        case notFound
        case cannot
    }

    enum Accidental: String, CaseIterable { case sharp, flat, natural }
    enum Length: String, CaseIterable {
        case whole, half, quarter, eighth, sixteenth = "16th"
        /// In quarter notes.
        var quarters: Double {
            switch self {
            case .whole: 4
            case .half: 2
            case .quarter: 1
            case .eighth: 0.5
            case .sixteenth: 0.25
            }
        }
    }

    enum NoteChange: Equatable {
        case step(Int)
        case accidental(Accidental)
        case length(Length)
        case toggleDot
        case toggleTie
        case toggleRest
    }

    enum BarAddition: Equatable {
        case rehearsal(String)
        case tempo(String)
        case fermata
    }

    var xml: String

    // MARK: Ids

    /// The file with an `id` on every note and bar that has none ("ls-n12",
    /// "ls-m3"). Ids already there are kept.
    static func withIDs(_ xml: String) -> String {
        let writer = IDWriter()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = writer
        return parser.parse() ? writer.output : xml
    }

    // MARK: Notes

    mutating func edit(note id: String, _ change: NoteChange) throws {
        guard let range = elementRange("note", id: id) else { throw Failure.notFound }
        let context = Context(xml: xml, upTo: range.lowerBound)
        var note = String(xml[range])
        switch change {
        case .step(let steps):
            guard let pitch = Pitch(note) else { throw Failure.cannot }
            let moved = pitch.moved(steps, fifths: context.fifths)
            note = note.replacingFirst(#"<pitch>[\s\S]*?</pitch>"#, with: moved.xml)
            note = note.removingAll(#"<accidental[^>]*>[\s\S]*?</accidental>"#)
        case .accidental(let accidental):
            guard var pitch = Pitch(note) else { throw Failure.cannot }
            pitch.alter = accidental == .sharp ? 1 : accidental == .flat ? -1 : 0
            note = note.replacingFirst(#"<pitch>[\s\S]*?</pitch>"#, with: pitch.xml)
            note = note.removingAll(#"<accidental[^>]*>[\s\S]*?</accidental>"#)
            note = note.inserting("<accidental>\(accidental.rawValue)</accidental>", after: ["</dot>", "</type>", "</voice>", "</duration>"])
        case .length(let length):
            let dots = note.components(separatedBy: "<dot>").count - 1
            note = note.replacingFirst(#"<type>[^<]*</type>"#, with: "<type>\(length.rawValue)</type>")
            if !note.contains("<type>") {
                note = note.inserting("<type>\(length.rawValue)</type>", after: ["</voice>", "</duration>"])
            }
            try setDuration(&note, quarters: length.quarters * Self.dotted(dots), at: range.lowerBound)
        case .toggleDot:
            let quarters = note.firstMatch(#"<type>([^<]*)</type>"#).flatMap { Length(rawValue: $0)?.quarters } ?? 1
            if note.contains("<dot>") {
                note = note.removingAll(#"<dot>\s*</dot>"#)
                try setDuration(&note, quarters: quarters, at: range.lowerBound)
            } else {
                note = note.inserting("<dot></dot>", after: ["</type>"])
                try setDuration(&note, quarters: quarters * 1.5, at: range.lowerBound)
            }
        case .toggleTie:
            try toggleTie(from: range)
            return
        case .toggleRest:
            if note.contains("<rest") {
                let pitch = Pitch.middleLine(clef: context.clef)
                note = note.replacingFirst(#"<rest[^>]*>[\s\S]*?</rest>"#, with: pitch.xml)
            } else {
                note = note.replacingFirst(#"<pitch>[\s\S]*?</pitch>"#, with: "<rest></rest>")
                note = note.removingAll(#"<accidental[^>]*>[\s\S]*?</accidental>"#)
                note = note.removingAll(#"<tie [^>]*>\s*</tie>"#)
                note = note.removingAll(#"<tied [^>]*>\s*</tied>"#)
            }
        }
        // Lengths may have rescaled the part's durations: find the note again.
        guard let current = elementRange("note", id: id) else { throw Failure.notFound }
        xml.replaceSubrange(current, with: note)
    }

    /// Sets a note's duration in divisions, doubling the part's divisions first when
    /// the length needs finer steps (a sixteenth where a quarter was 1).
    private mutating func setDuration(_ note: inout String, quarters: Double, at position: String.Index) throws {
        var divisions = Context(xml: xml, upTo: position).divisions
        var value = quarters * Double(divisions)
        var factor = 1
        while value != value.rounded() && factor < 64 {
            factor *= 2
            value *= 2
        }
        if factor > 1 {
            scaleDivisions(of: position, by: factor, in: &note)
            divisions *= factor
        }
        let duration = Int(quarters * Double(divisions))
        if note.contains("<duration>") {
            note = note.replacingFirst(#"<duration>[^<]*</duration>"#, with: "<duration>\(duration)</duration>")
        }
    }

    /// Multiplies every duration in the part holding `position` (and the note being
    /// edited) so a finer length fits in whole divisions.
    private mutating func scaleDivisions(of position: String.Index, by factor: Int, in note: inout String) {
        guard let partStart = xml.range(of: "<part ", options: .backwards, range: xml.startIndex..<position)?.lowerBound,
              let partEnd = xml.range(of: "</part>", range: position..<xml.endIndex)?.upperBound else { return }
        var part = String(xml[partStart..<partEnd])
        for tag in ["divisions", "duration"] {
            part = part.replacingMatches(of: "<\(tag)>(\\d+)</\(tag)>") { "<\(tag)>\(Int($0)! * factor)</\(tag)>" }
        }
        xml.replaceSubrange(partStart..<partEnd, with: part)
        note = note.replacingMatches(of: "<duration>(\\d+)</duration>") { "<duration>\(Int($0)! * factor)</duration>" }
    }

    /// Ties the note to the next note of the same voice, or unties it.
    private mutating func toggleTie(from range: Range<String.Index>) throws {
        var note = String(xml[range])
        let voice = note.firstMatch(#"<voice>([^<]*)</voice>"#) ?? "1"
        guard let next = nextNote(after: range.upperBound, voice: voice) else { throw Failure.cannot }
        var following = String(xml[next])
        if note.contains(#"<tie type="start">"#) {
            note = note.removingAll(#"<tie type="start">\s*</tie>"#).removingAll(#"<tied type="start">\s*</tied>"#)
            following = following.removingAll(#"<tie type="stop">\s*</tie>"#).removingAll(#"<tied type="stop">\s*</tied>"#)
        } else {
            note = note.inserting(#"<tie type="start"></tie>"#, after: ["</duration>"])
            note = Self.addNotation(#"<tied type="start"></tied>"#, to: note)
            following = following.inserting(#"<tie type="stop"></tie>"#, after: ["</duration>"])
            following = Self.addNotation(#"<tied type="stop"></tied>"#, to: following)
        }
        // Replace the later one first, so the earlier range stays valid.
        xml.replaceSubrange(next, with: following)
        xml.replaceSubrange(range, with: note)
    }

    private func nextNote(after position: String.Index, voice: String) -> Range<String.Index>? {
        var search = position
        while let start = xml.range(of: "<note", range: search..<xml.endIndex),
              let end = xml.range(of: "</note>", range: start.upperBound..<xml.endIndex) {
            if let partEnd = xml.range(of: "</part>", range: position..<xml.endIndex), partEnd.lowerBound < start.lowerBound { return nil }
            let candidate = String(xml[start.lowerBound..<end.upperBound])
            let candidateVoice = candidate.firstMatch(#"<voice>([^<]*)</voice>"#) ?? "1"
            if candidateVoice == voice, !candidate.contains("<chord"), !candidate.contains("<grace"), !candidate.contains("<rest") {
                return start.lowerBound..<end.upperBound
            }
            search = end.upperBound
        }
        return nil
    }

    // MARK: Bars

    mutating func add(_ addition: BarAddition, toBar id: String) throws {
        guard let range = elementRange("measure", id: id) else { throw Failure.notFound }
        var bar = String(xml[range])
        switch addition {
        case .rehearsal(let text):
            bar = Self.insertDirection("<rehearsal>\(Self.escape(text))</rehearsal>", into: bar)
        case .tempo(let text):
            bar = Self.insertDirection(#"<words font-weight="bold">"# + Self.escape(text) + "</words>", into: bar)
        case .fermata:
            guard let last = bar.range(of: "<note", options: .backwards),
                  let end = bar.range(of: "</note>", range: last.upperBound..<bar.endIndex) else { throw Failure.cannot }
            let note = Self.addNotation(#"<fermata type="upright"></fermata>"#, to: String(bar[last.lowerBound..<end.upperBound]))
            bar.replaceSubrange(last.lowerBound..<end.upperBound, with: note)
        }
        xml.replaceSubrange(range, with: bar)
    }

    /// Bars whose notes don't add up to the time signature, by id: a pickup bar
    /// (`implicit="yes"`) and the last bar of a part may be short.
    func barsThatDontAddUp() -> [String] {
        var result: [String] = []
        var search = xml.startIndex
        while let start = xml.range(of: "<measure", range: search..<xml.endIndex),
              let end = xml.range(of: "</measure>", range: start.upperBound..<xml.endIndex) {
            let bar = String(xml[start.lowerBound..<end.upperBound])
            search = end.upperBound
            let context = Context(xml: xml, upTo: end.lowerBound)
            let expected = Double(context.divisions) * 4 * Double(context.beats) / Double(context.beatType)
            var sums: [String: Double] = [:]
            var position = bar.startIndex
            while let noteStart = bar.range(of: "<note", range: position..<bar.endIndex),
                  let noteEnd = bar.range(of: "</note>", range: noteStart.upperBound..<bar.endIndex) {
                let note = String(bar[noteStart.lowerBound..<noteEnd.upperBound])
                position = noteEnd.upperBound
                if note.contains("<chord") || note.contains("<grace") { continue }
                let voice = note.firstMatch(#"<voice>([^<]*)</voice>"#) ?? "1"
                sums[voice, default: 0] += Double(note.firstMatch(#"<duration>([^<]*)</duration>"#) ?? "0") ?? 0
            }
            let implicit = bar.prefix(200).contains(#"implicit="yes""#)
            let lastInPart = xml[end.upperBound...].trimmingPrefixWhitespace().hasPrefix("</part>")
            let wholeBarRest = sums.count == 1 && bar.contains(#"<rest measure="yes""#)
            let wrong = sums.values.contains { $0 > expected + 0.001 || (!implicit && !lastInPart && !wholeBarRest && $0 < expected - 0.001) }
            if wrong, let id = bar.firstMatch(#"<measure[^>]*\bid="([^"]+)""#) { result.append(id) }
        }
        return result
    }

    // MARK: Helpers

    func elementRange(_ element: String, id: String) -> Range<String.Index>? {
        let pattern = "<\(element)\\b[^>]*\\bid=\"\(NSRegularExpression.escapedPattern(for: id))\""
        guard let start = xml.range(of: pattern, options: .regularExpression),
              let end = xml.range(of: "</\(element)>", range: start.upperBound..<xml.endIndex) else { return nil }
        return start.lowerBound..<end.upperBound
    }

    private static func dotted(_ dots: Int) -> Double {
        dots == 0 ? 1 : dots == 1 ? 1.5 : 1.75
    }

    private static func insertDirection(_ content: String, into bar: String) -> String {
        let direction = #"<direction placement="above"><direction-type>"# + content + "</direction-type></direction>"
        var bar = bar
        if let firstNote = bar.range(of: "<note") {
            bar.insert(contentsOf: direction, at: firstNote.lowerBound)
        } else if let end = bar.range(of: "</measure>", options: .backwards) {
            bar.insert(contentsOf: direction, at: end.lowerBound)
        }
        return bar
    }

    private static func addNotation(_ element: String, to note: String) -> String {
        var note = note
        if let end = note.range(of: "</notations>") {
            note.insert(contentsOf: element, at: end.lowerBound)
        } else if let end = note.range(of: "</note>", options: .backwards) {
            note.insert(contentsOf: "<notations>\(element)</notations>", at: end.lowerBound)
        }
        return note
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// What's in force at a place in the file: the last divisions, key, time and clef
/// before it, within its part.
nonisolated private struct Context {
    var divisions = 1
    var fifths = 0
    var beats = 4
    var beatType = 4
    var clef = "G"

    init(xml: String, upTo position: String.Index) {
        let partStart = xml.range(of: "<part ", options: .backwards, range: xml.startIndex..<position)?.lowerBound ?? xml.startIndex
        let before = String(xml[partStart..<position])
        if let d = before.lastMatch(#"<divisions>(\d+)</divisions>"#).flatMap(Int.init) { divisions = d }
        if let f = before.lastMatch(#"<fifths>(-?\d+)</fifths>"#).flatMap(Int.init) { fifths = f }
        if let b = before.lastMatch(#"<beats>(\d+)</beats>"#).flatMap(Int.init) { beats = b }
        if let t = before.lastMatch(#"<beat-type>(\d+)</beat-type>"#).flatMap(Int.init) { beatType = t }
        if let c = before.lastMatch(#"<sign>([A-Z]+)</sign>"#) { clef = c }
    }
}

nonisolated private struct Pitch {
    var step: Character
    var alter: Int
    var octave: Int

    static let steps: [Character] = ["C", "D", "E", "F", "G", "A", "B"]

    init?(_ note: String) {
        guard let s = note.firstMatch(#"<step>([A-G])</step>"#)?.first,
              let o = note.firstMatch(#"<octave>(-?\d+)</octave>"#).flatMap(Int.init) else { return nil }
        step = s
        octave = o
        alter = note.firstMatch(#"<alter>(-?\d+(?:\.\d+)?)</alter>"#).flatMap(Double.init).map { Int($0.rounded()) } ?? 0
    }

    init(step: Character, alter: Int, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }

    /// The line in the middle of the staff, for a rest turned into a note.
    static func middleLine(clef: String) -> Pitch {
        switch clef {
        case "F": Pitch(step: "D", alter: 0, octave: 3)
        case "C": Pitch(step: "C", alter: 0, octave: 4)
        default: Pitch(step: "B", alter: 0, octave: 4)
        }
    }

    /// Moved by scale steps, taking the key's sharp or flat for the new step.
    func moved(_ by: Int, fifths: Int) -> Pitch {
        let index = Pitch.steps.firstIndex(of: step)! + by
        let octaveShift = Int((Double(index) / 7).rounded(.down))
        let newStep = Pitch.steps[((index % 7) + 7) % 7]
        return Pitch(step: newStep, alter: Pitch.keyAlter(newStep, fifths: fifths), octave: octave + octaveShift)
    }

    static func keyAlter(_ step: Character, fifths: Int) -> Int {
        let sharps: [Character] = ["F", "C", "G", "D", "A", "E", "B"]
        if fifths > 0 { return sharps.prefix(fifths).contains(step) ? 1 : 0 }
        if fifths < 0 { return sharps.reversed().prefix(-fifths).contains(step) ? -1 : 0 }
        return 0
    }

    var xml: String {
        "<pitch><step>\(step)</step>" + (alter != 0 ? "<alter>\(alter)</alter>" : "") + "<octave>\(octave)</octave></pitch>"
    }
}

/// Echoes the document, giving notes and bars without an id one of their own.
nonisolated private final class IDWriter: NSObject, XMLParserDelegate {
    var output = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
    private var notes = 0
    private var bars = 0

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        var attributes = attributes
        if element == "note", attributes["id"] == nil { notes += 1; attributes["id"] = "ls-n\(notes)" }
        if element == "measure", attributes["id"] == nil { bars += 1; attributes["id"] = "ls-m\(bars)" }
        output += "<" + element
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            output += " \(key)=\"\(MusicXMLEdit.escape(value).replacingOccurrences(of: "\"", with: "&quot;"))\""
        }
        output += ">"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        output += MusicXMLEdit.escape(string)
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        output += "</\(element)>"
    }
}

nonisolated extension String {
    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    func lastMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: self, range: NSRange(startIndex..., in: self)).last,
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }

    func replacingFirst(_ pattern: String, with replacement: String) -> String {
        guard let range = range(of: pattern, options: .regularExpression) else { return self }
        var copy = self
        copy.replaceSubrange(range, with: replacement)
        return copy
    }

    func removingAll(_ pattern: String) -> String {
        replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    func replacingMatches(of pattern: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        var result = self
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)).reversed() {
            guard let whole = Range(match.range, in: result), let group = Range(match.range(at: 1), in: self) else { continue }
            result.replaceSubrange(whole, with: transform(String(self[group])))
        }
        return result
    }

    /// Inserts after the first of the given closing tags that occurs.
    func inserting(_ text: String, after tags: [String]) -> String {
        var copy = self
        for tag in tags {
            if let range = copy.range(of: tag, options: .backwards) {
                copy.insert(contentsOf: text, at: range.upperBound)
                return copy
            }
        }
        if let open = copy.range(of: ">") { copy.insert(contentsOf: text, at: open.upperBound) }
        return copy
    }

    func trimmingPrefixWhitespace() -> Substring {
        self.drop { $0.isWhitespace }
    }
}

nonisolated extension Substring {
    func trimmingPrefixWhitespace() -> Substring { self.drop { $0.isWhitespace } }
}
