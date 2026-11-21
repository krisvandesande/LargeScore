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
    var boldLines: Bool { didSet { store.set(boldLines, forKey: Key.boldLines) } }
    var pageColour: PageColour { didSet { store.set(pageColour.rawValue, forKey: Key.pageColour) } }
    var halfPageTurns: Bool { didSet { store.set(halfPageTurns, forKey: Key.halfPageTurns) } }
    var instrument: Instrument? { didSet { store.set(instrument?.rawValue, forKey: Key.instrument) } }
    var onboardingDone: Bool { didSet { store.set(onboardingDone, forKey: Key.onboardingDone) } }

    var staffHeight: CGFloat { Self.staffHeights[sizeStep] }

    private let store: UserDefaults

    private enum Key {
        static let sizeStep = "sizeStep"
        static let boldLines = "boldLines"
        static let pageColour = "pageColour"
        static let halfPageTurns = "halfPageTurns"
        static let instrument = "instrument"
        static let onboardingDone = "onboardingDone"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        let step = store.object(forKey: Key.sizeStep) as? Int ?? Self.defaultSizeStep
        sizeStep = min(max(step, 0), Self.staffHeights.count - 1)
        boldLines = store.object(forKey: Key.boldLines) as? Bool ?? true
        pageColour = store.string(forKey: Key.pageColour).flatMap(PageColour.init) ?? .light
        halfPageTurns = store.bool(forKey: Key.halfPageTurns)
        instrument = store.string(forKey: Key.instrument).flatMap(Instrument.init)
        onboardingDone = store.bool(forKey: Key.onboardingDone)
    }

    func layoutRequest(for area: CGSize) -> LayoutRequest {
        LayoutRequest(pageSize: area, staffHeight: staffHeight, bold: boldLines)
    }

    /// The scheme the page is drawn in, given the iPad's own.
    func pageScheme(system: ColorScheme) -> ColorScheme {
        switch pageColour {
        case .light: .light
        case .dark: .dark
        case .system: system
        }
    }
}

/// The instruments offered in setup. Chooses the sample's clef now, and the part to
/// preselect when music is added.
nonisolated enum Instrument: String, CaseIterable, Identifiable {
    case flute, oboe, clarinet, bassoon, saxophone, horn, trumpet, trombone, tuba
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
