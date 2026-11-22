import SwiftUI

/// A page of a piece, engraved at the current settings. Either as tall as its music
/// (up to `maxHeight`: no empty paper under the last line), or filling the space it
/// is given and drawn as the reader draws it (`fills`). Used wherever a size or
/// thickness is chosen by looking at it.
struct SampleCard: View {
    let piece: Piece
    var description: LocalizedStringResource
    /// The tallest the card may be; the page is laid out for this height.
    var maxHeight: CGFloat = 560
    /// Which page to show, for `fills`.
    var page: Int = 0
    var fills = false

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.colorScheme) private var systemScheme
    @State private var scene: SVGScene?
    @State private var size: CGSize = .zero

    private let inset: CGFloat = 20

    private var area: CGSize {
        CGSize(width: max(size.width - inset * 2, 1), height: max((fills ? size.height : maxHeight) - inset * 2, 1))
    }

    private var request: LayoutRequest { settings.layoutRequest(for: area, centred: fills) }

    /// The card's height: the music's lowest point plus the inset, never more than the page.
    private var cardHeight: CGFloat {
        guard let page = scene else { return min(maxHeight, 280) }
        let scale = ScoreCanvas.scale(of: page, in: area)
        let bottom = page.systems.filter { !$0.isNull }.map(\.maxY).max() ?? page.viewBox.maxY
        let music = (bottom - page.viewBox.minY) * scale
        return min(area.height, music) + inset * 2
    }

    var body: some View {
        let dark = settings.pageScheme(system: systemScheme) == .dark
        ZStack(alignment: .topLeading) {
            dark ? Color.black : Color.white
            if let page = scene {
                ScoreCanvas(scene: page, ink: dark ? .white : .black, glyphWeight: settings.glyphWeight)
                    .frame(width: area.width, height: area.height)
                    .padding(inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
        .frame(height: fills ? nil : cardHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(.separator)))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: request) {
            guard area.width > 100, area.height > 60 else { return }
            if let laidOut = try? await loader.layOut(piece, request: request) {
                scene = laidOut.pages[safe: min(page, laidOut.pages.count - 1)] ?? laidOut.pages.first
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(description))
    }
}

/// Choices side by side in one capsule, the chosen one filled and ticked: a
/// segmented control at a size that is easy to see and hit.
struct BigSegments<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringResource)]
    let selection: Value
    let choose: (Value) -> Void
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 56

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { choose(option.value) } label: {
                    HStack(spacing: 8) {
                        if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        Text(option.title)
                    }
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selected ? Palette.onAccent : Palette.accent)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(selected ? Palette.accent : .clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.buttonFill, in: Capsule())
    }
}

/// Smaller and Larger, with the size between them, in the same capsule as the other
/// choices. One adjustable element for VoiceOver.
struct SizeStepper: View {
    @Environment(ReaderSettings.self) private var settings
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 56
    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        HStack(spacing: 4) {
            step("Smaller", enabled: settings.sizeStep > 0) { settings.sizeStep -= 1 }
            Text("\(settings.sizeStep + 1) of \(count)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 8)
            step("Larger", enabled: settings.sizeStep < count - 1) { settings.sizeStep += 1 }
        }
        .padding(4)
        .background(Palette.buttonFill, in: Capsule())
        .accessibilityElement(children: .contain)
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

    private func step(_ title: LocalizedStringResource, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Palette.card, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Thin or Bold.
struct LineChoice: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        BigSegments(options: [(false, "Thin"), (true, "Bold")], selection: settings.boldLines) {
            settings.boldLines = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lines")
    }
}

/// Less, Normal or More room between lines.
struct SpacingChoice: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        BigSegments(options: LineSpacing.allCases.map { ($0, $0.title) }, selection: settings.lineSpacing) {
            settings.lineSpacing = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space between lines")
    }
}

/// The three choices as named rows in one panel: the name on the left, its control
/// on the right, all controls the same width; at large text the name goes above.
struct MusicSizePanel: View {
    var rows: Set<Row> = [.size, .spacing, .lines]

    enum Row { case size, spacing, lines }

    var body: some View {
        VStack(spacing: 0) {
            if rows.contains(.size) { row("Size") { SizeStepper() } }
            if rows.contains(.size) && rows.count > 1 { Divider() }
            if rows.contains(.spacing) { row("Space Between Lines") { SpacingChoice() } }
            if rows.contains(.spacing) && rows.contains(.lines) { Divider() }
            if rows.contains(.lines) { row("Lines") { LineChoice() } }
        }
        .padding(.horizontal, 20)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 26))
    }

    private func row<Control: View>(_ title: LocalizedStringResource, @ViewBuilder control: () -> Control) -> some View {
        let name = Text(title).font(.title3).fixedSize(horizontal: false, vertical: true)
        let control = control()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                name.frame(maxWidth: .infinity, alignment: .leading)
                control.frame(width: 460)
            }
            VStack(alignment: .leading, spacing: 12) {
                name
                control
            }
        }
        .air(.vertical, 14)
    }
}
