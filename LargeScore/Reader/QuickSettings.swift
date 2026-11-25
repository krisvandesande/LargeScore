import SwiftUI

/// The reading settings, changed from the reader without leaving the piece: for this
/// piece alone, or for all music. The page is laid out again behind the popover, so
/// each change shows at once.
struct QuickSettings: View {
    let pieceID: String
    @Environment(ReaderSettings.self) private var settings
    @State private var scope: Scope?

    enum Scope: Hashable { case piece, all }

    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        // Opens on this piece when it already has settings of its own.
        let scope = scope ?? (settings.hasOwnSettings(pieceID) ? .piece : .all)
        NavigationStack {
            Form {
                Section {
                    // Large, as in setup: the system's segments are too small to read here.
                    BigSegments(options: [(Scope.piece, LocalizedStringResource("This Piece")), (Scope.all, LocalizedStringResource("All Music"))], selection: scope) {
                        self.scope = $0
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Change For")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    // The size slider from setup, smaller to the left.
                    let step = sizeBinding(scope)
                    let name = scope == .piece ? String(localized: "Size for This Piece") : String(localized: "Size for All Music")
                    VStack(alignment: .leading, spacing: 4) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text(name)
                                Spacer(minLength: 16)
                                Text("Size \(step.wrappedValue + 1) of \(count)").foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                Text("Size \(step.wrappedValue + 1) of \(count)").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityHidden(true)
                        StepSlider(value: step.wrappedValue, count: count,
                                   smaller: "textformat.size.smaller", larger: "textformat.size.larger") {
                            step.wrappedValue = $0
                        }
                        .accessibilityLabel(Text(name))
                        .accessibilityValue(Text("Size \(step.wrappedValue + 1) of \(count)"))
                    }
                    .air(.top, 8)
                }
                Section {
                    FittingPicker(String(localized: "Lines"), value: bool(.boldLines, scope).wrappedValue ? String(localized: "Bold") : String(localized: "Thin"),
                                  selection: bool(.boldLines, scope)) {
                        Text("Thin").tag(false)
                        Text("Bold").tag(true)
                    }
                    let colour = colourBinding(scope)
                    FittingPicker(String(localized: "Color Mode"), value: String(localized: colour.wrappedValue.title), selection: colour) {
                        ForEach(ReaderSettings.PageColour.allCases) { colour in
                            Text(colour.title).tag(colour)
                        }
                    }
                    Toggle("Half-Page Turns", isOn: bool(.halfPageTurns, scope))
                    Toggle("Mark the First Bar", isOn: bool(.markFirstBar, scope))
                    Toggle("Repeats in Playing Order", isOn: bool(.playingOrder, scope))
                    Toggle("Key Reminders", isOn: bool(.keyReminders, scope))
                } footer: {
                    if scope == .all, settings.hasOwnSettings(pieceID) {
                        Text("This piece keeps its own settings.").formNote()
                    }
                }
                if settings.hasOwnSettings(pieceID) {
                    Section {
                        Button("Use the Settings for All Music") { settings.clearOwnSettings(pieceID) }
                    }
                }
            }
            .font(.title3)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        // Tall enough for what shows, with no empty room under the last row.
        .frame(idealWidth: 520, idealHeight: 676 + (settings.hasOwnSettings(pieceID) ? (scope == .all ? 126 : 86) : 0))
        // Solid: the music showing through the glass makes the words hard to read.
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func sizeBinding(_ scope: Scope) -> Binding<Int> {
        let settings = settings
        let piece = pieceID
        return scope == .piece
            ? Binding(get: { settings.sizeStep(for: piece) },
                      set: { settings.setSize($0 == settings.sizeStep ? nil : $0, for: piece) })
            : Binding(get: { settings.sizeStep }, set: { settings.sizeStep = $0 })
    }

    private func bool(_ choice: ReaderSettings.Choice, _ scope: Scope) -> Binding<Bool> {
        let settings = settings
        let piece = pieceID
        return Binding(
            get: { scope == .piece ? settings.bool(choice, for: piece) : settings.bool(choice, for: nil) },
            set: { on in
                guard scope == .all else { settings.set(choice, to: on, for: piece); return }
                switch choice {
                case .boldLines: settings.boldLines = on
                case .halfPageTurns: settings.halfPageTurns = on
                case .markFirstBar: settings.markFirstBar = on
                case .playingOrder: settings.playingOrder = on
                case .keyReminders: settings.keyReminders = on
                case .pageColour: break
                }
            })
    }

    private func colourBinding(_ scope: Scope) -> Binding<ReaderSettings.PageColour> {
        let settings = settings
        let piece = pieceID
        return Binding(
            get: { settings.pageColour(for: scope == .piece ? piece : nil) },
            set: { colour in
                if scope == .piece { settings.set(.pageColour, to: colour.rawValue, for: piece) } else { settings.pageColour = colour }
            })
    }
}
