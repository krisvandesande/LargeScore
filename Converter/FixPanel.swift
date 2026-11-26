import SwiftUI

/// The buttons for the selected note and its bar, as the iPad's Fix Notes has them.
/// Up and Down arrows move the note; Delete removes it.
struct FixPanel: View {
    @ObservedObject var model: FixModel
    @State private var asking: Question?
    @State private var words = ""

    private enum Question: Identifiable, Equatable {
        case rehearsal, tempo, restBars
        case change(Int)
        var id: String { "\(self)" }
    }

    static let times: [(Int, Int)] = [(2, 4), (3, 4), (4, 4), (5, 4), (2, 2), (3, 8), (6, 8), (9, 8), (12, 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.problem != nil || !model.wrongBars.isEmpty {
                    warnings
                    Divider()
                }
                if model.selectedNote == nil && model.selectedBar == nil {
                    Text("Click a note or a bar to fix it.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(Self.inset)
                }
                if model.selectedNote != nil {
                    noteSection
                    Divider()
                }
                if model.selectedBar != nil {
                    barSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $asking) { question in
            WordsSheet(title: title(question), prompt: prompt(question), text: $words,
                       confirm: confirmTitle(question)) {
                answer(question)
                asking = nil
            } cancel: {
                asking = nil
            }
        }
    }

    static let inset: CGFloat = 16

    // MARK: Sections

    /// What's wrong: the last change that couldn't be made, and bars that don't add up.
    private var warnings: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
            if !model.wrongBars.isEmpty {
                Label {
                    Text(wrongBarsText).foregroundColor(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Self.inset)
    }

    private var wrongBarsText: String {
        let numbers = model.wrongBars.compactMap { model.barNumbers[$0] }.sorted().map(String.init)
        let list = numbers.prefix(8).joined(separator: ", ")
        return numbers.count == 1
            ? String(localized: "Bar \(list) doesn't add up to its time signature.")
            : String(localized: "Bars \(list) don't add up to their time signature.")
    }

    private var noteSection: some View {
        section(title: model.selectedIsRest ? Text("Rest") : Text("Note"), detail: model.selectedSummary) {
            if !model.selectedIsRest {
                field("Pitch") {
                    HStack(spacing: 8) {
                        Button { model.apply(.step(-1)) } label: { Label("Lower", systemImage: "arrow.down") }
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .help("A step lower (↓)")
                        Button { model.apply(.step(1)) } label: { Label("Higher", systemImage: "arrow.up") }
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .help("A step higher (↑)")
                    }
                }
                field("Sharp or Flat") {
                    Picker("Sharp or Flat", selection: Binding(
                        get: { model.selectedAccidental },
                        set: { if let accidental = $0 { model.apply(.accidental(accidental)) } })) {
                        Text("♯ Sharp").tag(Optional(MusicXMLEdit.Accidental.sharp))
                        Text("♭ Flat").tag(Optional(MusicXMLEdit.Accidental.flat))
                        Text("♮ Natural").tag(Optional(MusicXMLEdit.Accidental.natural))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            field("Length") {
                HStack(spacing: 8) {
                    Picker("Length", selection: Binding(
                        get: { model.selectedLength ?? .quarter },
                        set: { model.apply(.length($0)) })) {
                        ForEach(MusicXMLEdit.Length.allCases, id: \.self) { length in
                            Text(FixModel.name(length)).tag(length)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    toggle("Dot", isOn: model.selectedHasDot) { model.apply(.toggleDot) }
                    if !model.selectedIsRest {
                        toggle("Tie to Next", isOn: model.selectedIsTied) { model.apply(.toggleTie) }
                    }
                }
            }
            field("Note") {
                HStack(spacing: 8) {
                    toggle("Rest", isOn: model.selectedIsRest) { model.apply(.toggleRest) }
                    Button("Add After") { model.addNote() }
                        .help("Add a note after this one")
                    Button("Delete") { model.deleteNote() }
                        .keyboardShortcut(.delete, modifiers: [])
                        .help("Delete this note (⌫)")
                        .accessibilityLabel(Text("Delete Note"))
                }
            }
        }
    }

    private var barSection: some View {
        let number = model.selectedBar.flatMap { model.barNumbers[$0] }
        return section(title: number.map { Text("Bar \($0)") } ?? Text("Bar"), detail: nil) {
            field("Time Signature") {
                Menu {
                    ForEach(0..<Self.times.count, id: \.self) { index in
                        let time = Self.times[index]
                        let name = "\(time.0)/\(time.1)"
                        Button { model.setTime(beats: time.0, beatType: time.1) } label: {
                            if name == model.currentTime { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                } label: {
                    Text(model.currentTime)
                }
                .fixedSize()
                .accessibilityLabel(Text("Time Signature"))
                .accessibilityValue(Text(model.currentTime))
            }
            field("Key Signature") {
                Menu {
                    ForEach(MusicXMLEdit.keys.reversed(), id: \.self) { fifths in
                        Button { model.setKey(fifths) } label: {
                            if fifths == model.currentKey {
                                Label(KeyName.name(fifths), systemImage: "checkmark")
                            } else {
                                Text(KeyName.name(fifths))
                            }
                        }
                    }
                } label: {
                    Text(KeyName.signature(model.currentKey))
                }
                .fixedSize()
                .help("Set the key from this bar on. Notes without their own sharp or flat follow it.")
                .accessibilityLabel(Text("Key Signature"))
                .accessibilityValue(Text(KeyName.name(model.currentKey)))
            }
            field("Add") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Rehearsal Mark…") { words = ""; asking = .rehearsal }
                        Button("Tempo…") { words = ""; asking = .tempo }
                    }
                    HStack(spacing: 8) {
                        Button("Fermata") { model.add(.fermata) }
                        Menu {
                            ForEach(MusicXMLEdit.dynamics, id: \.self) { mark in
                                Button(mark) { model.addDynamic(mark) }
                            }
                        } label: {
                            Text("Dynamic")
                        }
                        .fixedSize()
                    }
                }
            }
            if model.selectedNote == nil {
                field("") {
                    Button("Add Note") { model.addNote() }
                }
            }
            if model.selectedBarIsRest {
                field("Bars of Rest") {
                    Button("\(model.selectedRestBars)…") { words = "\(model.selectedRestBars)"; asking = .restBars }
                        .accessibilityLabel(Text("Bars of Rest"))
                        .accessibilityValue(Text("\(model.selectedRestBars)"))
                }
            }
            ForEach(model.selectedWords) { item in
                field("Words") {
                    HStack(spacing: 8) {
                        Text(item.text).font(.body.weight(.semibold)).lineLimit(1)
                        Button("Change…") { words = item.text; asking = .change(item.index) }
                            .accessibilityLabel(Text("Change \(item.text)"))
                        Button("Delete") { model.setWords(at: item.index, to: "") }
                            .accessibilityLabel(Text("Delete \(item.text)"))
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    /// A titled group of fields, as a Mac inspector shows one.
    private func section<Content: View>(title: Text, detail: String?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                if let detail {
                    Text(detail).font(.title3.weight(.semibold))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content()
        }
        .controlSize(.large)
        .padding(Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A field: its name above, small, and the controls under it.
    private func field<Content: View>(_ name: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if name != "" {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            content()
        }
    }

    /// A button that stays pressed while its state is on.
    private func toggle(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in action() }))
            .toggleStyle(.button)
    }

    private func title(_ question: Question) -> LocalizedStringKey {
        switch question {
        case .tempo: "Tempo"
        case .restBars: "Bars of Rest"
        case .change: "Change Words"
        case .rehearsal: "Rehearsal Mark"
        }
    }

    private func prompt(_ question: Question) -> LocalizedStringKey {
        switch question {
        case .tempo: "Words above the bar"
        case .restBars: "Number of bars"
        case .change: "Words"
        case .rehearsal: "Letter or number"
        }
    }

    private func confirmTitle(_ question: Question) -> LocalizedStringKey {
        switch question {
        case .restBars, .change: "Change"
        default: "Add"
        }
    }

    private func answer(_ question: Question) {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        switch question {
        case .restBars: if let count = Int(text), count >= 1 { model.setRestBars(count) }
        case .change(let index): if !text.isEmpty { model.setWords(at: index, to: text) }
        case .tempo: if !text.isEmpty { model.add(.tempo(text)) }
        case .rehearsal: if !text.isEmpty { model.add(.rehearsal(text)) }
        }
    }
}

/// Asks for a few words: macOS 12's alerts take no text field.
private struct WordsSheet: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var text: String
    let confirm: LocalizedStringKey
    let done: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            TextField(prompt, text: $text)
                .font(.body)
                .textFieldStyle(.roundedBorder)
                .onSubmit(done)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(confirm, action: done).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 420)
    }
}
