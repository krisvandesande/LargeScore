import Foundation

/// A part listed in a MusicXML file.
nonisolated struct ScorePart: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
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
        let writer = PartFilter(keep: partID)
        let parser = XMLParser(data: Data(musicXML.utf8))
        parser.delegate = writer
        guard parser.parse() else { return nil }
        return writer.output
    }
}

nonisolated private final class PartListReader: NSObject, XMLParserDelegate {
    var parts: [ScorePart] = []
    private var currentID: String?
    private var inName = false
    private var name = ""

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch element {
        case "score-part":
            currentID = attributes["id"]
            name = ""
        case "part-name" where currentID != nil:
            inName = true
        case "part":
            parser.abortParsing()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inName { name += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        switch element {
        case "part-name":
            inName = false
        case "score-part":
            if let id = currentID {
                parts.append(ScorePart(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            currentID = nil
        default:
            break
        }
    }
}

/// Echoes the document, skipping the `score-part` and `part` elements of other parts.
nonisolated private final class PartFilter: NSObject, XMLParserDelegate {
    let keep: String
    var output = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
    private var skipDepth = 0

    init(keep: String) { self.keep = keep }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if skipDepth > 0 { skipDepth += 1; return }
        if (element == "score-part" || element == "part"), let id = attributes["id"], id != keep {
            skipDepth = 1
            return
        }
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
    }

    static func escape(_ text: String, attribute: Bool) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        if attribute { result = result.replacingOccurrences(of: "\"", with: "&quot;") }
        return result
    }
}
