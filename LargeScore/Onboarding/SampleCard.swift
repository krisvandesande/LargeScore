import SwiftUI

/// The first page of a piece, engraved at the current settings, on a white card.
/// Used wherever a size or thickness is chosen by looking at it.
struct SampleCard: View {
    let piece: Piece
    var description: LocalizedStringResource

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.colorScheme) private var systemScheme
    @State private var page: SVGScene?

    private let inset: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let area = CGSize(width: max(proxy.size.width - inset * 2, 1),
                              height: max(proxy.size.height - inset * 2, 1))
            let dark = settings.pageScheme(system: systemScheme) == .dark
            ZStack(alignment: .topLeading) {
                dark ? Color.black : Color.white
                if let page {
                    ScoreCanvas(scene: page, ink: dark ? .white : .black)
                        .frame(width: area.width, height: area.height)
                        .padding(inset)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(.separator)))
            .task(id: settings.layoutRequest(for: area)) {
                guard area.width > 100, area.height > 60 else { return }
                if let laidOut = try? await loader.layOut(piece, request: settings.layoutRequest(for: area)) {
                    page = laidOut.pages.first
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(description))
    }
}

/// Smaller and Larger, with the step between them. One adjustable element for VoiceOver.
struct SizeStepper: View {
    @Environment(ReaderSettings.self) private var settings
    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        // One line while it fits the width, else stacked: never wider than the screen.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { smaller; label; larger }
            VStack(spacing: 16) { label; HStack(spacing: 16) { smaller; larger } }
            VStack(spacing: 16) { label; smaller; larger }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Music size")
        .accessibilityValue(Text("Size \(settings.sizeStep + 1) of \(count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if settings.sizeStep < count - 1 { settings.sizeStep += 1 }
            case .decrement: if settings.sizeStep > 0 { settings.sizeStep -= 1 }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("sizeStepper")
    }

    private var smaller: some View {
        Button("Smaller") { settings.sizeStep -= 1 }
            .buttonStyle(.large)
            .disabled(settings.sizeStep == 0)
            .frame(minWidth: 180)
    }

    private var larger: some View {
        Button("Larger") { settings.sizeStep += 1 }
            .buttonStyle(.large)
            .disabled(settings.sizeStep == count - 1)
            .frame(minWidth: 180)
    }

    private var label: some View {
        Text("Size \(settings.sizeStep + 1) of \(count)")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .fixedSize()
    }
}

/// Thin or Bold, as two large choices. Selected shows filled and with a checkmark.
struct LineChoice: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        HStack(spacing: 24) {
            option("Thin", selected: !settings.boldLines) { settings.boldLines = false }
            option("Bold", selected: settings.boldLines) { settings.boldLines = true }
        }
    }

    private func option(_ title: LocalizedStringResource, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(title)
            }
            .frame(minWidth: 180)
        }
        .buttonStyle(LargeButtonStyle(prominent: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
