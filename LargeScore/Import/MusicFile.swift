import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// MusicXML as a plain XML file (.musicxml).
    nonisolated static let musicXML = UTType(importedAs: "com.recordare.musicxml.uncompressed", conformingTo: .xml)
    /// Compressed MusicXML (.mxl).
    nonisolated static let compressedMusicXML = UTType(importedAs: "com.recordare.musicxml", conformingTo: .data)
    /// Everything that may hold MusicXML. Any file is allowed, since an .mxl can arrive
    /// typed as a ZIP or as another app's type; the contents are checked when read.
    nonisolated static let musicFiles: [UTType] = [.musicXML, .compressedMusicXML, .xml, .zip, .data]
}

/// A MusicXML file read and understood: the score as text, its title, composer and parts.
nonisolated struct MusicFile: Sendable, Identifiable {
    enum Failure: Error, Equatable {
        /// Not MusicXML at all.
        case notMusicXML
        /// MusicXML written measure by measure, which the engraver doesn't read.
        case timewise
        /// A compressed file that couldn't be opened.
        case damaged
        /// A PDF on its own: it has to be converted to MusicXML first.
        case pdf
    }

    var id = UUID()
    var fileName: String
    var xml: String
    var title: String
    var composer: String?
    var arranger: String?
    var parts: [ScorePart]
    /// The program that wrote the file, from its `encoding` (for example
    /// "Audiveris 5.11.0" or "MuseScore 4.7.7").
    var software: String?
    /// The PDF it was converted from, when that PDF came with it.
    var pdf: Data?

    /// Programs that read printed music and so may have got something wrong.
    static let recognisers = ["audiveris", "playscore", "smartscore", "photoscore", "scanscore", "maestria", "sharpeye"]

    /// Read from a PDF or a scan by a recognition program: to be checked against
    /// the original before playing from it.
    var isRecognised: Bool {
        guard let software = software?.lowercased() else { return false }
        return Self.recognisers.contains { software.contains($0) }
    }

    /// Reads a file from any source: compressed or not, UTF-8 or UTF-16.
    static func read(_ data: Data, fileName: String) throws -> MusicFile {
        let xml = try text(of: data)
        guard xml.contains("<score-partwise") else {
            throw xml.contains("<score-timewise") ? Failure.timewise : Failure.notMusicXML
        }
        let info = Metadata.read(xml)
        let fallback = (fileName as NSString).deletingPathExtension
        let title = [info.workTitle, info.movementTitle, info.creditTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback
        return MusicFile(fileName: fileName, xml: xml, title: title,
                         composer: info.composer, arranger: info.arranger,
                         parts: PartSplitter.parts(in: xml), software: info.software)
    }

    static func text(of data: Data) throws -> String {
        try declaringUTF8(decoded(data))
    }

    /// The text is kept as UTF-8 from here on; a declaration saying otherwise would
    /// make the parsers misread it.
    private static func declaringUTF8(_ text: String) -> String {
        guard let end = text.range(of: "?>"), text.hasPrefix("<?xml") || text.hasPrefix("\u{FEFF}<?xml") else { return text }
        let prolog = String(text[..<end.upperBound])
        let fixed = prolog.replacingOccurrences(of: #"encoding\s*=\s*["'][^"']*["']"#, with: #"encoding="UTF-8""#, options: .regularExpression)
        return fixed + text[end.upperBound...]
    }

    private static func decoded(_ data: Data) throws -> String {
        if data.starts(with: [0x50, 0x4B]) {
            return try text(of: unzipped(data))
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data, encoding: .utf16) else { throw Failure.notMusicXML }
            return text
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw Failure.notMusicXML
        }
        return text
    }

    /// The score inside an .mxl: the file META-INF/container.xml names, else the first
    /// MusicXML file outside META-INF.
    private static func unzipped(_ data: Data) throws -> Data {
        let entries: [ZipReader.Entry]
        do { entries = try ZipReader.entries(in: data) } catch { throw Failure.damaged }
        var target: ZipReader.Entry?
        if let container = entries.first(where: { $0.name == "META-INF/container.xml" }),
           let text = try? String(decoding: ZipReader.contents(of: container, in: data), as: UTF8.self),
           let range = text.range(of: #"full-path="([^"]+)""#, options: .regularExpression) {
            let path = text[range].dropFirst("full-path=\"".count).dropLast()
            target = entries.first { $0.name == path }
        }
        target = target ?? entries.first {
            !$0.name.hasPrefix("META-INF/") && ($0.name.hasSuffix(".musicxml") || $0.name.hasSuffix(".xml"))
        }
        guard let target else { throw Failure.damaged }
        do { return try ZipReader.contents(of: target, in: data) } catch { throw Failure.damaged }
    }

    /// Bars in the first part: notes are fixed to bar numbers, so a change here
    /// means they may have moved.
    var barCount: Int {
        guard let start = xml.range(of: "<part "), let end = xml.range(of: "</part>", range: start.upperBound..<xml.endIndex) else { return 0 }
        return xml[start.lowerBound..<end.lowerBound].components(separatedBy: "<measure ").count - 1
    }

    /// The part to offer first: the first one any of `instruments` plays, trying them
    /// in the player's order; else the only part.
    func suggestedPart(for instruments: [Instrument]) -> ScorePart? {
        for instrument in instruments {
            if let match = parts.first(where: { instrument.matches($0) }) { return match }
        }
        return parts.count == 1 ? parts.first : nil
    }
}

/// Title, composer and arranger, from the places notation programs write them.
nonisolated private final class Metadata: NSObject, XMLParserDelegate {
    var workTitle: String?
    var movementTitle: String?
    var creditTitle: String?
    var composer: String?
    var arranger: String?
    var software: String?

    private var path: [String] = []
    private var creatorType: String?
    private var creditType: String?
    private var firstCreditWords: String?
    private var text = ""

    static func read(_ xml: String) -> Metadata {
        let reader = Metadata()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = reader
        parser.parse()
        if reader.creditTitle == nil { reader.creditTitle = reader.firstCreditWords }
        return reader
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "part-list" { parser.abortParsing(); return }
        path.append(element)
        text = ""
        if element == "creator" { creatorType = attributes["type"] }
        if element == "credit" { creditType = nil }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "work-title": workTitle = value
        case "software": if software == nil, !value.isEmpty { software = value }
        case "movement-title": movementTitle = value
        case "creator":
            if creatorType == "composer", composer == nil, !value.isEmpty { composer = value }
            if creatorType == "arranger", arranger == nil, !value.isEmpty { arranger = value }
        case "credit-type": creditType = value
        case "credit-words":
            if creditType == "title", creditTitle == nil, !value.isEmpty { creditTitle = value }
            if creditType == "composer", composer == nil, !value.isEmpty { composer = value }
            if firstCreditWords == nil, !value.isEmpty { firstCreditWords = value }
        default: break
        }
        path.removeLast()
        text = ""
    }
}

extension Instrument {
    /// Words notation programs use for this instrument's parts, in English, Dutch,
    /// German, French and Italian, and the start of its MusicXML sound ids.
    nonisolated var partWords: [String] {
        switch self {
        case .flute: ["flute", "fluit", "flöte", "flauto", "fl."]
        case .oboe: ["oboe", "hobo", "hautbois", "ob."]
        case .clarinet: ["clarinet", "klarinet", "klarinette", "clarinette", "clarinetto", "cl.", "kl."]
        case .bassoon: ["bassoon", "fagot", "fagott", "basson", "fagotto", "bsn", "fg."]
        case .saxophone: ["sax"]
        case .horn: ["horn", "hoorn", "cor ", "corno", "hn."]
        case .trumpet: ["trumpet", "trompet", "trompete", "trompette", "tromba", "tpt"]
        case .trombone: ["trombone", "posaune", "tbn"]
        case .tuba: ["tuba"]
        case .violin: ["violin", "viool", "violine", "violon", "violino", "vln", "vl."]
        case .viola: ["viola", "altviool", "bratsche", "alto", "vla"]
        case .cello: ["cello", "violoncel", "vc."]
        case .doubleBass: ["double bass", "contrabass", "contrabas", "kontrabass", "contrebasse", "cb."]
        case .piano: ["piano", "klavier", "pno"]
        case .organ: ["organ", "orgel", "orgue", "organo"]
        case .voice: ["voice", "soprano", "sopraan", "tenor", "zang", "choir", "koor"]
        case .other: []
        }
    }

    nonisolated var soundPrefixes: [String] {
        switch self {
        case .flute: ["wind.flutes.flute"]
        case .oboe: ["wind.reed.oboe"]
        case .clarinet: ["wind.reed.clarinet"]
        case .bassoon: ["wind.reed.bassoon"]
        case .saxophone: ["wind.reed.saxophone"]
        case .horn: ["brass.french-horn", "brass.horn"]
        case .trumpet: ["brass.trumpet"]
        case .trombone: ["brass.trombone"]
        case .tuba: ["brass.tuba"]
        case .violin: ["strings.violin"]
        case .viola: ["strings.viola"]
        case .cello: ["strings.cello"]
        case .doubleBass: ["strings.contrabass"]
        case .piano: ["keyboard.piano"]
        case .organ: ["keyboard.organ"]
        case .voice: ["voice."]
        case .other: []
        }
    }

    nonisolated func matches(_ part: ScorePart) -> Bool {
        if part.sounds.contains(where: { sound in soundPrefixes.contains { sound.hasPrefix($0) } }) { return true }
        // Contrabassoon and bass clarinet are other instruments: the sound id says so
        // when present; by name, a longer word that contains ours doesn't count.
        let names = ([part.name, part.abbreviation] + part.instrumentNames).map { $0.lowercased() }
        let exclusions = ["contrabassoon", "contrafagot", "kontrafagott", "bass clarinet", "basklarinet", "bassklarinette"]
        if names.contains(where: { name in exclusions.contains { name.contains($0) } }) { return false }
        if self == .violin, names.contains(where: { $0.contains("violoncel") }) { return false }
        let englishHorn = ["english horn", "engelse hoorn", "cor anglais", "englischhorn", "corno inglese"]
        if self == .horn, names.contains(where: { name in englishHorn.contains { name.contains($0) } }) { return false }
        return names.contains { name in partWords.contains { name.contains($0) } }
    }
}
