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
    /// Drawn as the reader draws a page, edge to edge with the reader's margins, so
    /// the lines break where they will when reading; else a rounded card.
    var asPage = false

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.colorScheme) private var systemScheme
    @State private var scene: SVGScene?
    @State private var size: CGSize = .zero

    private let inset: CGFloat = 20
    /// The reader's own margins (ReaderView).
    private var margins: EdgeInsets {
        asPage ? EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12)
               : EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
    }

    private var area: CGSize {
        CGSize(width: max(size.width - margins.leading - margins.trailing, 1),
               height: max((fills ? size.height : maxHeight) - margins.top - margins.bottom, 1))
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
        // The paper alone sets the card's size; the music is drawn over it. Before, the
        // music's fixed frame from the last layout held the card at the old size when
        // the iPad turned, so the next layout used it too and ran off the screen.
        (dark ? Color.black : Color.white)
            .overlay(alignment: .topLeading) {
                if let page = scene {
                    ScoreCanvas(scene: page, ink: settings.pageInk(system: systemScheme), glyphWeight: settings.glyphWeight)
                        .frame(width: area.width, height: area.height)
                        .padding(margins)
                }
            }
            .clipped()
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil)
        .frame(height: fills ? nil : cardHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: asPage ? 0 : 26))
        .overlay(RoundedRectangle(cornerRadius: asPage ? 0 : 26).strokeBorder(asPage ? Color.clear : Color(.separator)))
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

/// The music size as a slider of seven steps, smaller to the left.
struct SizeStepper: View {
    @Environment(ReaderSettings.self) private var settings
    private var count: Int { ReaderSettings.staffHeights.count }

    var body: some View {
        StepSlider(value: settings.sizeStep, count: count,
                   smaller: "textformat.size.smaller", larger: "textformat.size.larger") {
            settings.sizeStep = $0
        }
        .accessibilityLabel("Music size")
        .accessibilityValue(Text("Size \(settings.sizeStep + 1) of \(count)"))
        .accessibilityIdentifier("sizeStepper")
    }
}

/// A slider that moves in whole steps, with a symbol at each end.
struct StepSlider: View {
    let value: Int
    let count: Int
    let smaller: String
    let larger: String
    let change: (Int) -> Void

    var body: some View {
        Slider(value: Binding(get: { Double(value) }, set: { change(Int($0.rounded())) }),
               in: 0...Double(count - 1), step: 1) {
            EmptyView()
        } minimumValueLabel: {
            Image(systemName: smaller).imageScale(.large).foregroundStyle(.secondary).accessibilityHidden(true)
        } maximumValueLabel: {
            Image(systemName: larger).imageScale(.large).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .tint(Palette.accent)
        .frame(minHeight: 56)
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

/// The room between lines as a slider standing upright: up for more room, down for less.
struct SpacingChoice: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                .imageScale(.large).foregroundStyle(.secondary).accessibilityHidden(true)
            GeometryReader { proxy in
                Slider(value: Binding(get: { Double(settings.lineGap) }, set: { settings.lineGap = Int($0.rounded()) }),
                       in: 0...Double(ReaderSettings.maxLineGap), step: 1)
                    .tint(Palette.accent)
                    .accessibilityLabel("Space between lines")
                    .accessibilityValue(Text("\(settings.lineGap + 1) of \(ReaderSettings.maxLineGap + 1)"))
                    .frame(width: proxy.size.height)
                    .rotationEffect(.degrees(-90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up")
                .imageScale(.large).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(width: 44)
    }
}

/// The music with its two sliders: the space between lines upright at the right
/// (up for more), the size along the foot (right for larger). `floating` lays them
/// over the music's edges, so the music keeps the full width of the reader's page;
/// otherwise they sit beside the card.
struct MusicSizePreview: View {
    let card: SampleCard
    var floating = false

    var body: some View {
        if floating {
            card
                .overlay(alignment: .trailing) {
                    SpacingChoice()
                        .padding(.vertical, 14)
                        .padding(.horizontal, 4)
                        .frame(maxHeight: 420)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.trailing, 4)
                }
                .overlay(alignment: .bottom) { sizeBar.padding(.horizontal, 80).padding(.bottom, 16) }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    card
                    SpacingChoice()
                }
                HStack(spacing: 12) {
                    SizeStepper()
                    Color.clear.frame(width: 44, height: 1)
                }
            }
        }
    }

    private var sizeBar: some View {
        SizeStepper()
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: Capsule())
    }
}

/// The three choices as named rows in one panel: the name on the left, its control
/// on the right, all controls the same width; at large text the name goes above.
struct MusicSizePanel: View {
    var rows: Set<Row> = [.size, .lines]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // Side by side at the standard sizes, the controls in one column; at the
        // accessibility sizes the name goes above and the control takes the width,
        // so no word in it breaks ("Sma / ller").
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    name
                    control
                }
            } else {
                HStack(spacing: 16) {
                    name.frame(maxWidth: .infinity, alignment: .leading)
                    control.frame(width: 460)
                }
            }
        }
        .air(.vertical, 14)
    }
}
