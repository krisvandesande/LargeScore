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

    // MARK: Checking, one thing at a time

    /// Something to check against the PDF: what Audiveris often gets wrong.
    enum CheckItem: Hashable {
        case key, time
        case bar(String)
    }

    /// Items passed with Looks Right; they stay passed while the piece is open.
    @Published private(set) var passed: Set<CheckItem> = []
    /// A bar the music pane should scroll to; it clears it when done.
    @Published var revealBar: String?

    /// What is left to check, in reading order: the key, the time, then each bar that
    /// doesn't add up. A fixed item drops off by itself.
    var checkItems: [CheckItem] {
        var items: [CheckItem] = []
        if keyMissing { items.append(.key) }
        if timeMissing { items.append(.time) }
        items += wrongBars.map(CheckItem.bar)
        return items.filter { !passed.contains($0) }
    }

    /// The bar an item is about: the first bar for the key and time.
    func bar(of item: CheckItem) -> String? {
        if case .bar(let id) = item { return id }
        return firstBar
    }

    /// Shows an item: its bar selected and scrolled to.
    func show(_ item: CheckItem) {
        guard let bar = bar(of: item) else { return }
        if selectedBar != bar { selectedNote = nil }
        selectedBar = bar
        revealBar = bar
    }

    func pass(_ item: CheckItem) {
        passed.insert(item)
    }

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

    /// The time signature at the selected bar, written "3/4".
    var currentTime: String {
        guard let bar = selectedBar else { return "" }
        let time = edit.time(atBar: bar)
        return "\(time.beats)/\(time.beatType)"
    }

    /// The selected note's sharp, flat or natural, as it sounds.
    var selectedAccidental: MusicXMLEdit.Accidental? {
        guard let note = selectedXML, !note.contains("<rest") else { return nil }
        switch note.firstMatch(#"<alter>(-?\d+)</alter>"#).flatMap(Int.init) ?? 0 {
        case 1: return .sharp
        case -1: return .flat
        default: return .natural
        }
    }

    /// No key signature was read: about a quarter of Audiveris's conversions, and
    /// the notes then lack the key's sharps or flats until it is set.
    var keyMissing: Bool { !edit.xml.contains("<fifths>") }
    /// No time signature was read.
    var timeMissing: Bool { !edit.xml.contains("<beats>") }

    /// The key at the selected bar, or at the start when no bar is selected.
    var currentKey: Int { selectedBar.map { edit.key(atBar: $0) } ?? edit.firstKey }

    /// Sets the key from the selected bar on (from the start when none is selected),
    /// spelling the notes by it: for music Audiveris read with the wrong key or none.
    func setKey(_ fifths: Int, fromStart: Bool = false) {
        let bar = fromStart ? nil : selectedBar
        guard let id = bar ?? edit.xml.firstMatch(#"<measure\b[^>]*\bid="([^"]+)""#) else { return }
        perform(problem: String(localized: "The key couldn't be set here.")) { try $0.setKey(fifths, fromBar: id) }
    }

    var currentClef: MusicXMLEdit.Clef {
        guard let bar = selectedBar ?? firstBar else { return .treble }
        return edit.clef(atBar: bar)
    }

    private var firstBar: String? { edit.xml.firstMatch(#"<measure\b[^>]*\bid="([^"]+)""#) }

    /// Sets the clef from the selected bar (or the start), the notes staying on their lines.
    func setClef(_ clef: MusicXMLEdit.Clef, fromStart: Bool = false) {
        guard let id = (fromStart ? nil : selectedBar) ?? firstBar else { return }
        perform(problem: String(localized: "The clef couldn't be set here.")) { try $0.setClef(clef, fromBar: id) }
    }

    /// Transpose as one change (one Undo): the key it's in set first if it was read
    /// wrongly, then moved for the other instrument, then on to the chosen key.
    func transpose(nowKey: Int, transposition: Transposition, toKey: Int) {
        let first = edit.xml.firstMatch(#"<measure\b[^>]*\bid="([^"]+)""#)
        perform(problem: String(localized: "The music couldn't be transposed.")) { edit in
            if nowKey != edit.firstKey, let first { try edit.setKey(nowKey, fromBar: first) }
            if !transposition.isNothing { edit.transpose(for: transposition) }
            let reached = edit.firstKey
            if toKey != reached {
                edit.transpose(toKey: toKey, up: MusicXMLEdit.nearerIsUp(from: reached, to: toKey))
            }
        }
    }

    /// Rewrites the part for another instrument: interval, key and clef.
    func transpose(for transposition: Transposition) {
        perform(problem: String(localized: "The music couldn't be transposed.")) { $0.transpose(for: transposition) }
    }

    /// Moves all the music to another key.
    func transpose(toKey fifths: Int, up: Bool) {
        perform(problem: String(localized: "The music couldn't be transposed.")) { $0.transpose(toKey: fifths, up: up) }
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
    var selectedSummary: String? { selectedXML.flatMap { Self.summary(of: $0) } }

    /// What the selected note would become with a change, said as `selectedSummary`
    /// says it: shown while a note is dragged, before the change is made.
    func preview(_ change: MusicXMLEdit.NoteChange) -> String? {
        guard let id = selectedNote else { return nil }
        var copy = edit
        guard (try? copy.edit(note: id, change)) != nil, let range = copy.elementRange("note", id: id) else { return nil }
        return Self.summary(of: String(copy.xml[range]))
    }

    static func summary(of note: String) -> String? {
        let length = note.firstMatch(#"<type>([^<]*)</type>"#).flatMap(MusicXMLEdit.Length.init).map(Self.name)
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
