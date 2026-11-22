import SwiftUI

/// Fixes being made to one piece: the music as it stands, what can be undone, and
/// what is selected. Nothing reaches the library until Save Fixes.
@Observable
final class FixSession {
    private(set) var edit: MusicXMLEdit
    private var undoStack: [String] = []
    private(set) var version = Date()
    /// Bars whose notes don't add up to the time signature, worked out after each change.
    private(set) var wrongBars: [String] = []
    /// Each bar's number as parts count them (every bar of a multi-bar rest counts).
    private(set) var barNumbers: [String: Int] = [:]
    var selectedNote: String?
    var selectedBar: String?
    var problem: LocalizedStringResource?

    init(xml: String) {
        edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(xml))
        wrongBars = edit.barsThatDontAddUp()
        barNumbers = edit.barNumbers()
    }

    var hasChanges: Bool { !undoStack.isEmpty }
    var xml: String { edit.xml }

    func apply(_ change: MusicXMLEdit.NoteChange) {
        guard let id = selectedNote else { return }
        perform(problem: change == .toggleTie ? "This note has no next note to tie to." : "This note can't be changed that way.") {
            try $0.edit(note: id, change)
        }
    }

    func add(_ addition: MusicXMLEdit.BarAddition) {
        guard let id = selectedBar else { return }
        perform(problem: "This bar has no note to put a fermata on.") { try $0.add(addition, toBar: id) }
    }

    func deleteNote() {
        guard let id = selectedNote else { return }
        perform(problem: "This note can't be changed that way.") { try $0.delete(note: id) }
    }

    func addNote() {
        var added: String?
        if let id = selectedNote {
            perform(problem: "This note can't be changed that way.") { added = try $0.addNote(after: id) }
        } else if let bar = selectedBar {
            perform(problem: "This note can't be changed that way.") { added = try $0.addNote(toBar: bar) }
        }
        if let added { selectedNote = added }
    }

    var selectedWords: [MusicXMLEdit.Words] {
        selectedBar.map { edit.words(inBar: $0) } ?? []
    }

    func setWords(at index: Int, to text: String) {
        guard let bar = selectedBar else { return }
        perform(problem: "These words can't be changed.") { try $0.setWords(inBar: bar, at: index, to: text) }
    }

    func addDynamic(_ mark: String) {
        guard let bar = selectedBar else { return }
        let note = selectedNote
        perform(problem: "This bar can't be changed that way.") { try $0.addDynamic(mark, bar: bar, at: note) }
    }

    func setTime(beats: Int, beatType: Int) {
        guard let bar = selectedBar else { return }
        perform(problem: "This bar can't be changed that way.") { try $0.setTime(beats: beats, beatType: beatType, bar: bar) }
    }

    /// The bar holds only rests, so it can become a rest of several bars.
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
        perform(problem: "Only a bar of rests can become a rest of several bars.") { try $0.setRestBars(count, bar: bar) }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        edit = MusicXMLEdit(xml: last)
        changed()
    }

    private func perform(problem message: LocalizedStringResource, _ body: (inout MusicXMLEdit) throws -> Void) {
        var copy = edit
        do {
            try body(&copy)
            undoStack.append(edit.xml)
            edit = copy
            problem = nil
            changed()
        } catch {
            problem = message
        }
    }

    private func changed() {
        version = .now
        wrongBars = edit.barsThatDontAddUp()
        barNumbers = edit.barNumbers()
        if let note = selectedNote, edit.elementRange("note", id: note) == nil { selectedNote = nil }
        if let bar = selectedBar, edit.elementRange("measure", id: bar) == nil { selectedBar = nil }
    }

    // MARK: The selected note

    private var selectedXML: String? {
        guard let id = selectedNote, let range = edit.elementRange("note", id: id) else { return nil }
        return String(edit.xml[range])
    }

    var selectedIsRest: Bool { selectedXML?.contains("<rest") ?? false }
    var selectedHasDot: Bool { selectedXML?.contains("<dot>") ?? false }
    var selectedIsTied: Bool { selectedXML?.contains(#"<tie type="start">"#) ?? false }
    var selectedLength: MusicXMLEdit.Length? {
        selectedXML?.firstMatch(#"<type>([^<]*)</type>"#).flatMap(MusicXMLEdit.Length.init)
    }

    /// The selected note as a musician would say it ("B flat, quarter"), or "Rest, half".
    var selectedSummary: String? {
        guard let note = selectedXML else { return nil }
        let length = selectedLength.map { String(localized: $0.name) }
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
}

extension MusicXMLEdit.Length {
    var name: LocalizedStringResource {
        switch self {
        case .whole: "Whole"
        case .half: "Half"
        case .quarter: "Quarter"
        case .eighth: "Eighth"
        case .sixteenth: "Sixteenth"
        }
    }
}

/// The buttons for the selected note and its bar, under the music.
struct FixBar: View {
    @Bindable var session: FixSession
    /// The bar number of the selected bar, as printed.
    var barNumber: Int?
    /// At most half the music's pane: past that the buttons scroll.
    var maxHeight: CGFloat = .infinity
    @State private var asking: Question?

    private enum Question: Identifiable, Equatable {
        case rehearsal, tempo, restBars
        case change(Int)
        var id: String { "\(self)" }
    }
    @State private var words = ""

    static let times: [(Int, Int)] = [(2, 4), (3, 4), (4, 4), (5, 4), (2, 2), (3, 8), (6, 8), (9, 8), (12, 8)]

    var body: some View {
        ViewThatFits(in: .vertical) {
            buttons
            ScrollView { buttons }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: maxHeight)
        .background(.bar)
        // Like the reader's strip, the buttons stop growing at the largest standard
        // size so the music keeps the screen; touch and hold shows each one larger.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .alert(alertTitle, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            alertContent
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = session.problem {
                Text(problem)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.notes)
            }
            if session.selectedNote != nil {
                noteButtons
            }
            if session.selectedBar != nil {
                barButtons
            }
            if session.selectedNote == nil && session.selectedBar == nil {
                Text("Tap a note or a bar to fix it.")
                    .formNote()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var alertContent: some View {
            switch asking {
            case .restBars:
                TextField("Number of bars", text: $words)
                    .keyboardType(.numberPad)
            case .change:
                TextField("Words", text: $words)
            default:
                TextField(asking == .tempo ? "Words above the bar" : "Letter or number", text: $words)
            }
            Button(asking == .restBars || asking.map({ if case .change = $0 { true } else { false } }) == true ? "Change" : "Add") {
                let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
                switch asking {
                case .restBars:
                    if let count = Int(text), count >= 1 { session.setRestBars(count) }
                case .change(let index):
                    if !text.isEmpty { session.setWords(at: index, to: text) }
                case .tempo:
                    if !text.isEmpty { session.add(.tempo(text)) }
                case .rehearsal:
                    if !text.isEmpty { session.add(.rehearsal(text)) }
                case nil:
                    break
                }
                asking = nil
            }
            Button("Cancel", role: .cancel) { asking = nil }
    }

    private var alertTitle: LocalizedStringResource {
        switch asking {
        case .tempo: "Tempo"
        case .restBars: "Bars of Rest"
        case .change: "Change Words"
        default: "Rehearsal Mark"
        }
    }

    private var noteButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = session.selectedSummary {
                Text(summary)
                    .font(.headline)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                if !session.selectedIsRest {
                    fixButton("Higher") { session.apply(.step(1)) }
                    fixButton("Lower") { session.apply(.step(-1)) }
                    fixButton("Sharp") { session.apply(.accidental(.sharp)) }
                    fixButton("Flat") { session.apply(.accidental(.flat)) }
                    fixButton("Natural") { session.apply(.accidental(.natural)) }
                }
                Menu {
                    ForEach(MusicXMLEdit.Length.allCases, id: \.self) { length in
                        Button {
                            session.apply(.length(length))
                        } label: {
                            if length == session.selectedLength {
                                Label { Text(length.name) } icon: { Image(systemName: "checkmark") }
                            } else {
                                Text(length.name)
                            }
                        }
                    }
                } label: {
                    Text("Length")
                }
                .menuStyle(.button)
                .buttonStyle(.large)
                .accessibilityLabel(Text("Length"))
                .accessibilityValue(session.selectedLength.map { Text($0.name) } ?? Text(""))
                fixButton(session.selectedHasDot ? "Remove Dot" : "Dot") { session.apply(.toggleDot) }
                if !session.selectedIsRest {
                    fixButton(session.selectedIsTied ? "Remove Tie" : "Tie to Next") { session.apply(.toggleTie) }
                }
                fixButton(session.selectedIsRest ? "Make Note" : "Make Rest") { session.apply(.toggleRest) }
                fixButton("Add Note After") { session.addNote() }
                fixButton("Delete Note") { session.deleteNote() }
            }
        }
    }

    private var barButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let barNumber {
                Text("Bar \(barNumber)")
                    .font(.headline)
            }
            FlowLayout(spacing: 8, lineSpacing: 8) {
                fixButton("Rehearsal Mark") { words = ""; asking = .rehearsal }
                fixButton("Tempo") { words = ""; asking = .tempo }
                fixButton("Fermata") { session.add(.fermata) }
                Menu {
                    ForEach(MusicXMLEdit.dynamics, id: \.self) { mark in
                        Button { session.addDynamic(mark) } label: { Text(verbatim: mark) }
                    }
                } label: {
                    Text("Dynamic")
                }
                .menuStyle(.button)
                .buttonStyle(.large)
                Menu {
                    ForEach(0..<Self.times.count, id: \.self) { index in
                        let time = Self.times[index]
                        Button { session.setTime(beats: time.0, beatType: time.1) } label: { Text(verbatim: "\(time.0)/\(time.1)") }
                    }
                } label: {
                    Text("Time Signature")
                }
                .menuStyle(.button)
                .buttonStyle(.large)
                if session.selectedNote == nil {
                    fixButton("Add Note") { session.addNote() }
                }
                if session.selectedBarIsRest {
                    fixButton("Bars of Rest") { words = "\(session.selectedRestBars)"; asking = .restBars }
                        .accessibilityValue(Text("\(session.selectedRestBars)"))
                }
            }
            ForEach(session.selectedWords) { item in
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    Text(item.text)
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 48)
                    fixButton("Change") { words = item.text; asking = .change(item.index) }
                        .accessibilityLabel(Text("Change \(item.text)"))
                    fixButton("Delete") { session.setWords(at: item.index, to: "") }
                        .accessibilityLabel(Text("Delete \(item.text)"))
                }
            }
        }
    }

    private func fixButton(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.large)
            .accessibilityShowsLargeContentViewer()
    }

}
