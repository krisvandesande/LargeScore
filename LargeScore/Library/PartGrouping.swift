import Foundation

/// A piece's name, part number and key as its title gives them: "Alexander's Ragtime
/// Band-Trombone_2" is Alexander's Ragtime Band, part 2. Used to keep the parts a
/// player doesn't play out of the way when another part of the same piece is there.
/// Free of SwiftUI so it can be tested on real names.
nonisolated enum PartGrouping {
    /// Words that start a part's description in a file or title.
    static let instrumentWords = ["trombone", "tromboon", "trbn", "tromb", "trb", "tbn", "bariton", "barit",
                                  "euphonium", "euph", "posaune", "low brass", "stem"]

    struct Parsed: Equatable {
        /// The piece's own name, without the part.
        var name: String
        /// 1, 2, 3 or 4; nil when the title names no part.
        var part: Int?
        /// "bb", "c", "eb" when the title names a key; versions in other keys aren't
        /// the same part.
        var key: String?
    }

    static func parse(_ title: String) -> Parsed {
        let lower = title.lowercased()
        // The earliest instrument word that starts a word.
        var cut: String.Index?
        for word in instrumentWords {
            var search = lower.startIndex..<lower.endIndex
            while let found = lower.range(of: word, range: search) {
                let before = found.lowerBound == lower.startIndex ? " " : lower[lower.index(before: found.lowerBound)]
                if !before.isLetter, cut.map({ found.lowerBound < $0 }) ?? true { cut = found.lowerBound; break }
                search = found.upperBound..<lower.endIndex
            }
        }
        guard let cut else { return Parsed(name: tidy(title), part: nil, key: nil) }
        let name = tidy(String(title[..<cut]))
        let rest = String(lower[cut...])
        return Parsed(name: name.isEmpty ? tidy(title) : name, part: partNumber(in: rest), key: key(in: rest))
    }

    /// The first part number after the instrument word: digits, or I to IV.
    static func partNumber(in text: String) -> Int? {
        // Drop the key ("in bb") so its letters aren't read as a numeral.
        let cleaned = text.replacingOccurrences(of: #"\bin\s*(bb|eb|c|f|b)\b"#, with: " ", options: .regularExpression)
        if let match = cleaned.range(of: #"(?<![0-9])[1-4](?![0-9])"#, options: .regularExpression) {
            return Int(cleaned[match])
        }
        let romans = ["iv": 4, "iii": 3, "ii": 2, "i": 1]
        for (numeral, value) in romans.sorted(by: { $0.key.count > $1.key.count }) {
            if cleaned.range(of: #"(?<![a-z])\#(numeral)(?![a-z])"#, options: .regularExpression) != nil { return value }
        }
        return nil
    }

    static func key(in text: String) -> String? {
        guard let match = text.range(of: #"\b(bb|eb|c)\b"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    /// The name as people write it: "Alexander_s" was "Alexander's" before a file
    /// system took the apostrophe; other underscores were spaces; separators at the
    /// ends go.
    static func tidy(_ text: String) -> String {
        var out = text.replacingOccurrences(of: #"_([sS])\b"#, with: "'$1", options: .regularExpression)
        out = out.replacingOccurrences(of: "_", with: " ")
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " -–(._"))
    }

    /// Which pieces to show and which to keep aside as other parts. A piece is kept
    /// aside only when another version of it (same name and key) is the player's part;
    /// a piece that exists in one part only always shows, whatever its number.
    static func split<ID: Hashable>(_ pieces: [(id: ID, title: String)], myPart: Int) -> (shown: [ID], others: [ID]) {
        let parsed = pieces.map { (id: $0.id, info: parse($0.title)) }
        let groups = Dictionary(grouping: parsed) { "\($0.info.name.lowercased())|\($0.info.key ?? "")" }
        var aside = Set<ID>()
        for (_, members) in groups where members.count > 1 {
            guard members.contains(where: { $0.info.part == myPart }) else { continue }
            for member in members where member.info.part != nil && member.info.part != myPart { aside.insert(member.id) }
        }
        return (pieces.map(\.id).filter { !aside.contains($0) }, pieces.map(\.id).filter { aside.contains($0) })
    }
}
