import Foundation

/// The instrument a part is written for, by what its written C sounds as. Band
/// parts often come for another instrument than the one playing them (a baritone
/// playing the baritone sax part), so a piece can be read in another key.
nonisolated enum WrittenFor: String, CaseIterable, Identifiable, Sendable, Codable {
    case c, cBass, bFlat, eFlat, f

    var id: String { rawValue }

    /// Semitones the instrument sounds below what is written, within an octave.
    var soundsBelow: Int {
        switch self {
        case .c, .cBass: 0
        case .bFlat: 2
        case .eFlat: 9
        case .f: 7
        }
    }

    var bassClef: Bool { self == .cBass }

    var title: LocalizedStringResource {
        switch self {
        case .c: "C (flute, oboe, violin)"
        case .cBass: "C, bass clef (trombone, euphonium, tuba)"
        case .bFlat: "B♭ (clarinet, trumpet, tenor sax, baritone)"
        case .eFlat: "E♭ (alto and baritone sax, E♭ horn)"
        case .f: "F (horn)"
        }
    }
}

/// Reading a part written for one instrument on another: the nearest interval
/// that keeps the sound, an octave either way if asked, and the clef changed
/// between bass and treble when the two instruments read different clefs.
nonisolated struct Transposition: Hashable, Sendable {
    var from: WrittenFor
    var to: WrittenFor
    var octaves: Int = 0

    /// Semitones to move every written note.
    var semitones: Int {
        var steps = to.soundsBelow - from.soundsBelow
        if steps > 6 { steps -= 12 }
        if steps < -6 { steps += 12 }
        // Treble-clef band instruments read an octave above the bass-clef part.
        if from.bassClef && !to.bassClef { steps += 12 }
        if !from.bassClef && to.bassClef { steps -= 12 }
        return steps + octaves * 12
    }

    var changesClef: Bool { from.bassClef != to.bassClef }

    var isNothing: Bool { semitones == 0 && !changesClef }

    private static let simple: [(quality: String, number: Int)] = [
        ("P", 1), ("m", 2), ("M", 2), ("m", 3), ("M", 3), ("P", 4),
        ("A", 4), ("P", 5), ("m", 6), ("M", 6), ("m", 7), ("M", 7),
    ]

    /// The interval as Verovio takes it ("+P4", "-M2", "+M9"), or nil for none.
    var interval: String? {
        let s = semitones
        guard s != 0 else { return nil }
        let size = abs(s)
        let (quality, number) = Self.simple[size % 12]
        let name = quality + String(number + 7 * (size / 12))
        return (s < 0 ? "-" : "+") + name
    }

    /// In words: "Up a fourth", "Down a second", "Up a ninth".
    var description: String {
        let s = semitones
        guard s != 0 else { return String(localized: "As written") }
        let size = abs(s)
        let number = Self.simple[size % 12].number + 7 * (size / 12)
        let name: String = switch number {
        case 2: String(localized: "second")
        case 3: String(localized: "third")
        case 4: String(localized: "fourth")
        case 5: String(localized: "fifth")
        case 6: String(localized: "sixth")
        case 7: String(localized: "seventh")
        case 8: String(localized: "octave")
        case 9: String(localized: "ninth")
        case 10: String(localized: "tenth")
        case 11: String(localized: "eleventh")
        case 12: String(localized: "twelfth")
        case 13: String(localized: "thirteenth")
        case 14: String(localized: "fourteenth")
        case 15: String(localized: "two octaves")
        default: String(localized: "sixteenth")
        }
        return s > 0 ? String(localized: "Up a \(name)") : String(localized: "Down a \(name)")
    }

    /// The clefs moved between bass and treble, when the instruments read different ones.
    /// Whole `<clef>` elements are rewritten: a G clef may leave out its line, and a
    /// tenor part's treble clef an octave down (`clef-octave-change`) would otherwise
    /// carry its octave over to the bass clef.
    func clefs(in xml: String) -> String {
        guard changesClef else { return xml }
        let (fromSign, toSign, toLine) = to.bassClef ? ("G", "F", "4") : ("F", "G", "2")
        guard let regex = try? NSRegularExpression(pattern: #"(<clef(?:\s[^>]*)?>)(.*?)(</clef>)"#, options: [.dotMatchesLineSeparators]) else { return xml }
        let text = xml as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: text.length)) {
            let body = text.substring(with: match.range(at: 2))
            guard body.range(of: #"<sign>\s*\#(fromSign)\s*</sign>"#, options: .regularExpression) != nil else { continue }
            result += text.substring(with: NSRange(location: last, length: match.range.location - last))
            result += text.substring(with: match.range(at: 1)) + "<sign>\(toSign)</sign><line>\(toLine)</line>" + "</clef>"
            last = match.range.location + match.range.length
        }
        guard last > 0 else { return xml }
        return result + text.substring(from: last)
    }
}
