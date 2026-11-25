import SwiftUI
import SwiftData

/// Adding music: one page per file with its title, composer, part and a preview at
/// the reader's size. Several files start from a list.
struct ImportSheet: View {
    @Bindable var session: ImportSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.candidates.count == 1 && session.failures.isEmpty {
                    ImportDetail(candidate: $session.candidates[0])
                } else {
                    list
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addTitle) {
                        session.apply(to: context)
                        dismiss()
                    }
                    .disabled(!session.isReady)
                    .fontWeight(.semibold)
                }
            }
        }
        .font(.title3)
        .presentationSizing(.page)
    }

    private var addTitle: LocalizedStringResource {
        let count = session.candidates.count
        return count == 1 ? "Add" : "Add \(count) Pieces"
    }

    private var list: some View {
        List {
            if !session.candidates.isEmpty {
                Section {
                    ForEach($session.candidates) { $candidate in
                        NavigationLink {
                            ImportDetail(candidate: $candidate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.title)
                                    .font(.title3.weight(.semibold))
                                Text(candidate.parts.isEmpty ? String(localized: "Choose a part") : candidate.parts.map(\.name).joined(separator: ", "))
                                    .foregroundStyle(candidate.parts.isEmpty ? Palette.accent : .secondary)
                            }
                            .air(.vertical, 6)
                        }
                    }
                }
            }
            if !session.failures.isEmpty {
                Section {
                    ForEach(session.failures) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: failure.fileName).font(.title3.weight(.semibold))
                            Text(failure.reason.message).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .air(.vertical, 6)
                    }
                } header: {
                    Text("Not Added").formHeading()
                }
            }
        }
        .navigationTitle("Add Music")
    }
}

struct ImportDetail: View {
    @Binding var candidate: ImportSession.Candidate

    var body: some View {
        Form {
            Section {
                field("Title", text: $candidate.title, prompt: nil)
                field("Composer", text: $candidate.composer, prompt: "Optional")
            }
            if let existing = candidate.existing {
                Section {
                    choice(Text("Replace the Music"), selected: candidate.replace) { candidate.replace = true }
                    choice(Text("Add as a New Piece"), selected: !candidate.replace) { candidate.replace = false }
                } header: {
                    Text("\(existing.title) is already in the library").formHeading()
                } footer: {
                    if candidate.replace {
                        VStack(alignment: .leading, spacing: 8) {
                            if !(existing.annotations ?? []).isEmpty, existing.barCount > 0,
                               existing.barCount != candidate.barCount {
                                Text("This version has \(candidate.barCount) bars instead of \(existing.barCount). Check your notes: after the change they may sit on other bars.")
                                    .foregroundStyle(Palette.notes)
                            }
                            Text("Your notes and programmes stay. The previous version can be restored from the library.")
                        }
                        .formNote()
                    }
                }
            }
            Section {
                ForEach(candidate.file.parts) { part in
                    let chosen = candidate.parts.contains { $0.id == part.id }
                    choice(Text(verbatim: part.name.isEmpty ? part.id : part.name), selected: chosen) {
                        candidate.parts = PartPicking.toggle(part, in: candidate.parts, order: candidate.file.parts)
                    }
                }
            } header: {
                Text("Parts").formHeading()
            } footer: {
                if candidate.file.parts.count > 1 {
                    Text("Choose more than one to read several lines together.").formNote()
                }
            }
            if !candidate.parts.isEmpty {
                Section {
                    SampleCard(piece: Piece(id: "import-\(candidate.id)", title: candidate.title, composer: nil,
                                            partIDs: candidate.parts.map(\.id), source: .stored(candidate.data)),
                               description: "Preview of the first page", maxHeight: 360)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Preview").formHeading()
                }
            }
        }
        .navigationTitle(candidate.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The name above the field, so it's visible and stays when the field has text;
    /// heard once, as the field's own name.
    private func field(_ name: LocalizedStringResource, text: Binding<String>, prompt: LocalizedStringResource?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.headline)
                .foregroundStyle(Palette.quiet)
                .accessibilityHidden(true)
            TextField(text: text, prompt: prompt.map { Text($0) }) { Text(name) }
                .font(.title3)
                .accessibilityLabel(Text(name))
        }
        .air(.vertical, 4)
    }

    /// A row that is chosen, not opened: a checkmark, no chevron.
    private func choice(_ title: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                title
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .air(.vertical, 6)
        }
        // A choice reads as text; only its checkmark carries the accent.
        .tint(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ticking parts on and off, kept in the file's order, never down to none.
nonisolated enum PartPicking {
    static func toggle(_ part: ScorePart, in chosen: [ScorePart], order: [ScorePart]) -> [ScorePart] {
        var ids = Set(chosen.map(\.id))
        if ids.contains(part.id) {
            guard ids.count > 1 else { return chosen }
            ids.remove(part.id)
        } else {
            ids.insert(part.id)
        }
        return order.filter { ids.contains($0.id) }
    }
}
