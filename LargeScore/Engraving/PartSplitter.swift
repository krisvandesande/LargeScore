import Foundation

/// A part listed in a MusicXML file.
nonisolated struct ScorePart: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var abbreviation: String = ""
    /// `instrument-name` of each `score-instrument`.
    var instrumentNames: [String] = []
    /// `instrument-sound` ids, such as "wind.reed.bassoon".
    var sounds: [String] = []
}

/// Reads the parts of a partwise MusicXML file and writes a copy holding one of them.
nonisolated enum PartSplitter {
    static func parts(in musicXML: String) -> [ScorePart] {
        let reader = PartListReader()
        let parser = XMLParser(data: Data(musicXML.utf8))
        parser.delegate = reader
        parser.parse()
        return reader.parts
    }

    /// The file with every part but `partID` removed, from the part list and the music.
    static func keeping(partID: String, in musicXML: String) -> String? {
        keeping(partIDs: [partID], in: musicXML)
    }

    /// The file with only `partIDs`, in the file's own order.
    static func keeping(partIDs: [String], in musicXML: String) -> String? {
        let writer = PartFilter(keep: Set(partIDs))
        let parser = XMLParser(data: Data(musicXML.utf8))
        parser.delegate = writer
        guard parser.parse() else { return nil }
        return writer.output
    }
}

nonisolated private final class PartListReader: NSObject, XMLParserDelegate {
    var parts: [ScorePart] = []
    private var current: ScorePart?
    private var field: String?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "score-part":
            current = ScorePart(id: attributes["id"] ?? "", name: "")
        case "part-name", "part-abbreviation", "instrument-name", "instrument-sound":
            guard current != nil else { break }
            field = element
            text = ""
        case "part":
            parser.abortParsing()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field != nil { text += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "part-name": current?.name = value; field = nil
        case "part-abbreviation": current?.abbreviation = value; field = nil
        case "instrument-name": if !value.isEmpty { current?.instrumentNames.append(value) }; field = nil
        case "instrument-sound": if !value.isEmpty { current?.sounds.append(value) }; field = nil
        case "score-part":
            if let part = current { parts.append(part) }
            current = nil
        default:
            break
        }
    }
}

/// Echoes the document, skipping the `score-part` and `part` elements of other parts.
nonisolated private final class PartFilter: NSObject, XMLParserDelegate {
    let keep: Set<String>
    var output = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
    private var skipDepth = 0
    /// Kept parts met so far; marks for the whole ensemble stay on the first only.
    private var keptPartsSeen = 0
    /// Where a `direction` in a later part began in `output`, and whether it holds a
    /// rehearsal mark or tempo, which notation programs repeat in every part.
    private var directionStart: String.Index?
    private var directionIsShared = false

    init(keep: Set<String>) { self.keep = keep }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if skipDepth > 0 { skipDepth += 1; return }
        if (element == "score-part" || element == "part"), let id = attributes["id"], !keep.contains(id) {
            skipDepth = 1
            return
        }
        // The full score's brackets and braces would be drawn around what's left.
        if element == "part-group" {
            skipDepth = 1
            return
        }
        if element == "part" { keptPartsSeen += 1 }
        if element == "direction", keptPartsSeen > 1 {
            directionStart = output.endIndex
            directionIsShared = false
        }
        if directionStart != nil {
            if element == "rehearsal" || element == "metronome" { directionIsShared = true }
            if element == "sound", attributes["tempo"] != nil { directionIsShared = true }
        }
        var attributes = attributes
        // One part on its own needs no name before the first line; several keep theirs.
        if keep.count == 1, element == "part-name" || element == "part-abbreviation" { attributes["print-object"] = "no" }
        output += "<" + element
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            output += " \(key)=\"\(Self.escape(value, attribute: true))\""
        }
        output += ">"
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0 { output += Self.escape(string, attribute: false) }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if skipDepth > 0 { skipDepth -= 1; return }
        output += "</\(element)>"
        if element == "direction", let start = directionStart {
            if directionIsShared { output.removeSubrange(start...) }
            directionStart = nil
        }
    }

    static func escape(_ text: String, attribute: Bool) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if attribute { result = result.replacingOccurrences(of: "\"", with: "&quot;") }
        return result
    }
}
