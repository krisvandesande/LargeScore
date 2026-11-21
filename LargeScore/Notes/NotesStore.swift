import SwiftUI
import SwiftData
import UIKit

/// The notes of the piece in the reader: read once into values, written straight
/// to the store, with an undo for this visit.
@Observable
final class NotesStore {
    private(set) var marks: [Mark] = []
    private let score: Score?
    private let context: ModelContext

    private enum Change {
        case added(Mark)
        case removed([Mark])
    }
    private var changes: [Change] = []

    init(pieceID: String, context: ModelContext) {
        self.context = context
        let id = UUID(uuidString: pieceID)
        score = id.flatMap { id in
            try? context.fetch(FetchDescriptor<Score>(predicate: #Predicate { $0.id == id })).first
        }
        marks = score?.annotations?.map(\.mark) ?? []
    }

    /// Only pieces in the library take notes; the bundled sample doesn't.
    var canAnnotate: Bool { score != nil }
    var canUndo: Bool { !changes.isEmpty }

    var note: String {
        get { score?.note ?? "" }
        set {
            score?.note = newValue
            try? context.save()
        }
    }

    func add(_ mark: Mark) {
        insert(mark)
        changes.append(.added(mark))
        save()
    }

    func remove(_ removed: [Mark]) {
        guard !removed.isEmpty else { return }
        delete(removed)
        changes.append(.removed(removed))
        save()
    }

    func undo() {
        guard let last = changes.popLast() else { return }
        switch last {
        case .added(let mark): delete([mark])
        case .removed(let marks): marks.forEach(insert)
        }
        save()
    }

    private func insert(_ mark: Mark) {
        guard let score else { return }
        let annotation = Annotation(mark: mark)
        annotation.score = score
        score.annotations = (score.annotations ?? []) + [annotation]
        marks.append(mark)
    }

    private func delete(_ gone: [Mark]) {
        let ids = Set(gone.map(\.id))
        for annotation in score?.annotations ?? [] where ids.contains(annotation.id) {
            score?.annotations?.removeAll { $0 === annotation }
            context.delete(annotation)
        }
        marks.removeAll { ids.contains($0.id) }
    }

    private func save() { try? context.save() }
}

enum NotesTool: Hashable {
    case pen, eraser
    case mark(MarkKind)

    var title: LocalizedStringResource {
        switch self {
        case .pen: "Pen"
        case .eraser: "Eraser"
        case .mark(let kind):
            switch kind {
            case .breath: "Breath"
            case .fermata: "Fermata"
            case .finger1: "1"
            case .finger2: "2"
            case .finger3: "3"
            case .finger4: "4"
            case .finger5: "5"
            case .watch: "Watch"
            case .circle: "Circle Bar"
            case .highlight: "Highlight Bar"
            case .ink: "Pen"
            }
        }
    }

    /// What VoiceOver and Voice Control call it, where the shown word is a digit.
    var spokenTitle: LocalizedStringResource {
        switch self {
        case .mark(.finger1): "Finger 1"
        case .mark(.finger2): "Finger 2"
        case .mark(.finger3): "Finger 3"
        case .mark(.finger4): "Finger 4"
        case .mark(.finger5): "Finger 5"
        default: title
        }
    }

    static let all: [NotesTool] = [.pen, .eraser, .mark(.breath), .mark(.fermata),
                                   .mark(.finger1), .mark(.finger2), .mark(.finger3), .mark(.finger4), .mark(.finger5),
                                   .mark(.watch), .mark(.circle), .mark(.highlight)]
}

/// The strip while writing notes: the tools, then undo, the written note, the page
/// buttons and Done. Wraps onto more rows when the words are large.
struct NotesPalette: View {
    @Binding var tool: NotesTool
    let canUndo: Bool
    let pageText: Text?
    let undo: () -> Void
    let writtenNote: () -> Void
    let previousPage: () -> Void
    let nextPage: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 10, lineSpacing: 10) {
                ForEach(NotesTool.all, id: \.self) { item in
                    let selected = tool == item
                    Button { tool = item } label: {
                        HStack(spacing: 8) {
                            if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                            Text(item.title)
                        }
                    }
                    .buttonStyle(LargeButtonStyle(prominent: selected))
                    .accessibilityShowsLargeContentViewer()
                    .accessibilityLabel(Text(item.spokenTitle))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            FlowLayout(spacing: 10, lineSpacing: 10) {
                Button("Undo", action: undo)
                    .buttonStyle(.large)
                    .accessibilityShowsLargeContentViewer()
                    .disabled(!canUndo)
                Button("Written Note", action: writtenNote)
                    .buttonStyle(.large)
                    .accessibilityShowsLargeContentViewer()
                Button("Previous Page", action: previousPage)
                    .buttonStyle(.large)
                    .accessibilityShowsLargeContentViewer()
                Button("Next Page", action: nextPage)
                    .buttonStyle(.large)
                    .accessibilityShowsLargeContentViewer()
                if let pageText {
                    pageText
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .frame(minHeight: 64)
                }
                Button("Done", action: done)
                    .buttonStyle(.largeProminent)
                    .accessibilityShowsLargeContentViewer()
            }
        }
        .air(.horizontal, 24)
        .air(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Capped like the reader's strip, so the music keeps the screen; every button
        // shows large in the Large Content Viewer (touch and hold).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) { Divider() }
    }
}

/// The note in words about the whole piece.
struct WrittenNoteSheet: View {
    let store: NotesStore
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Note on This Piece")
                    .font(.headline)
                    .foregroundStyle(Palette.quiet)
                    .accessibilityHidden(true)
                TextEditor(text: $text)
                    .font(.title2)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Note on This Piece")
                    .focused($focused)
            }
            .air(.all, 24)
            .background(Palette.ground)
            .navigationTitle("Written Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.note = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { text = store.note }
        .task {
            // Ready to type at once, once the sheet has finished coming up.
            try? await Task.sleep(for: .milliseconds(400))
            focused = true
        }
    }
}

extension Palette {
    /// Notes in a colour of their own, apart from the printed music: 6.4:1 on white,
    /// 8:1 on black.
    static let notes = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0x8A / 255, blue: 0x80 / 255, alpha: 1)
            : UIColor(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x1E / 255, alpha: 1)
    })
}
