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
    enum Layout: String, CaseIterable, Identifiable {
        case list, cards
        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .list: "List"
            case .cards: "Cards"
            }
        }
    }

    @AppStorage("librarySort") private var sort = Sort.title
    /// A list by default: with a whole book of parts, cards run to dozens of screens.
    @AppStorage("libraryLayout") private var layout = Layout.list
    @State private var search = ""
    @State private var selecting = false

    var body: some View {
        NavigationStack {
            LibraryGrid(sort: sort, search: search, layout: layout, selecting: $selecting, addMusic: { importer.choosingFiles = true })
                .background(Palette.ground)
                .navigationTitle("Library")
                .searchable(text: $search, prompt: Text("Title or Composer"))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Picker(selection: $sort) {
                                ForEach(Sort.allCases) { Text($0.title).tag($0) }
                            } label: { Text("Sort") }
                            Picker(selection: $layout) {
                                ForEach(Layout.allCases) { Text($0.title).tag($0) }
                            } label: { Text("Show As") }
                        } label: {
                            Text("Sort: \(Text(sort.title))")
                        }
                        .accessibilityLabel("Sort")
                        .accessibilityValue(Text(sort.title))
                        if layout == .list {
                            Button(selecting ? "Done" : "Select") { withAnimation { selecting.toggle() } }
                        }
                        if !selecting {
                            Button("Add Music") { importer.choosingFiles = true }
                        }
                    }
                }
        }
        .fileImporter(isPresented: Bindable(importer).choosingFiles, allowedContentTypes: UTType.musicFiles, allowsMultipleSelection: true) { result in
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
    let sort: LibraryView.Sort
    let layout: LibraryView.Layout
    @Binding var selecting: Bool
    @State private var selection: Set<UUID> = []
    @State private var deletingMany = false
    @State private var showOthers = false
    /// Letters and other parts, worked out when the library changes, not every redraw.
    @State private var grouping = LibraryGrouping()
    @Query private var scores: [Score]
    @Query(sort: \Programme.createdAt, order: .reverse) private var programmes: [Programme]
    @Environment(\.modelContext) private var context
    @Environment(ReaderSettings.self) private var settings
    @Environment(MusicFolder.self) private var folder
    @Environment(ImportCoordinator.self) private var importer
    @ScaledMetric(relativeTo: .title2) private var cardWidth: CGFloat = 320
    /// A value, not the stored piece: deleted on another device, a stored piece can't
    /// be read any more, and the reader would stop the app.
    @State private var open: Piece?
    @State private var changingPart: Score?
    @State private var deleting: Score?
    @State private var restoring: Score?
    @State private var comparing: Score?
    @State private var fixing: Score?
    @State private var transposing: Score?
    @State private var sizing: Piece?
    @State private var editingDetails: Score?

    init(sort: LibraryView.Sort, search: String, layout: LibraryView.Layout, selecting: Binding<Bool>, addMusic: @escaping () -> Void) {
        self.addMusic = addMusic
        self.sort = sort
        self.layout = layout
        _selecting = selecting
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
        // The covers and sheets hang on the group, so deleting the last piece (here or
        // on another device) doesn't take an open reader with it.
        Group {
            if scores.isEmpty {
                // In a scroll view only so it can be pulled down to look for music.
                ScrollView {
                    emptyState.containerRelativeFrame(.vertical)
                }
                .refreshable { await folder.look(instruments: settings.instruments, context: context, importer: importer) }
            } else if layout == .list {
                list
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: min(cardWidth, 600)), spacing: 24, alignment: .top)], spacing: 24) {
                        ForEach(scores) { score in
                            card(score)
                        }
                    }
                    .air(.horizontal, 48)
                    .air(.vertical, 24)
                }
                // Pull down to look for new music now.
                .refreshable { await folder.look(instruments: settings.instruments, context: context, importer: importer) }
            }
        }
        .task(id: GroupingKey(items: scores.map { GroupingKey.Item(id: $0.id, title: $0.title, composer: $0.composer) },
                              myPart: settings.myPart, sort: sort)) {
            grouping = LibraryGrouping(scores.map { (id: $0.id, title: $0.title, composer: $0.composer) },
                                       myPart: settings.myPart, sort: sort)
        }
        .onChange(of: selecting) { _, now in if !now { selection = [] } }
        .fullScreenCover(item: $open) { piece in
            ReaderView(piece: piece, backTitle: "Library")
        }
        .fullScreenCover(item: $comparing) { score in
            CompareView(score: score)
        }
        .fullScreenCover(item: $fixing) { score in
            CompareView(score: score, startFixing: true)
        }
        .sheet(item: $changingPart) { score in
            PartChooser(score: score)
        }
        .sheet(item: $transposing) { score in
            TransposeSheet(score: score)
        }
        .sheet(item: $sizing) { piece in
            PieceSizeSheet(piece: piece)
        }
        .sheet(item: $editingDetails) { score in
            DetailsSheet(score: score)
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

    private func card(_ score: Score) -> some View {
        Button {
            score.lastOpenedAt = .now
            try? context.save()
            open = score.piece
        } label: {
            PieceCard(title: score.title, composer: score.composer, note: score.note, needsCheck: score.needsCheck,
                      facts: facts(score))
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: score) }
        #if targetEnvironment(macCatalyst)
        // Onto a programme in the sidebar.
        .draggable(score.id.uuidString) {
            PieceCard(title: score.title, composer: score.composer).frame(width: 320)
        }
        #endif
        .accessibilityAction(named: Text("Change Parts")) { changingPart = score }
        .accessibilityAction(named: Text("Delete")) { deleting = score }
        .accessibilityAction(named: Text("Edit Details")) { editingDetails = score }
        .accessibilityAction(named: Text("Fix Notes")) { fixing = score }
        .accessibilityAction(named: Text("Transpose")) { transposing = score }
        .accessibilityAction(named: Text("Size for This Piece")) { sizing = score.piece }
        .accessibilityAction(named: Text("Compare with PDF")) { if score.pdf != nil { comparing = score } }
    }

    private func facts(_ score: Score) -> [PieceFacts.Fact] {
        let programmes = (score.entries ?? []).compactMap { $0.programme?.name }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return PieceFacts.facts(PieceFacts.Input(
            arranger: score.arranger, partName: score.partName, barCount: score.barCount,
            transposition: score.transposition?.description, programmes: programmes,
            ownSettings: settings.hasOwnSettings(score.id.uuidString),
            lastOpenedAt: score.lastOpenedAt, addedAt: score.addedAt))
    }

    /// One row a piece, grouped by first letter, with a strip of letters to jump by.
    /// Other parts of pieces whose own part is there wait, closed, at the end.
    private var list: some View {
        let byID = Dictionary(scores.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let letters = grouping.sections.map(\.key).filter { !$0.isEmpty }
        return ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(grouping.sections, id: \.key) { section in
                    Section {
                        ForEach(section.rows) { row in
                            if let score = byID[row.id] { listRow(row, score: score) }
                        }
                    } header: {
                        if !section.key.isEmpty {
                            Text(verbatim: section.key)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                if !grouping.others.isEmpty {
                    Section {
                        if showOthers {
                            ForEach(grouping.others) { row in
                                if let score = byID[row.id] { listRow(row, score: score) }
                            }
                        }
                    } header: {
                        Button {
                            withAnimation { showOthers.toggle() }
                        } label: {
                            HStack(spacing: 12) {
                                // Opens in place: a filled triangle, pointing in, down when open.
                                Image(systemName: showOthers ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                                    .font(.body)
                                    .accessibilityHidden(true)
                                Text("Other Parts")
                                Text(verbatim: "\(grouping.others.count)").foregroundStyle(.secondary)
                            }
                            .font(.title2.weight(.bold))
                            // A list header dims its contents; this one is a control in the text colour.
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: String(AttributedString(localized: "Other Parts, ^[\(grouping.others.count) piece](inflect: true)").characters)))
                        .accessibilityValue(Text(showOthers ? "Shown" : "Hidden"))
                        .accessibilityHint(Text("Parts other than your own, of pieces whose own part is in the library."))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if ids.count == 1, let id = ids.first, let score = byID[id] { menu(for: score) }
            } primaryAction: { ids in
                guard !selecting, let id = ids.first, let score = byID[id] else { return }
                score.lastOpenedAt = .now
                try? context.save()
                open = score.piece
            }
            .contentMargins(.trailing, letters.count > 1 ? 56 : 0, for: .scrollContent)
            .overlay(alignment: .trailing) {
                if letters.count > 1, !selecting { letterStrip(letters, proxy: proxy) }
            }
            .refreshable { await folder.look(instruments: settings.instruments, context: context, importer: importer) }
            .toolbar {
                if selecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        let all = Set(grouping.sections.flatMap { $0.rows.map(\.id) } + (showOthers ? grouping.others.map(\.id) : []))
                        Button(selection.isSuperset(of: all) && !all.isEmpty ? "Deselect All" : "Select All") {
                            selection = selection.isSuperset(of: all) ? [] : all
                        }
                        Spacer()
                        Button("Delete", role: .destructive) { deletingMany = true }
                            .disabled(selection.isEmpty)
                            .accessibilityValue(Text(verbatim: String(AttributedString(localized: "^[\(selection.count) piece](inflect: true)").characters)))
                            // Anchored to the button, so on iPad it points at what was tapped.
                            .confirmationDialog(Text(verbatim: String(AttributedString(localized: "Delete ^[\(selection.count) piece](inflect: true)?").characters)),
                                                isPresented: $deletingMany, titleVisibility: .visible) {
                                Button("Delete", role: .destructive) {
                                    for score in scores where selection.contains(score.id) { context.delete(score) }
                                    try? context.save()
                                    selection = []
                                    selecting = false
                                }
                            } message: {
                                Text("The pieces and your notes on them are removed from your library on every device.")
                            }
                    }
                }
            }
        }
    }

    private func listRow(_ row: LibraryGrouping.Row, score: Score) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.title2.weight(.semibold))
                if let composer = score.composer, !composer.isEmpty {
                    Text(composer).font(.title3).foregroundStyle(.secondary)
                }
                if score.needsCheck {
                    Text("Check against the PDF")
                        .font(.headline)
                        .foregroundStyle(Palette.onNotes)
                        .padding(.horizontal, 12)
                        .air(.vertical, 4)
                        .background(Palette.notes, in: PillShape(radius: 14))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let part = row.part {
                Text("Part \(part)").font(.title3).foregroundStyle(.secondary)
            }
            if !selecting { ForwardChevron() }
        }
        .air(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Edit Details")) { editingDetails = score }
        .accessibilityAction(named: Text("Fix Notes")) { fixing = score }
        .accessibilityAction(named: Text("Delete")) { deleting = score }
    }

    /// The letters down the right edge: a tap jumps to that letter's first piece.
    private func letterStrip(_ letters: [String], proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let height = min(44, (geometry.size.height - 16) / CGFloat(max(letters.count, 1)))
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Button {
                        if let first = grouping.sections.first(where: { $0.key == letter })?.rows.first {
                            withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    } label: {
                        Text(verbatim: letter)
                            .font(.headline)
                            .frame(width: 44, height: height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(Text("Jump to \(letter)"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 48)
        .padding(.trailing, 4)
    }

    /// What can be done with a piece: the card's and the list row's menu.
    @ViewBuilder
    private func menu(for score: Score) -> some View {
        if !programmes.isEmpty {
            Menu("Add to Programme", systemImage: "text.badge.plus") {
                ForEach(programmes) { programme in
                    Button(programme.name) {
                        programme.append([score])
                        try? context.save()
                    }
                }
            }
        }
        if score.pdf != nil {
            Button("Compare with PDF", systemImage: "doc.on.doc") { comparing = score }
        }
        Button("Edit Details", systemImage: "character.cursor.ibeam") { editingDetails = score }
        Button("Fix Notes", systemImage: "pencil") { fixing = score }
        Button("Transpose", systemImage: "arrow.up.arrow.down") { transposing = score }
        Button("Size for This Piece", systemImage: "textformat.size") { sizing = score.piece }
        if score.needsCheck {
            Button("Mark as Checked", systemImage: "checkmark") {
                score.needsCheck = false
                try? context.save()
            }
        }
        if score.partCount > 1 {
            Button("Change Parts", systemImage: "music.note.list") { changingPart = score }
        }
        if score.previousMusicXML != nil {
            Button("Restore Previous Version", systemImage: "clock.arrow.circlepath") { restoring = score }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = score }
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
/// Reading a part written for another instrument: what it's written for, what
/// plays it, and an octave either way.
/// One piece read at a size of its own: the piece itself at that size, as the reader
/// will show it, and the size slider.
private struct PieceSizeSheet: View {
    let piece: Piece
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        let step = settings.sizeStep(for: piece.id)
        NavigationStack {
            SampleCard(piece: piece, description: "\(piece.title) at size \(step + 1)", fills: true, asPage: true)
                .overlay(alignment: .bottom) {
                    StepSlider(value: step, count: count, smaller: "textformat.size.smaller", larger: "textformat.size.larger") {
                        settings.setSize($0 == settings.sizeStep ? nil : $0, for: piece.id)
                    }
                    .accessibilityLabel("Size for this piece")
                    .accessibilityValue(Text("Size \(step + 1) of \(count)"))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .frame(maxWidth: 620)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 80)
                    .padding(.bottom, 16)
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(piece.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if step != settings.sizeStep {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Use Standard Size") { settings.setSize(nil, for: piece.id) }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationSizing(.page)
    }
}

/// A piece's title, composer and arranger, as the library and programmes show them.
private struct DetailsSheet: View {
    let score: Score
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var composer = ""
    @State private var arranger = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Title", text: $title, prompt: nil)
                    field("Composer", text: $composer, prompt: "Optional")
                    field("Arranger", text: $arranger, prompt: "Optional")
                }
            }
            .font(.title3)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            title = score.title
            composer = score.composer ?? ""
            arranger = score.arranger ?? ""
        }
    }

    private func field(_ name: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.headline).accessibilityHidden(true)
            TextField(text: text, prompt: prompt.map { Text($0) }) { Text(name) }
                .font(.title3)
                .accessibilityLabel(Text(name))
        }
        .air(.vertical, 4)
    }

    private func save() {
        let clean = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !clean(title).isEmpty else { return }
        score.title = clean(title)
        score.composer = clean(composer).isEmpty ? nil : clean(composer)
        score.arranger = clean(arranger).isEmpty ? nil : clean(arranger)
        try? context.save()
        dismiss()
    }
}

private struct TransposeSheet: View {
    let score: Score
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// What the reader plays, remembered for the next piece.
    @AppStorage("transposePlayedOn") private var playedOn: WrittenFor = .bFlat
    @State private var writtenFor: WrittenFor = .eFlat
    @State private var octaves = 0

    private var transposition: Transposition {
        Transposition(from: writtenFor, to: playedOn, octaves: octaves)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FittingPicker(String(localized: "Written For"), value: String(localized: writtenFor.title), selection: $writtenFor) {
                        ForEach(WrittenFor.allCases) { Text($0.title).tag($0) }
                    }
                    FittingPicker(String(localized: "Played On"), value: String(localized: playedOn.title), selection: $playedOn) {
                        ForEach(WrittenFor.allCases) { Text($0.title).tag($0) }
                    }
                    FittingPicker(String(localized: "Octave"), value: String(localized: octaveTitle(octaves)), selection: $octaves) {
                        ForEach([1, 0, -1], id: \.self) { Text(octaveTitle($0)).tag($0) }
                    }
                }
                Section {
                    Text(verbatim: transposition.description + (transposition.changesClef ? ", " + (transposition.to.bassClef ? String(localized: "bass clef") : String(localized: "treble clef")) : ""))
                        .font(.title3.weight(.semibold))
                }
            }
            .font(.title3)
            .navigationTitle(score.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if score.transposition != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("As Written") {
                            score.transposition = nil
                            try? context.save()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        score.transposition = transposition
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let current = score.transposition {
                writtenFor = current.from
                playedOn = current.to
                octaves = current.octaves
            }
        }
    }

    private func octaveTitle(_ octaves: Int) -> LocalizedStringResource {
        switch octaves {
        case 1: "An Octave Higher"
        case -1: "An Octave Lower"
        default: "Nearest"
        }
    }
}

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
    var note: String = ""
    var needsCheck = false
    /// The rest of what's known, a line each; heard as More Content.
    var facts: [PieceFacts.Fact] = []

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
            if needsCheck {
                // Converted from a PDF by a recognition program and not checked yet.
                Text("Check against the PDF")
                    .font(.headline)
                    .foregroundStyle(Palette.onNotes)
                    .padding(.horizontal, 12)
                    .air(.vertical, 4)
                    .background(Palette.notes, in: PillShape(radius: 14))
                    .padding(.top, 4)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.title3.italic())
                    .foregroundStyle(Palette.notes)
                    .padding(.top, 4)
            }
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(facts, id: \.kind) { fact in
                        Text(fact.text)
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityHidden(true)
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
        .modifier(FactContent(facts: facts))
    }
}

/// Every kind of fact always applied, nil when the piece has none, so the chain keeps
/// one shape from card to card.
private struct FactContent: ViewModifier {
    let facts: [PieceFacts.Fact]

    private func text(_ kind: PieceFacts.Kind) -> Text? {
        facts.first { $0.kind == kind }.map { Text($0.text) }
    }

    func body(content: Content) -> some View {
        content
            .accessibilityCustomContent(AccessibilityCustomContentKey("Arranger"), text(.arranger))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Parts"), text(.parts))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Bars"), text(.bars))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Transposed"), text(.transposed))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Programmes"), text(.programmes))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Settings"), text(.settings))
            .accessibilityCustomContent(AccessibilityCustomContentKey("Played"), text(.played))
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

/// What the library's list is built from: changes in a piece's title or composer, the
/// player's part, or the sort make a new grouping.
private struct GroupingKey: Hashable {
    struct Item: Hashable {
        var id: UUID
        var title: String
        var composer: String?
    }
    var items: [Item]
    var myPart: Int
    var sort: LibraryView.Sort
}

/// The library's sections: by first letter of the name (by composer when sorted so),
/// one plain section when sorted by last played; other parts apart.
struct LibraryGrouping {
    struct Row: Identifiable, Hashable {
        var id: UUID
        var name: String
        var part: Int?
    }

    var sections: [(key: String, rows: [Row])] = []
    var others: [Row] = []

    init() {}

    init(_ items: [(id: UUID, title: String, composer: String?)], myPart: Int, sort: LibraryView.Sort) {
        let split = PartGrouping.split(items.map { (id: $0.id, title: $0.title) }, myPart: myPart)
        let aside = Set(split.others)
        var keys: [String] = []
        var rows: [String: [Row]] = [:]
        for item in items {
            let parsed = PartGrouping.parse(item.title)
            let row = Row(id: item.id, name: parsed.name, part: parsed.part)
            if aside.contains(item.id) { others.append(row); continue }
            let key: String = switch sort {
            case .title: Self.letter(parsed.name)
            case .composer: Self.letter(item.composer ?? "")
            case .recentlyPlayed: ""
            }
            if rows[key] == nil { keys.append(key) }
            rows[key, default: []].append(row)
        }
        sections = keys.map { (key: $0, rows: rows[$0] ?? []) }
    }

    /// "A" to "Z" by the name's first letter, accents ignored; "#" for anything else.
    static func letter(_ text: String) -> String {
        guard let first = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).first(where: { !$0.isWhitespace }),
              first.isLetter, first.isASCII else { return "#" }
        return String(first).uppercased()
    }
}

