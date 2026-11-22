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

    /// Dynamics a part can carry, as MusicXML names them.
    static let dynamics = ["ppp", "pp", "p", "mp", "mf", "f", "ff", "fff", "fp", "sf", "sfz", "fz"]

    /// A dynamic under the music, at the given note or else at the bar's start.
    mutating func addDynamic(_ mark: String, bar id: String, at note: String?) throws {
        guard Self.dynamics.contains(mark) else { throw Failure.cannot }
        let direction = #"<direction placement="below"><direction-type><dynamics><"# + mark + "></" + mark + "></dynamics></direction-type></direction>"
        if let note, let range = elementRange("note", id: note) {
            guard !String(xml[range]).contains("<chord") else { throw Failure.cannot }
            xml.insert(contentsOf: direction, at: range.lowerBound)
            return
        }
        guard let range = elementRange("measure", id: id) else { throw Failure.notFound }
        var bar = String(xml[range])
        if let first = bar.range(of: #"<note[\s>]"#, options: .regularExpression) {
            bar.insert(contentsOf: direction, at: first.lowerBound)
        } else if let end = bar.range(of: "</measure>", options: .backwards) {
            bar.insert(contentsOf: direction, at: end.lowerBound)
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

    // MARK: Adding and deleting notes

    /// Removes a note or rest. A chord's lowest note hands the chord on to the next one.
    mutating func delete(note id: String) throws {
        guard let range = elementRange("note", id: id) else { throw Failure.notFound }
        let note = String(xml[range])
        if !note.contains("<chord"), let next = followingNote(range.upperBound), String(xml[next]).contains("<chord") {
            let promoted = String(xml[next]).removingAll(#"<chord>\s*</chord>"#)
            xml.replaceSubrange(next, with: promoted)
        }
        xml.removeSubrange(range)
    }

    /// A copy of the note (or rest) after it and its chord, without ties, slurs,
    /// marks or words, for a note the recognition missed. Returns the new note's id.
    @discardableResult
    mutating func addNote(after id: String) throws -> String {
        guard let range = elementRange("note", id: id) else { throw Failure.notFound }
        var end = range.upperBound
        while let next = followingNote(end), String(xml[next]).contains("<chord") { end = next.upperBound }
        let newID = nextID("ls-n")
        var copy = String(xml[range])
            .removingAll(#"<chord>\s*</chord>"#)
            .removingAll(#"<tie [^>]*>\s*</tie>"#)
            .removingAll(#"<notations>[\s\S]*?</notations>"#)
            .removingAll(#"<lyric\b[^>]*>[\s\S]*?</lyric>"#)
            .removingAll(#"<beam\b[^>]*>[^<]*</beam>"#)
            .removingAll(#"<accidental[^>]*>[\s\S]*?</accidental>"#)
        copy = copy.replacingFirst(#"\bid="[^"]*""#, with: "id=\"\(newID)\"")
        copy = copy.replacingFirst(#"\s(default-x|relative-x)="[^"]*""#, with: "")
        xml.insert(contentsOf: copy, at: end)
        return newID
    }

    /// A quarter note on the staff's middle line, for a bar the recognition left
    /// empty. Returns its id.
    @discardableResult
    mutating func addNote(toBar id: String) throws -> String {
        guard let range = elementRange("measure", id: id) else { throw Failure.notFound }
        let context = Context(xml: xml, upTo: range.upperBound)
        let newID = nextID("ls-n")
        let note = "<note id=\"\(newID)\">" + Pitch.middleLine(clef: context.clef).xml
            + "<duration>\(context.divisions)</duration><voice>1</voice><type>quarter</type></note>"
        var bar = String(xml[range])
        if let backup = bar.range(of: "<backup") {
            bar.insert(contentsOf: note, at: backup.lowerBound)
        } else if let end = bar.range(of: "</measure>", options: .backwards) {
            bar.insert(contentsOf: note, at: end.lowerBound)
        }
        xml.replaceSubrange(range, with: bar)
        return newID
    }

    private func followingNote(_ position: String.Index) -> Range<String.Index>? {
        let rest = xml[position...]
        let trimmed = rest.drop { $0.isWhitespace }
        guard trimmed.hasPrefix("<note"), let end = xml.range(of: "</note>", range: trimmed.startIndex..<xml.endIndex) else { return nil }
        return trimmed.startIndex..<end.upperBound
    }

    /// An id not yet in the file: the prefix and one more than the highest number used with it.
    func nextID(_ prefix: String) -> String {
        var highest = 0
        let pattern = "id=\"" + NSRegularExpression.escapedPattern(for: prefix) + "(\\d+)\""
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                if let r = Range(match.range(at: 1), in: xml), let n = Int(xml[r]) { highest = max(highest, n) }
            }
        }
        return "\(prefix)\(highest + 1)"
    }

    // MARK: Words

    struct Words: Equatable, Identifiable {
        var index: Int
        var text: String
        var id: Int { index }
    }

    /// Words written in a bar, in file order: directions, rehearsal marks and lyrics.
    func words(inBar id: String) -> [Words] {
        guard let range = elementRange("measure", id: id) else { return [] }
        let bar = String(xml[range])
        return Self.wordRanges(in: bar).enumerated().map { index, item in
            Words(index: index, text: Self.unescape(String(bar[item.text])))
        }
    }

    /// Changes words in a bar; empty text removes them (and a direction left with nothing).
    mutating func setWords(inBar id: String, at index: Int, to text: String) throws {
        guard let range = elementRange("measure", id: id) else { throw Failure.notFound }
        var bar = String(xml[range])
        let items = Self.wordRanges(in: bar)
        guard items.indices.contains(index) else { throw Failure.notFound }
        let item = items[index]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            bar.replaceSubrange(item.text, with: Self.escape(trimmed))
        } else if item.lyric {
            bar.removeSubrange(item.whole)
        } else {
            bar.removeSubrange(item.whole)
            bar = bar.removingAll(#"<direction-type>\s*</direction-type>"#)
            // A direction with no direction-type left is gone too (sound and offset with it).
            bar = bar.replacingMatches(of: #"(<direction(?:\s[^>]*)?>(?:(?!<direction-type)[\s\S])*?</direction>)"#) { _ in "" }
        }
        xml.replaceSubrange(range, with: bar)
    }

    private struct WordRange {
        var whole: Range<String.Index>
        var text: Range<String.Index>
        var lyric: Bool
    }

    private static func wordRanges(in bar: String) -> [WordRange] {
        let pattern = #"<(words|rehearsal)\b[^>]*>([^<]*)</\1>|<lyric\b[^>]*>(?:(?!</lyric>)[\s\S])*?<text\b[^>]*>([^<]*)</text>[\s\S]*?</lyric>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: bar, range: NSRange(bar.startIndex..., in: bar)).compactMap { match in
            guard let whole = Range(match.range, in: bar) else { return nil }
            if let text = Range(match.range(at: 2), in: bar) { return WordRange(whole: whole, text: text, lyric: false) }
            if let text = Range(match.range(at: 3), in: bar) { return WordRange(whole: whole, text: text, lyric: true) }
            return nil
        }.filter { !bar[$0.text].trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Time signatures and rests

    /// Sets the time signature from this bar on.
    mutating func setTime(beats: Int, beatType: Int, bar id: String) throws {
        guard let range = elementRange("measure", id: id) else { throw Failure.notFound }
        var bar = String(xml[range])
        let time = "<time><beats>\(beats)</beats><beat-type>\(beatType)</beat-type></time>"
        if bar.range(of: #"<time\b[^>]*>[\s\S]*?</time>"#, options: .regularExpression) != nil {
            bar = bar.replacingFirst(#"<time\b[^>]*>[\s\S]*?</time>"#, with: time)
        } else {
            bar = Self.addAttribute(time, before: ["<staves", "<part-symbol", "<instruments", "<clef", "<staff-details", "<transpose", "<measure-style"], to: bar)
        }
        xml.replaceSubrange(range, with: bar)
    }

    /// How many bars of rest start at this bar (a multi-bar rest such as "7"): adds
    /// or removes empty bars after it to match. Only for bars holding nothing but rests.
    mutating func setRestBars(_ count: Int, bar id: String) throws {
        guard count >= 1, count <= 999, let range = elementRange("measure", id: id) else { throw Failure.notFound }
        var bar = String(xml[range])
        guard Self.onlyRests(bar) else { throw Failure.cannot }
        let current = bar.firstMatch(#"<multiple-rest\b[^>]*>(\d+)</multiple-rest>"#).flatMap(Int.init) ?? 1

        // The bars after this one that belong to it now.
        var group: [Range<String.Index>] = []
        var position = range.upperBound
        while group.count < current - 1, let next = nextMeasure(after: position) {
            guard Self.onlyRests(String(xml[next])) else { break }
            group.append(next)
            position = next.upperBound
        }
        let insertAt = group.last?.upperBound ?? range.upperBound
        let delta = count - 1 - group.count

        // Shift later bar numbers first, while the ranges still hold.
        if delta != 0 { renumber(after: insertAt, by: delta) }
        if delta > 0 {
            let context = Context(xml: xml, upTo: range.upperBound)
            let duration = context.divisions * 4 * context.beats / context.beatType
            let lastNumber = Int(String(xml[group.last ?? range]).firstMatch(#"<measure\b[^>]*\bnumber="(\d+)""#) ?? "") ?? 0
            var added = ""
            var ids = self
            for n in 1...delta {
                let newID = ids.nextID("ls-m")
                let measure = "<measure id=\"\(newID)\" number=\"\(lastNumber + n)\"><note><rest measure=\"yes\"></rest><duration>\(duration)</duration><voice>1</voice></note></measure>"
                ids.xml += measure // reserve the id
                added += measure
            }
            xml.insert(contentsOf: added, at: insertAt)
        } else if delta < 0 {
            for removed in group.suffix(-delta).reversed() { xml.removeSubrange(removed) }
        }

        // The first bar says how many.
        guard let start = elementRange("measure", id: id) else { throw Failure.notFound }
        bar = String(xml[start])
        bar = bar.removingAll(#"<measure-style>\s*<multiple-rest\b[^>]*>\d+</multiple-rest>\s*</measure-style>"#)
        bar = bar.removingAll(#"<attributes>\s*</attributes>"#)
        if count > 1 {
            bar = Self.addAttribute("<measure-style><multiple-rest>\(count)</multiple-rest></measure-style>", before: [], to: bar)
        }
        xml.replaceSubrange(start, with: bar)
    }

    private static func onlyRests(_ bar: String) -> Bool {
        bar.count(of: #"<note[\s>]"#) == bar.count(of: #"<rest[\s>/]"#)
    }

    private func nextMeasure(after position: String.Index) -> Range<String.Index>? {
        guard let start = xml.range(of: "<measure", range: position..<xml.endIndex),
              let partEnd = xml.range(of: "</part>", range: position..<xml.endIndex),
              start.lowerBound < partEnd.lowerBound,
              let end = xml.range(of: "</measure>", range: start.upperBound..<xml.endIndex) else { return nil }
        return start.lowerBound..<end.upperBound
    }

    private mutating func renumber(after position: String.Index, by delta: Int) {
        let partEnd = xml.range(of: "</part>", range: position..<xml.endIndex)?.lowerBound ?? xml.endIndex
        let tail = String(xml[position..<partEnd]).replacingMatches(of: #"(<measure\b[^>]*\bnumber="\d+")"#) { tag in
            tag.replacingMatches(of: #"number="(\d+)""#) { "number=\"\(Int($0)! + delta)\"" }
        }
        xml.replaceSubrange(position..<partEnd, with: tail)
    }

    /// Puts an element in the bar's attributes before the first of the given tags
    /// (MusicXML's order), making the attributes if the bar has none.
    private static func addAttribute(_ element: String, before tags: [String], to bar: String) -> String {
        var bar = bar
        if let open = bar.range(of: "<attributes>"), let close = bar.range(of: "</attributes>", range: open.upperBound..<bar.endIndex) {
            let inside = open.upperBound..<close.lowerBound
            for tag in tags {
                if let at = bar.range(of: tag, range: inside) {
                    bar.insert(contentsOf: element, at: at.lowerBound)
                    return bar
                }
            }
            bar.insert(contentsOf: element, at: close.lowerBound)
            return bar
        }
        let attributes = "<attributes>\(element)</attributes>"
        if let print = bar.range(of: "</print>") {
            bar.insert(contentsOf: attributes, at: print.upperBound)
        } else if let open = bar.range(of: ">") {
            bar.insert(contentsOf: attributes, at: open.upperBound)
        }
        return bar
    }

    /// Each bar's number counted from 1 within its part (a pickup bar is 0), the way
    /// parts number them; every bar of a multi-bar rest counts.
    func barNumbers() -> [String: Int] {
        var result: [String: Int] = [:]
        var search = xml.startIndex
        var count = 0
        var first = true
        while let start = xml.range(of: #"<(measure|part)(?:\s[^>]*)?>"#, options: .regularExpression, range: search..<xml.endIndex) {
            let tag = String(xml[start])
            search = start.upperBound
            if tag.hasPrefix("<part ") || tag == "<part>" { count = 0; first = true; continue }
            guard tag.hasPrefix("<measure") else { continue }
            if first && tag.contains(#"implicit="yes""#) { count = -1 }
            first = false
            count += 1
            if let id = tag.firstMatch(#"\bid="([^"]+)""#) { result[id] = count }
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
    func count(of pattern: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: self, range: NSRange(startIndex..., in: self)) ?? 0
    }

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
