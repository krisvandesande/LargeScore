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
    private let grid = [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let problem = model.problem {
                    Text(problem)
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                if !model.wrongBars.isEmpty {
                    Text(wrongBarsText)
                        .font(.body)
                }
                if model.selectedNote != nil { noteButtons }
                if model.selectedBar != nil { barButtons }
                if model.selectedNote == nil && model.selectedBar == nil {
                    Text("Click a note or a bar to fix it.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
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

    private var wrongBarsText: String {
        let numbers = model.wrongBars.compactMap { model.barNumbers[$0] }.sorted().map(String.init)
        let list = numbers.prefix(8).joined(separator: ", ")
        return numbers.count == 1
            ? String(localized: "Bar \(list) doesn't add up to its time signature.")
            : String(localized: "Bars \(list) don't add up to their time signature.")
    }

    private var noteButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = model.selectedSummary {
                Text(summary).font(.title3.weight(.semibold))
            }
            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                if !model.selectedIsRest {
                    fixButton("Higher") { model.apply(.step(1)) }.keyboardShortcut(.upArrow, modifiers: [])
                    fixButton("Lower") { model.apply(.step(-1)) }.keyboardShortcut(.downArrow, modifiers: [])
                    fixButton("Sharp") { model.apply(.accidental(.sharp)) }
                    fixButton("Flat") { model.apply(.accidental(.flat)) }
                    fixButton("Natural") { model.apply(.accidental(.natural)) }
                }
                Menu {
                    ForEach(MusicXMLEdit.Length.allCases, id: \.self) { length in
                        Button(FixModel.name(length) + (length == model.selectedLength ? " ✓" : "")) {
                            model.apply(.length(length))
                        }
                    }
                } label: {
                    Text("Length").font(.body)
                }
                .controlSize(.large)
                .accessibilityValue(Text(model.selectedLength.map(FixModel.name) ?? ""))
                fixButton(model.selectedHasDot ? "Remove Dot" : "Dot") { model.apply(.toggleDot) }
                if !model.selectedIsRest {
                    fixButton(model.selectedIsTied ? "Remove Tie" : "Tie to Next") { model.apply(.toggleTie) }
                }
                fixButton(model.selectedIsRest ? "Make Note" : "Make Rest") { model.apply(.toggleRest) }
                fixButton("Add Note After") { model.addNote() }
                fixButton("Delete Note") { model.deleteNote() }.keyboardShortcut(.delete, modifiers: [])
            }
        }
    }

    private var barButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let bar = model.selectedBar, let number = model.barNumbers[bar] {
                Text("Bar \(number)").font(.title3.weight(.semibold))
            }
            LazyVGrid(columns: grid, alignment: .leading, spacing: 8) {
                fixButton("Rehearsal Mark") { words = ""; asking = .rehearsal }
                fixButton("Tempo") { words = ""; asking = .tempo }
                fixButton("Fermata") { model.add(.fermata) }
                Menu {
                    ForEach(MusicXMLEdit.dynamics, id: \.self) { mark in
                        Button(mark) { model.addDynamic(mark) }
                    }
                } label: {
                    Text("Dynamic").font(.body)
                }
                .controlSize(.large)
                Menu {
                    ForEach(0..<Self.times.count, id: \.self) { index in
                        let time = Self.times[index]
                        Button("\(time.0)/\(time.1)") { model.setTime(beats: time.0, beatType: time.1) }
                    }
                } label: {
                    Text("Time Signature").font(.body)
                }
                .controlSize(.large)
                if model.selectedNote == nil {
                    fixButton("Add Note") { model.addNote() }
                }
                if model.selectedBarIsRest {
                    fixButton("Bars of Rest") { words = "\(model.selectedRestBars)"; asking = .restBars }
                        .accessibilityValue(Text("\(model.selectedRestBars)"))
                }
            }
            ForEach(model.selectedWords) { item in
                HStack(spacing: 8) {
                    Text(item.text).font(.headline)
                    fixButton("Change") { words = item.text; asking = .change(item.index) }
                        .accessibilityLabel(Text("Change \(item.text)"))
                    fixButton("Delete") { model.setWords(at: item.index, to: "") }
                        .accessibilityLabel(Text("Delete \(item.text)"))
                }
            }
        }
    }

    private func fixButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
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
