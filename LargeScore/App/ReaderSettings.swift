import SwiftUI

/// How the music is shown. Kept on the device; every piece follows it.
@Observable
final class ReaderSettings {
    /// Staff heights in points, smallest to largest. Print on a 13-inch iPad is about 36.
    /// Pages up to 120 pt: past that, a bar of sixteenths is wider than an upright
    /// 13-inch iPad and Verovio crushes it (2026-11-24, measured on real parts). The
    /// larger sizes read the part as one line, a screen at a time (`OneLine`).
    static let staffHeights: [CGFloat] = [40, 48, 56, 64, 72, 80, 88, 100, 110, 120, 140, 165, 195, 230, 270]
    static let largestPageSize: CGFloat = 120

    /// One line instead of pages at this size.
    var readsAsOneLine: Bool { staffHeight > Self.largestPageSize }
    static let defaultSizeStep = 3

    enum PageColour: String, CaseIterable, Identifiable {
        case light, dark, yellowOnBlack, system
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .yellowOnBlack: "Yellow on Black"
            case .system: "Match iPad"
            }
        }
    }

    /// Pure yellow on black, the pairing many low-vision readers use: 19.6:1.
    static let yellowInk = Color(red: 1, green: 1, blue: 0)

    var sizeStep: Int { didSet { store.set(sizeStep, forKey: Key.sizeStep) } }
    /// Room between lines of music, in Verovio's half staff spaces: 0 to `maxLineGap`.
    var lineGap: Int { didSet { store.set(lineGap, forKey: Key.lineGap) } }
    static let maxLineGap = 6
    var boldLines: Bool { didSet { store.set(boldLines, forKey: Key.boldLines) } }
    var pageColour: PageColour { didSet { store.set(pageColour.rawValue, forKey: Key.pageColour) } }
    var halfPageTurns: Bool { didSet { store.set(halfPageTurns, forKey: Key.halfPageTurns) } }
    /// Repeats and jumps written out where they're played.
    var playingOrder: Bool { didSet { store.set(playingOrder, forKey: Key.playingOrder) } }
    /// A moment's tint on the first bar after a page turn, to find where to read.
    var markFirstBar: Bool { didSet { store.set(markFirstBar, forKey: Key.markFirstBar) } }
    /// The key's sharps and flats printed on every note they apply to.
    var keyReminders: Bool { didSet { store.set(keyReminders, forKey: Key.keyReminders) } }
    /// Pieces read at a size of their own (a busy one smaller, a sparse one larger),
    /// by piece id. Kept on this device, like the size itself.
    private(set) var pieceSizes: [String: Int] { didSet { store.set(pieceSizes, forKey: Key.pieceSizes) } }

    /// The size step a piece is read at: its own, else the one for every piece.
    func sizeStep(for piece: String?) -> Int {
        guard let piece, let own = pieceSizes[piece], Self.staffHeights.indices.contains(own) else { return sizeStep }
        return own
    }

    /// A size for one piece; nil goes back to the size every piece has.
    func setSize(_ step: Int?, for piece: String) {
        pieceSizes[piece] = step.map { min(max($0, 0), Self.staffHeights.count - 1) }
    }

    func staffHeight(for piece: String?) -> CGFloat { Self.staffHeights[sizeStep(for: piece)] }

    /// The reading settings a piece can have its own value for, besides its size.
    enum Choice: String, CaseIterable {
        case boldLines, pageColour, halfPageTurns, markFirstBar, playingOrder, keyReminders
    }

    /// Own values by piece id, then by `Choice`: "true", "false" or a page colour.
    /// A piece keeps only what differs from every piece's setting.
    private(set) var pieceChoices: [String: [String: String]] { didSet { store.set(pieceChoices, forKey: Key.pieceChoices) } }

    private func standard(_ choice: Choice) -> String {
        switch choice {
        case .boldLines: String(boldLines)
        case .pageColour: pageColour.rawValue
        case .halfPageTurns: String(halfPageTurns)
        case .markFirstBar: String(markFirstBar)
        case .playingOrder: String(playingOrder)
        case .keyReminders: String(keyReminders)
        }
    }

    private func value(_ choice: Choice, for piece: String?) -> String {
        piece.flatMap { pieceChoices[$0]?[choice.rawValue] } ?? standard(choice)
    }

    func bool(_ choice: Choice, for piece: String?) -> Bool { value(choice, for: piece) == "true" }

    func pageColour(for piece: String?) -> PageColour { PageColour(rawValue: value(.pageColour, for: piece)) ?? pageColour }

    /// A value for one piece; the same as every piece's removes the piece's own.
    func set(_ choice: Choice, to raw: String, for piece: String) {
        var own = pieceChoices[piece] ?? [:]
        if raw == standard(choice) { own.removeValue(forKey: choice.rawValue) } else { own.updateValue(raw, forKey: choice.rawValue) }
        if own.isEmpty { pieceChoices.removeValue(forKey: piece) } else { pieceChoices.updateValue(own, forKey: piece) }
    }

    func set(_ choice: Choice, to on: Bool, for piece: String) { set(choice, to: String(on), for: piece) }

    func isOwn(_ choice: Choice, for piece: String) -> Bool { pieceChoices[piece]?[choice.rawValue] != nil }

    /// Whether a piece reads differently from every other: its size or any setting.
    func hasOwnSettings(_ piece: String) -> Bool { pieceSizes[piece] != nil || pieceChoices[piece] != nil }

    /// Back to the settings every piece has.
    func clearOwnSettings(_ piece: String) {
        pieceSizes.removeValue(forKey: piece)
        pieceChoices.removeValue(forKey: piece)
    }
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
        static let lineGap = "lineGap"
        static let boldLines = "boldLines"
        static let pageColour = "pageColour"
        static let halfPageTurns = "halfPageTurns"
        static let playingOrder = "playingOrder"
        static let markFirstBar = "markFirstBar"
        static let pieceSizes = "pieceSizes"
        static let keyReminders = "keyReminders"
        static let pieceChoices = "pieceChoices"
        static let instrument = "instrument"
        static let instruments = "instruments"
        static let onboardingDone = "onboardingDone"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        let step = store.object(forKey: Key.sizeStep) as? Int ?? Self.defaultSizeStep
        sizeStep = min(max(step, 0), Self.staffHeights.count - 1)
        boldLines = store.object(forKey: Key.boldLines) as? Bool ?? true
        // Earlier versions kept Less, Normal or More: their gaps were 0, 1 and 4.
        let earlier: Int? = switch store.string(forKey: Key.lineSpacing) {
        case "less": 0
        case "more": 4
        case "normal": 1
        default: nil
        }
        lineGap = min(max(store.object(forKey: Key.lineGap) as? Int ?? earlier ?? 1, 0), Self.maxLineGap)
        // The page follows the iPad: white on black in dark mode, unless chosen otherwise.
        pageColour = store.string(forKey: Key.pageColour).flatMap(PageColour.init) ?? .system
        halfPageTurns = store.bool(forKey: Key.halfPageTurns)
        playingOrder = store.bool(forKey: Key.playingOrder)
        markFirstBar = store.object(forKey: Key.markFirstBar) as? Bool ?? true
        keyReminders = store.bool(forKey: Key.keyReminders)
        pieceSizes = store.dictionary(forKey: Key.pieceSizes) as? [String: Int] ?? [:]
        pieceChoices = store.dictionary(forKey: Key.pieceChoices) as? [String: [String: String]] ?? [:]
        if let list = store.string(forKey: Key.instruments) {
            instruments = list.split(separator: " ").compactMap { Instrument(rawValue: String($0)) }
        } else {
            // Build 1 kept one instrument.
            instruments = store.string(forKey: Key.instrument).flatMap(Instrument.init).map { [$0] } ?? []
        }
        onboardingDone = store.bool(forKey: Key.onboardingDone)
    }

    func layoutRequest(for area: CGSize, centred: Bool = false, piece: String? = nil) -> LayoutRequest {
        let height = staffHeight(for: piece)
        return LayoutRequest(pageSize: area, staffHeight: height, bold: bool(.boldLines, for: piece), lineGap: lineGap, centred: centred,
                             oneLine: height > Self.largestPageSize, playingOrder: bool(.playingOrder, for: piece),
                             keyReminders: bool(.keyReminders, for: piece))
    }

    /// Bold also thickens the glyphs a little: 7% of a staff space all round.
    var glyphWeight: CGFloat { glyphWeight(for: nil) }

    func glyphWeight(for piece: String?) -> CGFloat { bool(.boldLines, for: piece) ? staffHeight(for: piece) / 4 * 0.07 : 0 }

    /// The scheme the page is drawn in, given the iPad's own.
    func pageScheme(system: ColorScheme, piece: String? = nil) -> ColorScheme {
        switch pageColour(for: piece) {
        case .light: .light
        case .dark, .yellowOnBlack: .dark
        case .system: system
        }
    }

    /// The colour the music is drawn in, given the iPad's own scheme.
    func pageInk(system: ColorScheme, piece: String? = nil) -> Color {
        if pageColour(for: piece) == .yellowOnBlack { return Self.yellowInk }
        return pageScheme(system: system, piece: piece) == .dark ? .white : .black
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
