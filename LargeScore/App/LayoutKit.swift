import SwiftUI

// Layout helpers for the "Small screens and large text" and chevron rules, shared with
// Project Chester, The Hideaway and Shootable so every project behaves the same way.

// MARK: - Air that grows with the text

/// Air that grows with the text: the base amount at the standard size, scaled by half
/// as much as the text grows, never more than twice, so the largest accessibility size
/// doesn't spend the screen on padding. On macOS, which has no Dynamic Type, the scale
/// stays 1 and nothing changes.
struct BreathingPadding: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let edges: Edge.Set
    let base: CGFloat

    func body(content: Content) -> some View {
        content.padding(edges, Self.amount(base, scale: scale))
    }

    nonisolated static func amount(_ base: CGFloat, scale: CGFloat) -> CGFloat {
        base * min(2, max(1, 1 + (scale - 1) / 2))
    }
}

extension View {
    /// Padding that grows with the text (see `BreathingPadding`). Unchanged at the
    /// standard size.
    func air(_ edges: Edge.Set = .all, _ base: CGFloat) -> some View {
        modifier(BreathingPadding(edges: edges, base: base))
    }

    /// A 44 pt touch area around a small control without moving the layout: pad the
    /// label inside the button with `touchTargetInset`, and the button outside with
    /// `touchTargetOutset`, by the same amount.
    func touchTargetInset(_ inset: CGFloat) -> some View {
        padding(inset).contentShape(Rectangle())
    }

    func touchTargetOutset(_ inset: CGFloat) -> some View {
        padding(-inset)
    }
}

// MARK: - Parts of a line

/// A detail line made of parts ("Mental Light · Physical Medium · 10 min"). At the
/// accessibility sizes each part takes a line of its own, so a wrap never starts a
/// line with "·" and nothing is cut. VoiceOver hears commas, never middots.
struct PartsText: View {
    let parts: [String]
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ parts: [String]) {
        self.parts = parts.filter { !$0.isEmpty }
    }

    var body: some View {
        Text(verbatim: parts.joined(separator: typeSize.isAccessibilitySize ? "\n" : " · "))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: parts.joined(separator: ", ")))
    }
}

// MARK: - Whole words

/// Text that never breaks a word in half: past the size where its longest word fits
/// the width, it stops growing (the system otherwise hyphenates). Font, weight and
/// colour come from the environment, as on any `Text`. Chester's `WholeWordsText`.
struct WholeWordsText: View {
    static let caps: [DynamicTypeSize] = [.accessibility5, .accessibility4, .accessibility3,
                                          .accessibility2, .accessibility1, .xxxLarge, .xxLarge]
    let text: String
    var alignment: HorizontalAlignment = .leading

    init(_ text: String, alignment: HorizontalAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        // Every word measured, not the one with the most letters.
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        WholeWordsLayout(alignment: alignment) {
            ForEach(Self.caps, id: \.self) { cap in
                // Measured, never drawn.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                        Text(verbatim: word).lineLimit(1).fixedSize()
                    }
                }
                .fixedSize()
                .dynamicTypeSize(...cap)
                .hidden()
                // Not fixed in height: the layout proposes the width and asks for
                // the height, and an unused copy proposed zero must draw nothing.
                Text(verbatim: text)
                    .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .dynamicTypeSize(...cap)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }
}

/// Pairs of (probe, text), largest first: the first text whose probe (its longest word
/// on one line) fits the offered width is the one sized and placed. Decided inside the
/// layout pass, never from geometry read back into state.
struct WholeWordsLayout: Layout {
    let alignment: HorizontalAlignment

    struct Cache { var widths: [Int: CGFloat] = [:] }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    private func chosen(_ subviews: Subviews, width: CGFloat?, cache: inout Cache) -> Int {
        guard let width, width.isFinite else { return 1 }
        var index = 1
        for pair in stride(from: 0, to: subviews.count - 1, by: 2) {
            index = pair + 1
            let probe: CGFloat
            if let known = cache.widths[pair] {
                probe = known
            } else {
                probe = subviews[pair].sizeThatFits(.unspecified).width
                cache.widths[pair] = probe
            }
            if probe <= width + 0.5 { break }
        }
        return index
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // A zero or infinite width is a measuring question ("how small / how big
        // could you be?"), not a place to lay words out: answer with the text's
        // ideal size. Laid out at width zero it was one letter a line, thousands of
        // points tall, and the screen around it went blank.
        let width = proposal.width.flatMap { $0.isFinite && $0 > 1 ? $0 : nil }
        let i = chosen(subviews, width: width, cache: &cache)
        let size = subviews[i].sizeThatFits(ProposedViewSize(width: width, height: nil))
        // The proposal's width when it is a real one, so the text wraps in it.
        // Centred and trailing text take the whole width offered, so they can align in it.
        // Never an infinite width: a button that fills its row measures with one,
        // and handing it back blanked the whole screen.
        if alignment != .leading, let width {
            return CGSize(width: width, height: size.height)
        }
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let i = chosen(subviews, width: bounds.width, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            if index == i {
                let x = alignment == .leading ? bounds.minX : alignment == .trailing ? bounds.maxX : bounds.midX
                let anchor: UnitPoint = alignment == .leading ? .topLeading : alignment == .trailing ? .topTrailing : .top
                subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: anchor,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
            } else {
                // Unsized, at the corner: there for measuring, never seen. Placed far
                // off screen instead, a list cell drew its whole content out of view.
                subview.place(at: bounds.origin, proposal: .zero)
            }
        }
    }
}

// MARK: - Switches that fit

/// At the accessibility sizes the switch goes under its label, which starts at the
/// row's edge and keeps its words whole, instead of squeezing beside the switch. The
/// system switch everywhere else, and on macOS.
struct FittingSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        FittingSwitchRow(configuration: configuration)
    }
}

private struct FittingSwitchRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                // Words only, from the row's edge: beside its icon a name squeezed
                // into "Remin / me".
                configuration.label
                    .labelStyle(.titleOnly)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)          // the switch carries the name
                Toggle(configuration).labelsHidden()
            }
        } else {
            Toggle(configuration)
        }
    }
}

extension ToggleStyle where Self == FittingSwitchStyle {
    static var fitting: FittingSwitchStyle { FittingSwitchStyle() }
}

// MARK: - Expanding in place

/// Something that expands in place: a solid triangle in the text colour on the left,
/// pointing right when closed and down when open (the house rule for every project).
///
/// With `wholeRow` (the default) the whole header toggles it and VoiceOver hears one
/// button that says whether it's expanded. A header that holds controls of its own —
/// a step's tick and title field — sets it false: then only the triangle toggles, as
/// a 44 pt button of its own.
struct TriangleDisclosureStyle: DisclosureGroupStyle {
    var wholeRow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let toggle = {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                configuration.isExpanded.toggle()
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            if wholeRow {
                Button(action: toggle) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        DisclosureTriangle(expanded: configuration.isExpanded)
                        configuration.label
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(configuration.isExpanded ? Text("Expanded") : Text("Collapsed"))
            } else {
                HStack(alignment: .center, spacing: 4) {
                    Button(action: toggle) {
                        DisclosureTriangle(expanded: configuration.isExpanded)
                            .frame(width: 28, height: 28)
                            .touchTargetInset(8)
                    }
                    .buttonStyle(.plain)
                    .touchTargetOutset(8)
                    .accessibilityLabel(configuration.isExpanded ? Text("Hide details") : Text("Show details"))
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

extension DisclosureGroupStyle where Self == TriangleDisclosureStyle {
    static var triangle: TriangleDisclosureStyle { TriangleDisclosureStyle() }
    /// Only the triangle toggles; the header's own controls stay usable.
    static var triangleOnly: TriangleDisclosureStyle { TriangleDisclosureStyle(wholeRow: false) }
}

/// The filled triangle on its own, for a header that toggles something itself.
struct DisclosureTriangle: View {
    let expanded: Bool
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 10

    var body: some View {
        Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.primary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: size * 1.4)
            .accessibilityHidden(true)
    }
}

/// Goes to the next screen: Apple's own disclosure indicator, for rows the system
/// doesn't draw one on.
struct ForwardChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.body.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Pills that grow

/// A pill that holds words. Its corner is the capsule's at the regular text size; when
/// larger text makes it taller, the corner keeps exactly that size and only the
/// straight sides grow, where a capsule would stretch into an oval.
nonisolated struct PillShape: InsettableShape {
    var radius: CGFloat
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let capsule = r.height / 2
        let corner = radius > 0 ? min(capsule, max(0, radius - inset)) : capsule
        return RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: r)
    }

    func inset(by amount: CGFloat) -> PillShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}

/// A word pill: words that wrap, air that grows, and the regular capsule's corner kept
/// as it grows. One place for every chip in the app.
struct Pill<Label: View, Background: ShapeStyle>: View {
    let background: Background
    var horizontal: CGFloat = 8
    var vertical: CGFloat = 3
    @ViewBuilder let label: () -> Label
    @State private var radius: CGFloat = 0

    var body: some View {
        label()
            .fixedSize(horizontal: false, vertical: true)
            .air(.horizontal, horizontal)
            .air(.vertical, vertical)
            .background(background, in: PillShape(radius: radius))
            .background {
                // The same pill at the regular size, measured for its corner.
                label()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, horizontal)
                    .padding(.vertical, vertical)
                    .dynamicTypeSize(.large)
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height / 2 } action: { radius = $0 }
            }
    }
}

// MARK: - Rows that wrap

/// Lays its children out like words in a paragraph: across, then onto the next line.
/// For chips, so a row of them never runs off the side of a phone at large text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            // Each child at most the whole width: a long chip wraps its own words.
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.indices.append(index)
            current.sizes.append(size)
            current.height = max(current.height, size.height)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Side margins that give way

/// A generous side margin at the standard sizes that gives way to the usual 16 pt at
/// the accessibility sizes, where every point of a small phone's width goes to the
/// words (a 32 pt margin each side left an iPhone SE's text a column of short lines).
struct GivingMargin: ViewModifier {
    let base: CGFloat
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        content.padding(.horizontal, size.isAccessibilitySize ? min(base, 16) : base)
    }
}

extension View {
    func sideMargin(_ base: CGFloat) -> some View {
        modifier(GivingMargin(base: base))
    }
}

// MARK: - Button words that stay whole

/// A button's label: icon and words at the standard sizes; at the accessibility
/// sizes the words alone, centred, and never broken mid-word (they stop growing
/// first). `WordsFirstLabelStyle` can't do the last part, since a style can't read
/// the words it is given.
struct WordsFirstLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var size

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        if size.isAccessibilitySize {
            WholeWordsText(title, alignment: .center)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

// MARK: - Pickers and steppers that fit

/// A form picker that keeps its value whole. The system's picker at the standard
/// sizes; at the accessibility sizes the system squeezed the value into what was
/// left beside the name ("An…ere", "On a…thm" on an iPhone SE), so there the value
/// goes under the name, from the same edge: one line, else stack. Chester's.
struct FittingPicker<Selection: Hashable, Content: View, Title: View>: View {
    /// The chosen option's name, as the list shows it.
    let value: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content
    @ViewBuilder let title: () -> Title
    /// The name for VoiceOver and Voice Control at the large sizes.
    let spokenTitle: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                Picker(selection: $selection, content: content, label: title)
                    .pickerStyle(.inline)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    title()
                        .labelStyle(.titleOnly)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: value)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A form row's name and value, not a tinted button title.
            .tint(.primary)
            .accessibilityLabel(Text(verbatim: spokenTitle))
            .accessibilityValue(Text(verbatim: value))
        } else {
            Picker(selection: $selection, content: content, label: title)
        }
    }
}

extension FittingPicker where Title == Text {
    init(_ title: String, value: String, selection: Binding<Selection>, @ViewBuilder content: @escaping () -> Content) {
        self.value = value
        self._selection = selection
        self.content = content
        self.title = { Text(verbatim: title) }
        self.spokenTitle = title
    }
}

/// A stepper whose name and value stay whole. Beside the system's buttons at the
/// standard sizes; at the accessibility sizes the name gets its own line and the
/// value and buttons go under it ("Tim / e esti- / mat / e" on an iPhone SE).
struct FittingStepper: View {
    let title: String
    let value: String
    let onIncrement: (() -> Void)?
    let onDecrement: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init<V: Strideable>(_ title: String, value: String, binding: Binding<V>, in range: ClosedRange<V>, step: V.Stride = 1) {
        self.title = title
        self.value = value
        onIncrement = binding.wrappedValue < range.upperBound
            ? { binding.wrappedValue = min(range.upperBound, binding.wrappedValue.advanced(by: step)) } : nil
        onDecrement = binding.wrappedValue > range.lowerBound
            ? { binding.wrappedValue = max(range.lowerBound, binding.wrappedValue.advanced(by: -step)) } : nil
    }

    var body: some View {
        let stepper = Stepper {
            Text(verbatim: title)
        } onIncrement: {
            onIncrement?()
        } onDecrement: {
            onDecrement?()
        }
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)       // the stepper carries the name
                HStack {
                    Text(verbatim: value)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    Spacer(minLength: 8)
                    stepper.labelsHidden()
                        .accessibilityLabel(Text(verbatim: title))
                        .accessibilityValue(Text(verbatim: value))
                }
            }
        } else {
            Stepper {
                LabeledContent(title, value: value)
            } onIncrement: {
                onIncrement?()
            } onDecrement: {
                onDecrement?()
            }
            .accessibilityValue(Text(verbatim: value))
        }
    }
}
