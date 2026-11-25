import Foundation

/// Fixes being made to one converted piece: the iPad's Fix Notes (`FixSession`) for
/// macOS 12, where Observation isn't available. The edits themselves are the shared
/// `MusicXMLEdit`; keep the two in step when one gains a change.
@MainActor
final class FixModel: ObservableObject {
    @Published private(set) var edit: MusicXMLEdit
    @Published private(set) var version = Date()
    @Published private(set) var wrongBars: [String] = []
    @Published private(set) var barNumbers: [String: Int] = [:]
    @Published var selectedNote: String? { didSet { readSelection() } }
    @Published var selectedBar: String?
    @Published private(set) var selectedXML: String?
    @Published var problem: String?
    private var undoStack: [String] = []
    /// Changes since the music was last saved.
    @Published private(set) var unsaved = false
    static let undoLimit = 100

    init(xml: String) {
        edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(xml))
        wrongBars = edit.barsThatDontAddUp()
        barNumbers = edit.barNumbers()
    }

    var xml: String { edit.xml }
    var canUndo: Bool { !undoStack.isEmpty }

    func markSaved() { unsaved = false }

    func apply(_ change: MusicXMLEdit.NoteChange) {
        guard let id = selectedNote else { return }
        perform(problem: change == .toggleTie ? String(localized: "This note has no next note to tie to.") : String(localized: "This note can't be changed that way.")) {
            try $0.edit(note: id, change)
        }
    }

    func add(_ addition: MusicXMLEdit.BarAddition) {
        guard let id = selectedBar else { return }
        perform(problem: String(localized: "This bar has no note to put a fermata on.")) { try $0.add(addition, toBar: id) }
    }

    func deleteNote() {
        guard let id = selectedNote else { return }
        perform(problem: String(localized: "This note can't be changed that way.")) { try $0.delete(note: id) }
    }

    func addNote() {
        var added: String?
        if let id = selectedNote {
            perform(problem: String(localized: "This note can't be changed that way.")) { added = try $0.addNote(after: id) }
        } else if let bar = selectedBar {
            perform(problem: String(localized: "This note can't be changed that way.")) { added = try $0.addNote(toBar: bar) }
        }
        if let added { selectedNote = added }
    }

    var selectedWords: [MusicXMLEdit.Words] { selectedBar.map { edit.words(inBar: $0) } ?? [] }

    func setWords(at index: Int, to text: String) {
        guard let bar = selectedBar else { return }
        perform(problem: String(localized: "These words can't be changed.")) { try $0.setWords(inBar: bar, at: index, to: text) }
    }

    func addDynamic(_ mark: String) {
        guard let bar = selectedBar else { return }
        let note = selectedNote
        perform(problem: String(localized: "This bar can't be changed that way.")) { try $0.addDynamic(mark, bar: bar, at: note) }
    }

    func setTime(beats: Int, beatType: Int) {
        guard let bar = selectedBar else { return }
        perform(problem: String(localized: "This bar can't be changed that way.")) { try $0.setTime(beats: beats, beatType: beatType, bar: bar) }
    }

    var selectedBarIsRest: Bool {
        guard let bar = selectedBar, let range = edit.elementRange("measure", id: bar) else { return false }
        let xml = String(edit.xml[range])
        return xml.count(of: #"<note[\s>]"#) == xml.count(of: #"<rest[\s>/]"#)
    }

    var selectedRestBars: Int {
        guard let bar = selectedBar, let range = edit.elementRange("measure", id: bar) else { return 1 }
        return String(edit.xml[range]).firstMatch(#"<multiple-rest\b[^>]*>(\d+)</multiple-rest>"#).flatMap(Int.init) ?? 1
    }

    func setRestBars(_ count: Int) {
        guard let bar = selectedBar else { return }
        perform(problem: String(localized: "Only a bar of rests can become a rest of several bars.")) { try $0.setRestBars(count, bar: bar) }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        edit = MusicXMLEdit(xml: last)
        changed()
    }

    /// The last change gave music the engraver can't read: it is taken back.
    func rejectLastChange() {
        guard let last = undoStack.popLast() else { return }
        edit = MusicXMLEdit(xml: last)
        changed()
        problem = String(localized: "That change couldn't be shown, so it was undone.")
    }

    private func perform(problem message: String, _ body: (inout MusicXMLEdit) throws -> Void) {
        var copy = edit
        do {
            try body(&copy)
            guard copy.xml != edit.xml else { problem = nil; return }
            undoStack.append(edit.xml)
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
            edit = copy
            problem = nil
            changed()
        } catch {
            problem = message
        }
    }

    private func changed() {
        version = Date()
        unsaved = true
        wrongBars = edit.barsThatDontAddUp()
        barNumbers = edit.barNumbers()
        if let note = selectedNote, edit.elementRange("note", id: note) == nil { selectedNote = nil }
        if let bar = selectedBar, edit.elementRange("measure", id: bar) == nil { selectedBar = nil }
        readSelection()
    }

    private func readSelection() {
        guard let id = selectedNote, let range = edit.elementRange("note", id: id) else { selectedXML = nil; return }
        selectedXML = String(edit.xml[range])
    }

    // MARK: The selected note

    var selectedIsRest: Bool { selectedXML?.contains("<rest") ?? false }
    var selectedHasDot: Bool { selectedXML?.contains("<dot>") ?? false }
    var selectedIsTied: Bool { selectedXML?.contains(#"<tie type="start">"#) ?? false }
    var selectedLength: MusicXMLEdit.Length? {
        selectedXML?.firstMatch(#"<type>([^<]*)</type>"#).flatMap(MusicXMLEdit.Length.init)
    }

    /// The selected note as a musician would say it ("B flat, quarter"), or "Rest, half".
    var selectedSummary: String? {
        guard let note = selectedXML else { return nil }
        let length = selectedLength.map(Self.name)
        if note.contains("<rest") {
            return [String(localized: "Rest"), length].compactMap { $0 }.joined(separator: ", ")
        }
        guard let step = note.firstMatch(#"<step>([A-G])</step>"#) else { return length }
        let alter = note.firstMatch(#"<alter>(-?\d+)</alter>"#).flatMap(Int.init) ?? 0
        let name: String = switch alter {
        case 1: String(localized: "\(step) sharp")
        case -1: String(localized: "\(step) flat")
        default: step
        }
        return [name, length].compactMap { $0 }.joined(separator: ", ")
    }

    nonisolated static func name(_ length: MusicXMLEdit.Length) -> String {
        switch length {
        case .whole: String(localized: "Whole")
        case .half: String(localized: "Half")
        case .quarter: String(localized: "Quarter")
        case .eighth: String(localized: "Eighth")
        case .sixteenth: String(localized: "Sixteenth")
        }
    }
}
