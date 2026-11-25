import Foundation

/// The instruments offered in setup. Chooses the sample's clef now, and the part to
/// preselect when music is added.
nonisolated enum Instrument: String, CaseIterable, Identifiable {
    case flute, oboe, clarinet, bassoon, saxophone, horn, trumpet, trombone, baritone, tuba
    case violin, viola, cello, doubleBass, piano, organ, voice, other

    var id: String { rawValue }

    @available(macOS 13, *)
    var title: LocalizedStringResource {
        switch self {
        case .flute: "Flute"
        case .oboe: "Oboe"
        case .clarinet: "Clarinet"
        case .bassoon: "Bassoon"
        case .saxophone: "Saxophone"
        case .horn: "Horn"
        case .trumpet: "Trumpet"
        case .trombone: "Trombone"
        case .baritone: "Baritone"
        case .tuba: "Tuba"
        case .violin: "Violin"
        case .viola: "Viola"
        case .cello: "Cello"
        case .doubleBass: "Double Bass"
        case .piano: "Piano"
        case .organ: "Organ"
        case .voice: "Voice"
        case .other: "Other"
        }
    }

    enum Clef { case treble, alto, bass }

    var clef: Clef {
        switch self {
        case .bassoon, .trombone, .tuba, .cello, .doubleBass: .bass
        case .viola: .alto
        default: .treble
        }
    }

    /// The bundled sample written in this instrument's clef.
    var sampleName: String {
        switch clef {
        case .treble: "evening-air-treble"
        case .alto: "evening-air-alto"
        case .bass: "evening-air"
        }
    }
}
