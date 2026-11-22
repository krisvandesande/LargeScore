import SwiftUI

/// First launch: the instrument (for the clef of the sample and the part to choose),
/// then the size and line thickness, chosen by looking at real music.
struct OnboardingView: View {
    enum Step: Int { case instrument, size, spacing, lines }

    @Environment(ReaderSettings.self) private var settings
    @State private var step = Step.instrument

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if step != .instrument {
                        Button {
                            step = Step(rawValue: step.rawValue - 1) ?? .instrument
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .buttonStyle(.large)
                    }
                    content(viewport: proxy.size)
                    // The sample fills the room above the button; the instrument
                    // grid leaves it empty.
                    if step == .instrument { Spacer(minLength: 0) }
                    footer
                }
                .air(.horizontal, 48)
                .air(.vertical, 40)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Content stops at the status bar instead of scrolling under it.
            .clipped()
        }
        .background(Palette.ground)
    }

    @ViewBuilder
    private func content(viewport: CGSize) -> some View {
        switch step {
        case .instrument:
            ScreenTitle(text: "Which instruments do you play?")
            InstrumentGrid()
        case .size:
            VStack(alignment: .leading, spacing: 12) {
                ScreenTitle(text: "Choose the music size")
                Text("Put the iPad on your stand and pick the size you read without effort.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SampleCard(piece: .sample(for: settings.instrument), description: "Sample music", fills: true)
                .frame(minHeight: 320)
            MusicSizePanel(rows: [.size])
        case .spacing:
            ScreenTitle(text: "Choose the space between lines")
            SampleCard(piece: .sample(for: settings.instrument), description: "Sample music", fills: true)
                .frame(minHeight: 320)
            MusicSizePanel(rows: [.spacing])
        case .lines:
            ScreenTitle(text: "Choose the line thickness")
            SampleCard(piece: .sample(for: settings.instrument), description: "Sample music", fills: true)
                .frame(minHeight: 320)
            MusicSizePanel(rows: [.lines])
        }
    }

    private var footer: some View {
        Button {
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            } else {
                settings.onboardingDone = true
            }
        } label: {
            Text(step == .lines ? "Start" : "Continue")
                .frame(minWidth: 360)
        }
        .buttonStyle(.largeProminent)
        .disabled(step == .instrument && settings.instruments.isEmpty)
        .frame(maxWidth: .infinity)
    }
}

/// Every instrument as a large button; the chosen one filled and ticked.
struct InstrumentGrid: View {
    @Environment(ReaderSettings.self) private var settings
    @ScaledMetric(relativeTo: .title3) private var minWidth: CGFloat = 220

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 16)], spacing: 16) {
            ForEach(Instrument.allCases) { instrument in
                let selected = settings.instruments.contains(instrument)
                Button {
                    if selected {
                        settings.instruments.removeAll { $0 == instrument }
                    } else {
                        settings.instruments.append(instrument)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        Text(instrument.title)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LargeButtonStyle(prominent: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
