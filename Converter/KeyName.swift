import Foundation

/// A key signature as a player names it: "2 flats (B♭ major)", in Dutch
/// "2 mollen (Bes groot)".
enum KeyName {
    private static let english = ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"]
    private static let dutch = ["Ces", "Ges", "Des", "As", "Es", "Bes", "F", "C", "G", "D", "A", "E", "B", "Fis", "Cis"]

    static var isDutch: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("nl") == true }

    /// The major key with this signature.
    static func major(_ fifths: Int) -> String {
        let index = min(max(fifths + 7, 0), 14)
        return isDutch ? "\(dutch[index]) groot" : "\(english[index]) major"
    }

    static func signature(_ fifths: Int) -> String {
        switch fifths {
        case 0: String(localized: "No sharps or flats")
        case 1: String(localized: "1 sharp")
        case -1: String(localized: "1 flat")
        case let n where n > 1: String(localized: "\(n) sharps")
        default: String(localized: "\(-fifths) flats")
        }
    }

    static func name(_ fifths: Int) -> String { "\(signature(fifths)) (\(major(fifths)))" }
}

extension MusicXMLEdit.Clef {
    /// As players name it: in Dutch, by the note the clef shows (sol, fa, do).
    var name: String {
        switch self {
        case .treble: String(localized: "Treble Clef")
        case .bass: String(localized: "Bass Clef")
        case .alto: String(localized: "Alto Clef")
        case .tenor: String(localized: "Tenor Clef")
        }
    }
}
