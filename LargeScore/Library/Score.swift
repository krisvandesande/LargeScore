import Foundation
import SwiftData

/// A piece in the library: the whole MusicXML file as it arrived, and the part shown.
/// Shaped for CloudKit (every property optional or defaulted, no unique constraints),
/// so syncing can be switched on later without a migration.
@Model
final class Score {
    var id: UUID = UUID()
    var title: String = ""
    var composer: String?
    var arranger: String?
    /// The part ids shown, separated by spaces (XML ids hold none).
    var partID: String = ""
    /// Their names, for the card and VoiceOver.
    var partName: String = ""
    /// Parts in the file, kept so the library never parses music to draw a menu.
    var partCount: Int = 1
    @Attribute(.externalStorage) var musicXML: Data?
    var addedAt: Date = Date.now
    var changedAt: Date = Date.now
    var lastOpenedAt: Date?
    /// The music before the last Replace, kept so a wrong replace can be undone.
    @Attribute(.externalStorage) var previousMusicXML: Data?
    var previousPartID: String?
    var replacedAt: Date?
    /// The PDF the music was converted from, to compare against.
    @Attribute(.externalStorage) var pdf: Data?
    /// Converted by a recognition program and not yet checked against the PDF.
    var needsCheck: Bool = false
    /// A note in words about the whole piece.
    var note: String = ""
    /// Read in another key: what the part is written for and what plays it
    /// (`WrittenFor` raw values), and octaves up or down on top.
    var transposeFrom: String?
    var transposeTo: String?
    var transposeOctaves: Int = 0
    /// Bars in the first part shown, to warn when a new version changes them.
    var barCount: Int = 0
    /// Handwriting and marks, fixed to bars.
    @Relationship(deleteRule: .cascade, inverse: \Annotation.score)
    var annotations: [Annotation]? = []
    /// Its places in programmes, removed with the piece.
    @Relationship(deleteRule: .cascade, inverse: \ProgrammeEntry.score)
    var entries: [ProgrammeEntry]? = []

    var partIDs: [String] { partID.split(separator: " ").map(String.init) }

    private func show(_ parts: [ScorePart]) {
        partID = parts.map(\.id).joined(separator: " ")
        partName = parts.map(\.name).joined(separator: ", ")
    }

    init(file: MusicFile, parts: [ScorePart]) {
        title = file.title
        composer = file.composer
        arranger = file.arranger
        partID = parts.map(\.id).joined(separator: " ")
        partName = parts.map(\.name).joined(separator: ", ")
        partCount = file.parts.count
        musicXML = Data(file.xml.utf8)
        barCount = file.barCount
        pdf = file.pdf
        needsCheck = file.isRecognised
    }

    /// Takes the new version's music, keeping the old one for Restore. Parts chosen in
    /// the sheet win; otherwise the parts stay where the new file still has them (by
    /// id, else by name).
    func replaceMusic(with file: MusicFile, parts chosen: [ScorePart]) {
        let oldNames = partName.components(separatedBy: ", ")
        let oldIDs = partIDs
        previousMusicXML = musicXML
        previousPartID = partID
        replacedAt = .now
        musicXML = Data(file.xml.utf8)
        partCount = file.parts.count
        barCount = file.barCount
        // A fresh conversion is checked again; a version saved from a notation
        // program (a fix in MuseScore) counts as checked. The PDF stays for comparing.
        needsCheck = file.isRecognised
        pdf = file.pdf ?? pdf
        composer = file.composer ?? composer
        arranger = file.arranger ?? arranger
        let kept = file.parts.filter { oldIDs.contains($0.id) }
        let byName = file.parts.filter { oldNames.contains($0.name) }
        let parts = !chosen.isEmpty ? chosen : !kept.isEmpty ? kept : !byName.isEmpty ? byName : Array(file.parts.prefix(1))
        show(parts)
        changedAt = .now
    }

    func restorePrevious() {
        guard let previous = previousMusicXML else { return }
        musicXML = previous
        let parts = PartSplitter.parts(in: String(decoding: previous, as: UTF8.self))
        partCount = parts.count
        if let ids = previousPartID {
            let restored = ids.split(separator: " ").map(String.init)
            show(parts.filter { restored.contains($0.id) })
        }
        previousMusicXML = nil
        previousPartID = nil
        replacedAt = nil
        changedAt = .now
    }

    /// Fixes made in Large Score: a new version, with the one before kept for Restore.
    func saveFixes(_ xml: String) {
        previousMusicXML = musicXML
        previousPartID = partID
        replacedAt = .now
        musicXML = Data(xml.utf8)
        changedAt = .now
    }

    var transposition: Transposition? {
        get {
            guard let from = transposeFrom.flatMap(WrittenFor.init), let to = transposeTo.flatMap(WrittenFor.init) else { return nil }
            let t = Transposition(from: from, to: to, octaves: transposeOctaves)
            return t.isNothing ? nil : t
        }
        set {
            transposeFrom = newValue?.from.rawValue
            transposeTo = newValue?.to.rawValue
            transposeOctaves = newValue?.octaves ?? 0
            changedAt = .now
        }
    }

    func chooseParts(_ parts: [ScorePart]) {
        guard !parts.isEmpty else { return }
        show(parts)
        changedAt = .now
    }

    var parts: [ScorePart] {
        guard let musicXML else { return [] }
        return PartSplitter.parts(in: String(decoding: musicXML, as: UTF8.self))
    }

    /// What the reader opens.
    var piece: Piece {
        Piece(id: id.uuidString, title: title, composer: composer, partIDs: partIDs,
              source: .stored(musicXML ?? Data()), version: changedAt, transposition: transposition)
    }

    /// Same piece if the title and composer match, ignoring case and spacing.
    func isSamePiece(as file: MusicFile) -> Bool {
        Self.key(title, composer) == Self.key(file.title, file.composer)
    }

    nonisolated static func key(_ title: String, _ composer: String?) -> String {
        let clean: (String) -> String = {
            $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return clean(title) + "|" + clean(composer ?? "")
    }
}
