import SwiftUI
import SwiftData

/// The Mac's window: a sidebar with the library, every programme and settings, for
/// adding music and building programmes at a desk. No Today: the iPad on the stand is
/// where a programme is played. Pieces dragged from the library onto a programme in
/// the sidebar are added to its end.
struct MacRootView: View {
    enum Item: Hashable {
        case library, settings
        case programme(UUID)
    }

    @Query(sort: \Programme.createdAt, order: .reverse) private var programmes: [Programme]
    @Environment(\.modelContext) private var context
    @Environment(ImportCoordinator.self) private var commands
    @Binding var section: RootView.Section
    @State private var selection: Item? = .library
    @State private var naming = false
    @State private var newName = ""
    @State private var deleting: Programme?
    @State private var dropTarget: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Library", systemImage: "books.vertical")
                    .tag(Item.library)
                Section("Programmes") {
                    ForEach(programmes) { programme in
                        programmeRow(programme)
                    }
                    Button { naming = true } label: {
                        Label("New Programme", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.accent)
                }
                Label("Settings", systemImage: "gearshape")
                    .tag(Item.settings)
            }
            .font(.title3)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detail
        }
        .onChange(of: section, initial: true) { _, now in
            switch now {
            case .library: selection = .library
            case .settings: selection = .settings
            case .programmes: break
            }
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
                if let deleting {
                    if selection == .programme(deleting.id) { selection = .library }
                    context.delete(deleting)
                    try? context.save()
                }
            }
        } message: {
            Text("The pieces stay in the library.")
        }
    }

    private func programmeRow(_ programme: Programme) -> some View {
        Label {
            Text(programme.name)
        } icon: {
            Image(systemName: "list.number")
        }
        .tag(Item.programme(programme.id))
        .dropDestination(for: String.self) { ids, _ in
            add(ids, to: programme)
        } isTargeted: { over in
            dropTarget = over ? programme.id : (dropTarget == programme.id ? nil : dropTarget)
        }
        .listRowBackground(dropTarget == programme.id ? Palette.accent.opacity(0.2) : nil)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = programme }
        }
        .accessibilityAction(named: Text("Delete")) { deleting = programme }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .programme(let id):
            if let programme = programmes.first(where: { $0.id == id }) {
                NavigationStack { ProgrammeDetail(programme: programme) }
                    .id(id)
            } else {
                LibraryView()
            }
        case .settings:
            SettingsView()
        case .library, nil:
            LibraryView()
        }
    }

    /// Library pieces dropped by id; an id that isn't a piece is ignored.
    private func add(_ ids: [String], to programme: Programme) -> Bool {
        let wanted = ids.compactMap(UUID.init(uuidString:))
        guard !wanted.isEmpty else { return false }
        let found = (try? context.fetch(FetchDescriptor<Score>(predicate: #Predicate { wanted.contains($0.id) }))) ?? []
        let scores = wanted.compactMap { id in found.first { $0.id == id } }
        guard !scores.isEmpty else { return false }
        programme.append(scores)
        try? context.save()
        return true
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else { return }
        let programme = Programme(name: name)
        context.insert(programme)
        try? context.save()
        selection = .programme(programme.id)
    }
}
