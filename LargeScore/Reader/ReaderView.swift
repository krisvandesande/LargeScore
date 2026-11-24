import SwiftUI
import UIKit

/// A piece, full screen: the music fills the page, a strip at the foot holds the way
/// back, the title, the page and the size. Pages turn by a tap (left third back, the
/// rest forward), a swipe, or a pedal's keys. Opened from a programme, turning past
/// the last page goes on to the next piece, and back past the first to the one before.
struct ReaderView: View {
    let pieces: [Piece]
    var backTitle: LocalizedStringResource = "Library"
    /// Called whenever a piece comes up, to note when it was last played.
    var onShow: (Piece) -> Void = { _ in }

    init(piece: Piece, backTitle: LocalizedStringResource = "Library", onShow: @escaping (Piece) -> Void = { _ in }) {
        self.init(pieces: [piece], start: 0, backTitle: backTitle, onShow: onShow)
    }

    init(pieces: [Piece], start: Int, backTitle: LocalizedStringResource, onShow: @escaping (Piece) -> Void = { _ in }) {
        self.pieces = pieces
        self.backTitle = backTitle
        self.onShow = onShow
        _place = State(initialValue: ProgrammePlace(count: pieces.count, index: min(max(start, 0), max(pieces.count - 1, 0))))
    }

    @Environment(\.modelContext) private var context
    @State private var notes: NotesStore?
    @State private var annotating = false
    @State private var tool: NotesTool = .pen
    /// The line of handwriting being drawn, in page units.
    @State private var line: [CGPoint] = []
    @State private var writingNote = false

    @State private var place: ProgrammePlace
    /// Set when going back into the previous piece: it opens on its last page.
    @State private var startAtEnd = false
    @State private var laidOutPieceID: String?

    private var piece: Piece { pieces[place.index] }
    private var nextPiece: Piece? { place.hasNext ? pieces[place.index + 1] : nil }

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @State private var laidOut: LaidOutPiece?
    @State private var turner = PageTurner(pageCount: 0, halfPageTurns: false)
    @State private var failed = false

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
                        guard !annotating else { return }
                        location.x < proxy.size.width / 3 ? turn(forward: false) : turn(forward: true)
                    }
                    .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                        guard !annotating else { return }
                        if value.translation.width < -40 { turn(forward: true) }
                        else if value.translation.width > 40 { turn(forward: false) }
                    })
                    .task(id: ReaderKey(request: settings.layoutRequest(for: area, centred: true), piece: piece)) {
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

            if annotating, let notes {
                NotesPalette(tool: $tool, canUndo: notes.canUndo, pageText: pageText,
                             undo: { notes.undo() }, writtenNote: { writingNote = true },
                             previousPage: { turn(forward: false) }, nextPage: { turn(forward: true) },
                             done: { annotating = false })
            } else {
                ReaderStrip(title: piece.title, backTitle: backTitle, pageText: pageText,
                            nextTitle: nextPiece?.title,
                            back: { dismiss() }, next: { goToNextPiece() },
                            notes: notes?.canAnnotate == true ? { startAnnotating() } : nil)
            }
        }
        .environment(\.colorScheme, scheme)
        // The pedal's keys, except while a sheet over the reader needs the keyboard.
        .background { PedalKeys(active: !writingNote,
                                forward: { turn(forward: true) }, back: { turn(forward: false) }, close: { dismiss() }) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            notes = NotesStore(pieceID: piece.id, context: context)
            onShow(piece)
        }
        .sheet(isPresented: $writingNote) {
            if let notes { WrittenNoteSheet(store: notes) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: settings.halfPageTurns) { _, half in
            turner.update(pageCount: turner.pageCount, halfPageTurns: half && laidOut?.request.oneLine != true)
        }
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func page(area: CGSize, scheme: ColorScheme) -> some View {
        let ink: Color = scheme == .dark ? .white : .black
        if let laidOut, laidOut.pages.indices.contains(turner.page) {
            let current = laidOut.pages[turner.page]
            let marks = notes?.marks ?? []
            let geometry = barGeometry(laidOut, page: turner.page)
            if turner.halfway, laidOut.pages.indices.contains(turner.page + 1),
               let split = HalfPageSplit.split(current: current.systems,
                                               next: laidOut.pages[turner.page + 1].systems,
                                               pageHeight: current.viewBox.height) {
                ScoreCanvas(scene: current, upper: laidOut.pages[turner.page + 1], split: split, ink: ink, glyphWeight: settings.glyphWeight,
                            marks: marks, geometry: geometry, upperMarks: marks,
                            upperGeometry: barGeometry(laidOut, page: turner.page + 1))
                    .frame(width: area.width, height: area.height)
            } else {
                ScoreCanvas(scene: current, ink: ink, glyphWeight: settings.glyphWeight, marks: marks, geometry: geometry)
                    .frame(width: area.width, height: area.height)
                    .overlay {
                        if annotating, let geometry {
                            drawingLayer(geometry, scale: ScoreCanvas.scale(of: current, in: area))
                        }
                    }
            }
        } else if failed {
            Text("This music could not be read.")
                .font(.title2)
                .frame(width: area.width, height: area.height)
        } else {
            Color.clear.frame(width: area.width, height: area.height)
        }
    }

    private func barGeometry(_ laidOut: LaidOutPiece, page: Int) -> BarGeometry? {
        guard laidOut.pages.indices.contains(page) else { return nil }
        return BarGeometry(page: laidOut.pages[page], firstBar: laidOut.firstBars[page],
                           request: laidOut.request)
    }

    private func startAnnotating() {
        // Notes go on one whole page at a time.
        if turner.halfway { turner.back() }
        annotating = true
    }

    /// Takes the pen, the eraser or a mark while notes are being written. Touches are
    /// in points; the page is drawn at `scale` points a page unit.
    private func drawingLayer(_ geometry: BarGeometry, scale: CGFloat) -> some View {
        let toPage = { (p: CGPoint) in CGPoint(x: p.x / scale, y: p.y / scale) }
        return
        ZStack {
            Path { path in
                guard let first = line.first else { return }
                path.move(to: first)
                for point in line.dropFirst() { path.addLine(to: point) }
            }
            .stroke(Palette.notes, style: StrokeStyle(lineWidth: geometry.space * scale * 0.22, lineCap: .round, lineJoin: .round))
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    switch tool {
                    case .pen: line.append(value.location)
                    case .eraser:
                        guard let notes else { return }
                        notes.remove(geometry.marks(notes.marks, near: toPage(value.location), radius: geometry.space * 1.5))
                    case .mark: break
                    }
                }.onEnded { value in
                    switch tool {
                    case .pen:
                        if let mark = geometry.mark(ink: line.map(toPage)) { notes?.add(mark) }
                        line = []
                    case .mark(let kind):
                        if hypot(value.translation.width, value.translation.height) < 20,
                           let mark = geometry.mark(kind, at: toPage(value.location)) {
                            notes?.add(mark)
                        }
                    case .eraser: break
                    }
                })
                .accessibilityLabel("Music")
                .accessibilityHint("Draw or place the chosen mark here.")
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
        let count = (notes?.marks ?? []).filter { bars.contains($0.bar) }.count
        let noted = count > 0 ? Text(", ^[\(count) note](inflect: true)") : Text("")
        return Text("\(page), \(barText)\(top)\(noted)")
    }

    private func turn(forward: Bool) {
        if forward {
            if !turner.forward() { goToNextPiece() }
        } else if !turner.back(), place.previous() {
            startAtEnd = true
            showPiece()
        }
    }

    private func goToNextPiece() {
        guard place.next() else { return }
        startAtEnd = false
        showPiece()
    }

    /// A new piece came up without the person looking at the strip: say which.
    private func showPiece() {
        // Never show the old piece's page under the new title.
        laidOut = nil
        notes = NotesStore(pieceID: piece.id, context: context)
        onShow(piece)
        UIAccessibility.post(notification: .announcement, argument: piece.title)
    }

    private func layOut(area: CGSize) async {
        guard area.width > 100, area.height > 100 else { return }
        do {
            let shown = piece
            let result = try await loader.layOut(shown, request: settings.layoutRequest(for: area, centred: true))
            let page: Int
            if laidOutPieceID == shown.id {
                // Same piece, new size or orientation: keep the place by bar.
                let firstBar = laidOut?.firstBars[safe: turner.page] ?? 1
                page = result.firstBars.lastIndex(where: { $0 <= firstBar }) ?? 0
            } else {
                page = startAtEnd ? result.pages.count - 1 : 0
            }
            laidOut = result
            laidOutPieceID = shown.id
            if let next = nextPiece {
                // Engrave the next piece ahead, so turning into it is immediate.
                let request = settings.layoutRequest(for: area, centred: true)
                Task { _ = try? await loader.layOut(next, request: request) }
            }
            turner = PageTurner(pageCount: result.pages.count, halfPageTurns: settings.halfPageTurns && !result.request.oneLine, page: page)
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
    /// False while something else (the written note's field) must keep the keyboard.
    let active: Bool
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
        view.active = active
        if active { view.claimKeys() } else if view.isFirstResponder { view.resignFirstResponder() }
    }
}

final class KeyCatcherView: UIView {
    var forward: () -> Void = {}
    var back: () -> Void = {}
    var close: () -> Void = {}
    var active = true

    override var canBecomeFirstResponder: Bool { active }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimKeys()
    }

    func claimKeys() {
        guard active, window != nil, !isFirstResponder else { return }
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

private struct ReaderKey: Hashable {
    var request: LayoutRequest
    var piece: Piece
}

/// Layout B's strip: back, title, page, the next piece in a programme, size. Where
/// the row doesn't fit, the title goes first, since the person chose the piece and
/// the page number matters more.
struct ReaderStrip: View {
    let title: String
    let backTitle: LocalizedStringResource
    let pageText: Text?
    var nextTitle: String? = nil
    let back: () -> Void
    var next: () -> Void = {}
    var notes: (() -> Void)? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showTitle: true)
            row(showTitle: false)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) { backButton; Spacer(minLength: 0); notesButton }
                HStack(spacing: 16) { pageLabel; Spacer(minLength: 0); nextButton }
            }
        }
        .air(.horizontal, 32)
        .air(.vertical, 18)
        .frame(maxWidth: .infinity)
        // The music is what is read here, at its own size; past the largest standard
        // text size the strip stops growing, or it would leave one line of music. Its
        // controls show large in the Large Content Viewer (touch and hold).
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
            nextButton
            notesButton
        }
    }

    @ViewBuilder
    private var notesButton: some View {
        if let notes {
            Button("Notes", action: notes)
                .buttonStyle(.large)
                .accessibilityShowsLargeContentViewer()
                .fixedSize()
        }
    }

    @ViewBuilder
    private var nextButton: some View {
        if let nextTitle {
            Button(action: next) {
                Label { Text("Next: \(nextTitle)").lineLimit(1).fixedSize() } icon: { Image(systemName: "chevron.forward") }
                    .labelStyle(TrailingIcon())
            }
            .buttonStyle(.large)
            .accessibilityLabel(Text("Next piece: \(nextTitle)"))
            .accessibilityShowsLargeContentViewer()
            .accessibilityInputLabels([Text("Next"), Text("Next Piece")])
        }
    }

    private var backButton: some View {
        Button(action: back) {
            Label { Text(backTitle) } icon: { Image(systemName: "chevron.backward") }
                .fixedSize()
        }
        .buttonStyle(.large)
        .accessibilityLabel(Text("Back to \(Text(backTitle))"))
        .accessibilityShowsLargeContentViewer()
        .accessibilityInputLabels([Text(backTitle), Text("Back")])
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

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Words first, the icon after them: a button that goes forward.
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.title
            configuration.icon
        }
    }
}
