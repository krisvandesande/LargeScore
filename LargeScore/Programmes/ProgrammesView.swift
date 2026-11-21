import SwiftUI
import SwiftData

/// Every programme; one can be Today's.
struct ProgrammesView: View {
    @Query(sort: \Programme.createdAt, order: .reverse) private var programmes: [Programme]
    @Environment(\.modelContext) private var context
    @Environment(ImportCoordinator.self) private var commands
    @State private var naming = false
    @State private var newName = ""
    @State private var deleting: Programme?
    @State private var path: [Programme] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if programmes.isEmpty {
                    VStack(spacing: 20) {
                        Text("No programmes yet")
                            .font(.title.weight(.semibold))
                        Text("A programme lists the pieces for a rehearsal or concert, in the order you play them.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Button("New Programme") { naming = true }
                            .buttonStyle(.largeProminent)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640)
                    .air(.all, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(programmes) { programme in
                            NavigationLink(value: programme) {
                                ProgrammeRow(programme: programme)
                            }
                            .contextMenu {
                                if !programme.isToday {
                                    Button("Use Today", systemImage: "star") {
                                        programme.makeToday(in: context)
                                        try? context.save()
                                    }
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = programme }
                            }
                            .accessibilityAction(named: Text("Delete")) { deleting = programme }
                        }
                        .onDelete { offsets in deleting = offsets.first.map { programmes[$0] } }
                    }
                    .font(.title3)
                }
            }
            .background(Palette.ground)
            .navigationTitle("Programmes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Programme") { naming = true }
                }
            }
            .navigationDestination(for: Programme.self) { programme in
                ProgrammeDetail(programme: programme)
            }
            .onChange(of: commands.namingProgramme, initial: true) { _, asked in
                if asked { naming = true; commands.namingProgramme = false }
            }
            .alert("New Programme", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") { create() }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("For example the rehearsal or concert it's for.")
            }
            .confirmationDialog(Text("Delete \(deleting?.name ?? "")?"), isPresented: present($deleting), titleVisibility: .visible) {
                Button("Delete Programme", role: .destructive) {
                    if let deleting { context.delete(deleting); try? context.save() }
                }
            } message: {
                Text("The pieces stay in the library.")
            }
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else { return }
        let programme = Programme(name: name)
        context.insert(programme)
        try? context.save()
        path = [programme]
    }
}

private struct ProgrammeRow: View {
    let programme: Programme

    var body: some View {
        let count = programme.orderedEntries.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(programme.name)
                    .font(.title2.weight(.semibold))
                if programme.isToday {
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Palette.accent, in: PillShape(radius: 14))
                }
            }
            Text("^[\(count) piece](inflect: true)")
                .foregroundStyle(.secondary)
        }
        .air(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

func present<T>(_ item: Binding<T?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

/// A programme's pieces in order: open one to play from there, or reorder, remove
/// and add pieces.
struct ProgrammeDetail: View {
    @Bindable var programme: Programme
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var adding = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        ProgrammePieces(programme: programme, editing: editing, backTitle: LocalizedStringResource(stringLiteral: programme.name),
                        addPieces: { adding = true })
            .navigationTitle(programme.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Rename") {
                        newName = programme.name
                        renaming = true
                    }
                    Button(editing ? "Done" : "Reorder") { withAnimation { editing.toggle() } }
                        .disabled(programme.orderedEntries.isEmpty && !editing)
                }
            }
            .sheet(isPresented: $adding) { AddPiecesSheet(programme: programme) }
            .alert("Rename Programme", isPresented: $renaming) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { programme.name = name; try? context.save() }
                }
            }
    }
}

/// The numbered list both a programme's page and the Today tab show.
struct ProgrammePieces: View {
    let programme: Programme
    var editing = false
    var backTitle: LocalizedStringResource
    /// Shown as a large button after the last piece, where it's always in sight.
    var addPieces: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @State private var openAt: Int?

    var body: some View {
        let entries = programme.orderedEntries
        List {
            Section {
                Toggle("Today’s Programme", isOn: Binding(
                    get: { programme.isToday },
                    set: { on in
                        if on { programme.makeToday(in: context) } else { programme.isToday = false }
                        try? context.save()
                    }))
                    .font(.title3)
                    .air(.vertical, 6)
            } footer: {
                Text("Today’s programme is what Large Score opens on.").formNote()
            }
            Section {
                if entries.isEmpty {
                    Text("No pieces yet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .air(.vertical, 8)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        openAt = index
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            Text("\(index + 1)")
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 36, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.score?.title ?? "")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if let composer = entry.score?.composer, !composer.isEmpty {
                                    Text(composer)
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !editing { ForwardChevron() }
                        }
                        .air(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(editing)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(index + 1), \(entry.score?.title ?? "")"))
                }
                .onMove { source, destination in
                    programme.move(from: source, to: destination)
                    try? context.save()
                }
                .onDelete { offsets in
                    programme.remove(at: offsets, in: context)
                    try? context.save()
                }
            }
            if let addPieces, !editing {
                Section {
                    Button(action: addPieces) {
                        Label("Add Pieces", systemImage: "plus")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .air(.vertical, 8)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .fullScreenCover(item: Binding(get: { openAt.map(OpenAt.init) }, set: { openAt = $0?.index })) { open in
            ReaderView(pieces: programme.scores.map(\.piece), start: open.index, backTitle: backTitle) { piece in
                programme.scores.first { $0.id.uuidString == piece.id }?.lastOpenedAt = .now
                try? context.save()
            }
        }
    }

    private struct OpenAt: Identifiable {
        var index: Int
        var id: Int { index }
    }
}

/// Library pieces to add, ticked and added in one go, in the library's order.
private struct AddPiecesSheet: View {
    let programme: Programme
    @Query(sort: [SortDescriptor(\Score.title, comparator: .localizedStandard)]) private var scores: [Score]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(scores) { score in
                let selected = chosen.contains(score.id)
                Button {
                    if selected { chosen.remove(score.id) } else { chosen.insert(score.id) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(score.title).font(.title3.weight(.semibold))
                            if let composer = score.composer, !composer.isEmpty {
                                Text(composer).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .air(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .tint(.primary)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            .font(.title3)
            .overlay {
                if scores.isEmpty {
                    Text("The library is empty. Add music there first.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .air(.all, 48)
                }
            }
            .navigationTitle("Add Pieces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen.count > 1 ? "Add \(chosen.count) Pieces" : "Add") {
                        programme.append(scores.filter { chosen.contains($0.id) })
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .presentationSizing(.page)
    }
}

/// The Today tab: the pinned programme, ready to play.
struct TodayView: View {
    @Query(filter: #Predicate<Programme> { $0.isToday }) private var today: [Programme]
    let showProgrammes: () -> Void

    var body: some View {
        NavigationStack {
            if let programme = today.first {
                ProgrammePieces(programme: programme, backTitle: "Today")
                    .navigationTitle(programme.name)
            } else {
                VStack(spacing: 20) {
                    Text("No programme for today")
                        .font(.title.weight(.semibold))
                    Text("Choose one in Programmes.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Button("Go to Programmes", action: showProgrammes)
                        .buttonStyle(.large)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .air(.all, 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.ground)
                .navigationTitle("Today")
            }
        }
    }
}
