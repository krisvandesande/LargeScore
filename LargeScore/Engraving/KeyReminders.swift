import Foundation

/// The key's sharps and flats printed on every note they apply to, for a player who
/// loses the key halfway down a line when reading slowly at a large size. Works on
/// the MusicXML before engraving: a note the key alters, written without an accidental
/// of its own, gets one.
nonisolated enum KeyReminders {
    static func apply(_ xml: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<fifths>\s*(-?\d+)\s*</fifths>|<part[\s>]|<note[\s>][\s\S]*?</note>"#) else { return xml }
        let text = xml as NSString
        var result = ""
        var last = 0
        var fifths = 0
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: text.length)) {
            let token = text.substring(with: match.range)
            if token.hasPrefix("<fifths") {
                fifths = Int(text.substring(with: match.range(at: 1))) ?? 0
                continue
            }
            if token.hasPrefix("<part") {
                fifths = 0
                continue
            }
            guard let reminded = remind(token, fifths: fifths) else { continue }
            result += text.substring(with: NSRange(location: last, length: match.range.location - last)) + reminded
            last = match.range.location + match.range.length
        }
        guard last > 0 else { return xml }
        return result + text.substring(from: last)
    }

    /// The note with the key's accidental added, or nil when it needs none.
    static func remind(_ note: String, fifths: Int) -> String? {
        guard fifths != 0, !note.contains("<accidental"), !note.contains("<rest"),
              // A note tied over from the one before keeps the first one's accidental.
              !note.contains(#"<tie type="stop""#),
              let step = note.firstMatch(#"<step>\s*([A-G])\s*</step>"#)?.first else { return nil }
        let alter = note.firstMatch(#"<alter>\s*(-?\d+)\s*</alter>"#).flatMap(Int.init) ?? 0
        let inKey = keyAlter(step, fifths: fifths)
        guard inKey != 0, alter == inKey else { return nil }
        let accidental = inKey > 0 ? "<accidental>sharp</accidental>" : "<accidental>flat</accidental>"
        return note.inserting(accidental, after: ["</dot>", "</type>", "</voice>", "</duration>"])
    }

    static func keyAlter(_ step: Character, fifths: Int) -> Int {
        let sharps: [Character] = ["F", "C", "G", "D", "A", "E", "B"]
        if fifths > 0 { return sharps.prefix(min(fifths, 7)).contains(step) ? 1 : 0 }
        return sharps.reversed().prefix(min(-fifths, 7)).contains(step) ? -1 : 0
    }
}
