import SwiftUI

/// How the music is shown. Kept on the device; every piece follows it.
@Observable
final class ReaderSettings {
    /// Staff heights in points, smallest to largest. Print on a 13-inch iPad is about 36.
    static let staffHeights: [CGFloat] = [40, 48, 56, 64, 72, 80, 88]
    static let defaultSizeStep = 3

    enum PageColour: String, CaseIterable, Identifiable {
        case light, dark, system
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .system: "Match iPad"
            }
        }
    }

    var sizeStep: Int { didSet { store.set(sizeStep, forKey: Key.sizeStep) } }
    var lineSpacing: LineSpacing { didSet { store.set(lineSpacing.rawValue, forKey: Key.lineSpacing) } }
    var boldLines: Bool { didSet { store.set(boldLines, forKey: Key.boldLines) } }
    var pageColour: PageColour { didSet { store.set(pageColour.rawValue, forKey: Key.pageColour) } }
    var halfPageTurns: Bool { didSet { store.set(halfPageTurns, forKey: Key.halfPageTurns) } }
    /// Everything the player plays, in the order chosen. The first sets the sample's clef.
    var instruments: [Instrument] {
        didSet { store.set(instruments.map(\.rawValue).joined(separator: " "), forKey: Key.instruments) }
    }
    var instrument: Instrument? { instruments.first }
    var onboardingDone: Bool { didSet { store.set(onboardingDone, forKey: Key.onboardingDone) } }

    var staffHeight: CGFloat { Self.staffHeights[sizeStep] }

    private let store: UserDefaults

    private enum Key {
        static let sizeStep = "sizeStep"
        static let lineSpacing = "lineSpacing"
        static let boldLines = "boldLines"
        static let pageColour = "pageColour"
        static let halfPageTurns = "halfPageTurns"
        static let instrument = "instrument"
        static let instruments = "instruments"
        static let onboardingDone = "onboardingDone"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        let step = store.object(forKey: Key.sizeStep) as? Int ?? Self.defaultSizeStep
        sizeStep = min(max(step, 0), Self.staffHeights.count - 1)
        boldLines = store.object(forKey: Key.boldLines) as? Bool ?? true
        lineSpacing = store.string(forKey: Key.lineSpacing).flatMap(LineSpacing.init) ?? .normal
        // The page follows the iPad: white on black in dark mode, unless chosen otherwise.
        pageColour = store.string(forKey: Key.pageColour).flatMap(PageColour.init) ?? .system
        halfPageTurns = store.bool(forKey: Key.halfPageTurns)
        if let list = store.string(forKey: Key.instruments) {
            instruments = list.split(separator: " ").compactMap { Instrument(rawValue: String($0)) }
        } else {
            // Build 1 kept one instrument.
            instruments = store.string(forKey: Key.instrument).flatMap(Instrument.init).map { [$0] } ?? []
        }
        onboardingDone = store.bool(forKey: Key.onboardingDone)
    }

    func layoutRequest(for area: CGSize, centred: Bool = false) -> LayoutRequest {
        LayoutRequest(pageSize: area, staffHeight: staffHeight, bold: boldLines, lineGap: lineSpacing.gap, centred: centred)
    }

    /// Bold also thickens the glyphs a little: 7% of a staff space all round.
    var glyphWeight: CGFloat { boldLines ? staffHeight / 4 * 0.07 : 0 }

    /// The scheme the page is drawn in, given the iPad's own.
    func pageScheme(system: ColorScheme) -> ColorScheme {
        switch pageColour {
        case .light: .light
        case .dark: .dark
        case .system: system
        }
    }
}

/// The room between lines of music.
nonisolated enum LineSpacing: String, CaseIterable, Identifiable {
    case less, normal, more
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .less: "Less"
        case .normal: "Normal"
        case .more: "More"
        }
    }

    /// Half staff spaces added between lines.
    var gap: Int {
        switch self {
        case .less: 0
        case .normal: 1
        case .more: 4
        }
    }
}

/// The instruments offered in setup. Chooses the sample's clef now, and the part to
/// preselect when music is added.
nonisolated enum Instrument: String, CaseIterable, Identifiable {
    case flute, oboe, clarinet, bassoon, saxophone, horn, trumpet, trombone, baritone, tuba
    case violin, viola, cello, doubleBass, piano, organ, voice, other

    var id: String { rawValue }

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
