import SwiftUI
import UIKit

/// A piece, full screen: the music fills the page, a strip at the foot holds the way
/// back, the title, the page and the size. Pages turn by a tap (left third back, the
/// rest forward), a swipe, or a pedal's keys.
struct ReaderView: View {
    let piece: Piece
    var backTitle: LocalizedStringResource = "Library"

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @State private var laidOut: LaidOutPiece?
    @State private var turner = PageTurner(pageCount: 0, halfPageTurns: false)
    @State private var failed = false
    @State private var choosingSize = false

    /// Even and small at the sides: the staff runs from one margin to the other, so
    /// the music gets every point of the width the eye can use.
    private let margins = EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12)

    var body: some View {
        let scheme = settings.pageScheme(system: systemScheme)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let area = CGSize(width: max(proxy.size.width - margins.leading - margins.trailing, 1),
                                  height: max(proxy.size.height - margins.top - margins.bottom, 1))
                page(area: area, scheme: scheme)
                    .padding(margins)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        location.x < proxy.size.width / 3 ? turn(forward: false) : turn(forward: true)
                    }
                    .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                        if value.translation.width < -40 { turn(forward: true) }
                        else if value.translation.width > 40 { turn(forward: false) }
                    })
                    .task(id: settings.layoutRequest(for: area)) {
                        await layOut(area: area)
                    }
            }
            .background(scheme == .dark ? Color.black : Color.white)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(piece.title))
            .accessibilityValue(pageDescription)
            .accessibilityAdjustableAction { direction in
                turn(forward: direction == .increment)
            }
            .accessibilityIdentifier("page")

            ReaderStrip(title: piece.title, backTitle: backTitle, pageText: pageText,
                        back: { dismiss() }, size: { choosingSize = true })
        }
        .environment(\.colorScheme, scheme)
        .background { PedalKeys(forward: { turn(forward: true) }, back: { turn(forward: false) }, close: { dismiss() }) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: settings.halfPageTurns) { _, half in
            turner.update(pageCount: turner.pageCount, halfPageTurns: half)
        }
        .sheet(isPresented: $choosingSize) {
            SizeSheet(piece: piece)
        }
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func page(area: CGSize, scheme: ColorScheme) -> some View {
        let ink: Color = scheme == .dark ? .white : .black
        if let laidOut, laidOut.pages.indices.contains(turner.page) {
            let current = laidOut.pages[turner.page]
            if turner.halfway, laidOut.pages.indices.contains(turner.page + 1),
               let split = HalfPageSplit.split(current: current.systems,
                                               next: laidOut.pages[turner.page + 1].systems,
                                               pageHeight: current.viewBox.height) {
                ScoreCanvas(scene: current, upper: laidOut.pages[turner.page + 1], split: split, ink: ink, glyphWeight: settings.glyphWeight)
                    .frame(width: area.width, height: area.height)
            } else {
                ScoreCanvas(scene: current, ink: ink, glyphWeight: settings.glyphWeight)
                    .frame(width: area.width, height: area.height)
            }
        } else if failed {
            Text("This music could not be read.")
                .font(.title2)
                .frame(width: area.width, height: area.height)
        } else {
            Color.clear.frame(width: area.width, height: area.height)
        }
    }

    private var pageText: Text? {
        guard let laidOut, !laidOut.pages.isEmpty else { return nil }
        return Text("Page \(turner.page + 1) of \(laidOut.pages.count)")
    }

    private var pageDescription: Text {
        guard let laidOut, !laidOut.pages.isEmpty else { return Text("") }
        let page = Text("Page \(turner.page + 1) of \(laidOut.pages.count)")
        guard let bars = laidOut.bars(onPage: turner.page) else { return page }
        let barText = bars.lowerBound == bars.upperBound
            ? Text("bar \(bars.lowerBound)")
            : Text("bars \(bars.lowerBound) to \(bars.upperBound)")
        let top = turner.halfway ? Text(", top shows page \(turner.page + 2)") : Text("")
        return Text("\(page), \(barText)\(top)")
    }

    private func turn(forward: Bool) {
        if forward { turner.forward() } else { turner.back() }
    }

    private func layOut(area: CGSize) async {
        guard area.width > 100, area.height > 100 else { return }
        do {
            let result = try await loader.layOut(piece, request: settings.layoutRequest(for: area))
            // Keep the place by bar when the size or orientation changes.
            let firstBar = laidOut?.firstBars[safe: turner.page] ?? 1
            let page = result.firstBars.lastIndex(where: { $0 <= firstBar }) ?? 0
            laidOut = result
            turner = PageTurner(pageCount: result.pages.count, halfPageTurns: settings.halfPageTurns, page: page)
            failed = false
        } catch {
            failed = true
        }
    }
}

/// The keys page-turn pedals send (arrows, Page Up and Down, Space), taken by a
/// first-responder view as key commands: they work wherever the reader is, and the
/// titles show in the iPad's shortcut overlay.
private struct PedalKeys: UIViewRepresentable {
    let forward: () -> Void
    let back: () -> Void
    let close: () -> Void

    func makeUIView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: KeyCatcherView, context: Context) {
        view.forward = forward
        view.back = back
        view.close = close
        view.claimKeys()
    }
}

final class KeyCatcherView: UIView {
    var forward: () -> Void = {}
    var back: () -> Void = {}
    var close: () -> Void = {}

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimKeys()
    }

    func claimKeys() {
        guard window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }

    override var keyCommands: [UIKeyCommand]? {
        let next = String(localized: "Next Page"), previous = String(localized: "Previous Page")
        func command(_ input: String, _ title: String?, _ action: Selector) -> UIKeyCommand {
            let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
            if let title { command.discoverabilityTitle = title } else { command.attributes = .hidden }
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
        return [
            command(UIKeyCommand.inputRightArrow, next, #selector(nextPage)),
            command(UIKeyCommand.inputDownArrow, nil, #selector(nextPage)),
            command(" ", nil, #selector(nextPage)),
            command(UIKeyCommand.inputLeftArrow, previous, #selector(previousPage)),
            command(UIKeyCommand.inputUpArrow, nil, #selector(previousPage)),
            command(UIKeyCommand.inputEscape, String(localized: "Close"), #selector(closeReader)),
        ]
    }

    /// Page Up and Page Down arrive as presses rather than key commands.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            switch press.key?.keyCode {
            case .keyboardPageDown?: forward(); handled = true
            case .keyboardPageUp?: back(); handled = true
            default: break
            }
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    @objc private func nextPage() { forward() }
    @objc private func previousPage() { back() }
    @objc private func closeReader() { close() }
}

/// Layout B's strip: back, title, page, size. At the accessibility sizes the title
/// goes first, since the person chose the piece and the page number matters more.
struct ReaderStrip: View {
    let title: String
    let backTitle: LocalizedStringResource
    let pageText: Text?
    let back: () -> Void
    let size: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showTitle: true)
            row(showTitle: false)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) { backButton; Spacer(minLength: 0); sizeButton }
                pageLabel
            }
        }
        .air(.horizontal, 32)
        .air(.vertical, 18)
        .frame(maxWidth: .infinity)
        // The music is what is read here, at its own size; past the largest standard
        // text size the strip stops growing, or it would leave one line of music.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .top) { Divider() }
    }

    private func row(showTitle: Bool) -> some View {
        HStack(spacing: 24) {
            backButton
            if showTitle {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            pageLabel
            sizeButton
        }
    }

    private var backButton: some View {
        Button(action: back) {
            Label { Text(backTitle) } icon: { Image(systemName: "chevron.backward") }
                .fixedSize()
        }
        .buttonStyle(.large)
        .accessibilityLabel(Text("Back to \(Text(backTitle))"))
        .accessibilityInputLabels([Text(backTitle), Text("Back")])
    }

    private var sizeButton: some View {
        Button("Size", action: size)
            .buttonStyle(.large)
            .fixedSize()
            .accessibilityLabel("Music Size")
            .accessibilityInputLabels([Text("Size"), Text("Music Size")])
    }

    @ViewBuilder
    private var pageLabel: some View {
        if let pageText {
            pageText
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

/// The size, changed while reading: the same choice as at the start.
struct SizeSheet: View {
    let piece: Piece
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                SampleCard(piece: piece, description: "The music at this size")
                    .frame(minHeight: 280)
                SizeStepper()
                SpacingChoice()
                LineChoice()
            }
            .air(.all, 32)
            .navigationTitle("Music Size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .presentationSizing(.page)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
