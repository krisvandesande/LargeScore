import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Every piece as a large card: search, sort, and Add Music.
struct LibraryView: View {
    enum Sort: String, CaseIterable, Identifiable {
        case title, composer, recentlyPlayed
        var id: String { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .title: "Title"
            case .composer: "Composer"
            case .recentlyPlayed: "Recently Played"
            }
        }
    }

    @Environment(ReaderSettings.self) private var settings
    @Environment(ImportCoordinator.self) private var importer
    @Environment(\.modelContext) private var context
    @AppStorage("librarySort") private var sort = Sort.title
    @State private var search = ""
    @State private var choosingFiles = false

    var body: some View {
        NavigationStack {
            LibraryGrid(sort: sort, search: search, addMusic: { choosingFiles = true })
                .background(Palette.ground)
                .navigationTitle("Library")
                .searchable(text: $search, prompt: Text("Title or Composer"))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Picker(selection: $sort) {
                                ForEach(Sort.allCases) { Text($0.title).tag($0) }
                            } label: { Text("Sort") }
                        } label: {
                            Text("Sort: \(Text(sort.title))")
                        }
                        .accessibilityLabel("Sort")
                        .accessibilityValue(Text(sort.title))
                        Button("Add Music") { choosingFiles = true }
                    }
                }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: UTType.musicFiles, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await importer.receive(urls, instruments: settings.instruments, context: context) }
        }
        .dropDestination(for: DroppedMusic.self) { items, _ in
            Task { await importer.receive(items.map(\.url), instruments: settings.instruments, context: context) }
            return !items.isEmpty
        }
    }
}

/// The cards, fetched sorted and filtered by the store rather than in the view.
private struct LibraryGrid: View {
    let addMusic: () -> Void
    let isSearching: Bool
    @Query private var scores: [Score]
    @Environment(\.modelContext) private var context
    @ScaledMetric(relativeTo: .title2) private var cardWidth: CGFloat = 320
    @State private var open: Score?
    @State private var changingPart: Score?
    @State private var deleting: Score?
    @State private var restoring: Score?

    init(sort: LibraryView.Sort, search: String, addMusic: @escaping () -> Void) {
        self.addMusic = addMusic
        let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !words.isEmpty
        let order: [SortDescriptor<Score>] = switch sort {
        case .title: [SortDescriptor(\.title, comparator: .localizedStandard)]
        case .composer: [SortDescriptor(\.composer, comparator: .localizedStandard), SortDescriptor(\.title, comparator: .localizedStandard)]
        case .recentlyPlayed: [SortDescriptor(\.lastOpenedAt, order: .reverse), SortDescriptor(\.title, comparator: .localizedStandard)]
        }
        let filter: Predicate<Score>? = words.isEmpty ? nil : #Predicate<Score> { score in
            score.title.localizedStandardContains(words)
                || (score.composer?.localizedStandardContains(words) ?? false)
        }
        _scores = Query(filter: filter, sort: order)
    }

    var body: some View {
        if scores.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(cardWidth, 600)), spacing: 24)], spacing: 24) {
                    ForEach(scores) { score in
                        card(score)
                    }
                }
                .air(.horizontal, 48)
                .air(.vertical, 24)
            }
            .fullScreenCover(item: $open) { score in
                ReaderView(piece: score.piece, backTitle: "Library")
            }
            .sheet(item: $changingPart) { score in
                PartChooser(score: score)
            }
            .confirmationDialog(Text("Delete \(deleting?.title ?? "")?"), isPresented: isPresent($deleting), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting { context.delete(deleting); try? context.save() }
                }
            } message: {
                Text("The piece and your notes on it are removed from this iPad.")
            }
            .confirmationDialog(Text("Restore the previous version of \(restoring?.title ?? "")?"), isPresented: isPresent($restoring), titleVisibility: .visible) {
                Button("Restore Previous Version") {
                    restoring?.restorePrevious()
                    try? context.save()
                }
            } message: {
                Text("The music you added last is replaced by the version before it.")
            }
        }
    }

    private func card(_ score: Score) -> some View {
        Button {
            score.lastOpenedAt = .now
            try? context.save()
            open = score
        } label: {
            PieceCard(title: score.title, composer: score.composer)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if score.partCount > 1 {
                Button("Change Parts", systemImage: "music.note.list") { changingPart = score }
            }
            if score.previousMusicXML != nil {
                Button("Restore Previous Version", systemImage: "clock.arrow.circlepath") { restoring = score }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = score }
        }
        .accessibilityAction(named: Text("Change Parts")) { changingPart = score }
        .accessibilityAction(named: Text("Delete")) { deleting = score }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            if isSearching {
                Text("Nothing found")
                    .font(.title.weight(.semibold))
            } else {
                Text("No music yet")
                    .font(.title.weight(.semibold))
                Text("Add MusicXML files from Files, iCloud Drive or Google Drive, or send them to this iPad with AirDrop.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button("Add Music", action: addMusic)
                    .buttonStyle(.largeProminent)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 640)
        .air(.all, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isPresent(_ item: Binding<Score?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

/// Other parts of a piece already in the library; more than one reads together.
private struct PartChooser: View {
    let score: Score
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var all: [ScorePart] = []
    @State private var chosen: [ScorePart] = []

    var body: some View {
        NavigationStack {
            List(all) { part in
                let selected = chosen.contains { $0.id == part.id }
                Button {
                    chosen = PartPicking.toggle(part, in: chosen, order: all)
                } label: {
                    HStack {
                        Text(verbatim: part.name.isEmpty ? part.id : part.name)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .air(.vertical, 6)
                }
                .tint(.primary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            .font(.title3)
            .navigationTitle(score.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        score.chooseParts(chosen)
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .task {
            // Read once when the sheet opens, not on every redraw.
            all = score.parts
            chosen = all.filter { score.partIDs.contains($0.id) }
        }
    }
}

struct PieceCard: View {
    let title: String
    let composer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
            if let composer, !composer.isEmpty {
                Text(composer)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .air(.horizontal, 32)
        .air(.vertical, 24)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// What a tab shows while it has nothing: one plain line, and what to do if anything.
struct EmptyTab: View {
    let title: LocalizedStringResource
    let heading: LocalizedStringResource
    var message: LocalizedStringResource?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(heading)
                    .font(.title.weight(.semibold))
                if let message {
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .air(.all, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.ground)
            .navigationTitle(Text(title))
        }
    }
}
