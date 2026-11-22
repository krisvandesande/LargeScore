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
    var selectedNote: String?
    var selectedBar: String?
    var problem: LocalizedStringResource?

    init(xml: String) {
        edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(xml))
        wrongBars = edit.barsThatDontAddUp()
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
        if let note = selectedNote, edit.elementRange("note", id: note) == nil { selectedNote = nil }
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
    @State private var asking: Question?

    private enum Question: Identifiable {
        case rehearsal, tempo
        var id: Self { self }
    }
    @State private var words = ""

    var body: some View {
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
        .background(.bar)
        .alert(asking == .tempo ? "Tempo" : "Rehearsal Mark", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            TextField(asking == .tempo ? "Words above the bar" : "Letter or number", text: $words)
            Button("Add") {
                let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { session.add(asking == .tempo ? .tempo(text) : .rehearsal(text)) }
                asking = nil
            }
            Button("Cancel", role: .cancel) { asking = nil }
        }
    }

    private var noteButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = session.selectedSummary {
                Text(summary)
                    .font(.headline)
                    .accessibilityLabel(Text("Selected: \(summary)"))
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
            }
        }
    }

    private func fixButton(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.large)
    }

}
