import SwiftUI

/// The reading settings, changed from the reader without leaving the piece. The page
/// is laid out again behind the popover, so each change shows at once. The size here
/// is this piece's own; the other settings are the same ones as in Settings.
struct QuickSettings: View {
    let pieceID: String
    @Environment(ReaderSettings.self) private var settings

    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        @Bindable var settings = settings
        let step = Binding(
            get: { settings.sizeStep(for: pieceID) },
            set: { settings.setSize($0 == settings.sizeStep ? nil : $0, for: pieceID) }
        )
        NavigationStack {
            Form {
                Section {
                    FittingStepper(String(localized: "Size for This Piece"),
                                   value: String(localized: "Size \(step.wrappedValue + 1) of \(count)"),
                                   binding: step, in: 0...(count - 1))
                    if step.wrappedValue != settings.sizeStep {
                        Button("Use Standard Size") { settings.setSize(nil, for: pieceID) }
                    }
                }
                Section {
                    FittingPicker(String(localized: "Lines"), value: settings.boldLines ? String(localized: "Bold") : String(localized: "Thin"), selection: $settings.boldLines) {
                        Text("Thin").tag(false)
                        Text("Bold").tag(true)
                    }
                    FittingPicker(String(localized: "Color Mode"), value: String(localized: settings.pageColour.title), selection: $settings.pageColour) {
                        ForEach(ReaderSettings.PageColour.allCases) { colour in
                            Text(colour.title).tag(colour)
                        }
                    }
                    Toggle("Half-Page Turns", isOn: $settings.halfPageTurns)
                    Toggle("Mark the First Bar", isOn: $settings.markFirstBar)
                    Toggle("Repeats in Playing Order", isOn: $settings.playingOrder)
                    Toggle("Key Reminders", isOn: $settings.keyReminders)
                }
            }
            .font(.title3)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .frame(idealWidth: 520, idealHeight: 560)
        // Solid: the music showing through the glass makes the words hard to read.
        .presentationBackground(Color(.systemGroupedBackground))
    }
}
