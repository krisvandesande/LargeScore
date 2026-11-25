import SwiftUI
import UIKit

/// A piece, full screen: the music fills the page, a strip at the foot holds the way
/// back, the title, the page and the size. Pages turn by a tap (left third back, the
/// rest forward), a swipe, or a pedal's keys. Opened from a programme, turning past
/// the last page goes on to the next piece, and back past the first to the one before.
struct ReaderView: View {
    /// Kept as they were when the reader opened: a programme changed on another device
    /// mid-concert must not swap the piece on the stand or run the place off the end.
    @State private var pieces: [Piece]
    /// The list as the caller has it now. Taken over only while it holds the same
    /// pieces in the same order: a new version or music that finished downloading.
    private let incoming: [Piece]
    var backTitle: LocalizedStringResource = "Library"
    /// Called whenever a piece comes up, to note when it was last played.
    var onShow: (Piece) -> Void = { _ in }

    init(piece: Piece, backTitle: LocalizedStringResource = "Library", onShow: @escaping (Piece) -> Void = { _ in }) {
        self.init(pieces: [piece], start: 0, backTitle: backTitle, onShow: onShow)
    }

    init(pieces: [Piece], start: Int, backTitle: LocalizedStringResource, onShow: @escaping (Piece) -> Void = { _ in }) {
        _pieces = State(initialValue: pieces)
        incoming = pieces
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

    private var piece: Piece { pieces[min(place.index, pieces.count - 1)] }
    private var nextPiece: Piece? { place.hasNext ? pieces[place.index + 1] : nil }

    @Environment(ReaderSettings.self) private var settings
    @Environment(ScoreLoader.self) private var loader
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The first bar is tinted for a moment after a turn forward.
    @State private var tintFirstBar = false
    @State private var tintTask: Task<Void, Never>?
    @State private var aheadTask: Task<Void, Never>?
    @State private var laidOut: LaidOutPiece?
    @State private var turner = PageTurner(pageCount: 0, halfPageTurns: false)
    @State private var failed = false

    /// Even and small at the sides: the staff runs from one margin to the other, so
    /// the music gets every point of the width the eye can use.
    private let margins = EdgeInsets(top: 16, leading: 12, bottom: 12, trailing: 12)

    var body: some View {
        let scheme = settings.pageScheme(system: systemScheme, piece: piece.id)
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
                    .task(id: ReaderKey(request: settings.layoutRequest(for: area, centred: true, piece: piece.id), piece: piece, index: place.index)) {
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
                            notes: notes?.canAnnotate == true ? { startAnnotating() } : nil,
                            pieceID: piece.id)
            }
        }
        .environment(\.colorScheme, scheme)
        // The pedal's keys, except while a sheet over the reader needs the keyboard.
        // Not while a line is being drawn either: the page under the pen must stay.
        .background { PedalKeys(active: !writingNote && line.isEmpty,
                                forward: { turn(forward: true) }, back: { turn(forward: false) }, close: { dismiss() }) }
        .onAppear {
            AwakeReaders.opened()
            notes = NotesStore(pieceID: piece.id, context: context)
            onShow(piece)
        }
        .sheet(isPresented: $writingNote) {
            if let notes { WrittenNoteSheet(store: notes) }
        }
        .onDisappear {
            AwakeReaders.closed()
            aheadTask?.cancel()
        }
        .onChange(of: settings.bool(.halfPageTurns, for: piece.id)) { _, half in
            turner.update(pageCount: turner.pageCount, halfPageTurns: half && laidOut?.request.oneLine != true)
        }
        .onChange(of: turner.page) { old, new in
            notes?.forgetUndo()
            if new > old { showFirstBar() }
        }
        .onChange(of: incoming) { _, now in
            if now.map(\.id) == pieces.map(\.id) { pieces = now }
        }
        .persistentSystemOverlays(.hidden)
    }

    @ViewBuilder
    private func page(area: CGSize, scheme: ColorScheme) -> some View {
        let ink = settings.pageInk(system: systemScheme, piece: piece.id)
        if let laidOut, laidOut.pages.indices.contains(turner.page) {
            let current = laidOut.pages[turner.page]
            let marks = notes?.marks ?? []
            let geometry = barGeometry(laidOut, page: turner.page)
            if turner.halfway, laidOut.pages.indices.contains(turner.page + 1),
               let split = HalfPageSplit.split(current: current.systems,
                                               next: laidOut.pages[turner.page + 1].systems,
                                               pageHeight: current.viewBox.height) {
                ScoreCanvas(scene: current, upper: laidOut.pages[turner.page + 1], split: split, ink: ink, glyphWeight: settings.glyphWeight(for: piece.id),
                            marks: marks, geometry: geometry, upperMarks: marks,
                            upperGeometry: barGeometry(laidOut, page: turner.page + 1))
                    .frame(width: area.width, height: area.height)
            } else {
                ScoreCanvas(scene: current, ink: ink, glyphWeight: settings.glyphWeight(for: piece.id), marks: marks, geometry: geometry)
                    .frame(width: area.width, height: area.height)
                    .overlay(alignment: .topLeading) {
                        if tintFirstBar, !annotating, let box = current.measures.first(where: { !$0.isNull }) {
                            let scale = ScoreCanvas.scale(of: current, in: area)
                            let space = (geometry?.space ?? 0) * scale
                            RoundedRectangle(cornerRadius: space)
                                .fill(Palette.accent.opacity(0.22))
                                .frame(width: box.width * scale + space, height: box.height * scale + space * 4)
                                .offset(x: (box.minX - current.viewBox.minX) * scale - space / 2,
                                        y: (box.minY - current.viewBox.minY) * scale - space * 2)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        }
                    }
                    .overlay {
                        if annotating, let geometry {
                            drawingLayer(geometry, scale: ScoreCanvas.scale(of: current, in: area), origin: current.viewBox.origin)
                        }
                    }
            }
        } else if failed {
            Text(piece.isMissing ? "This music is still on its way from iCloud." : "This music could not be read.")
                .font(.title2)
                .frame(width: area.width, height: area.height)
        } else {
            Color.clear.frame(width: area.width, height: area.height)
        }
    }

    private func barGeometry(_ laidOut: LaidOutPiece, page: Int) -> BarGeometry? {
        guard laidOut.pages.indices.contains(page) else { return nil }
        return BarGeometry(page: laidOut.pages[page], numbers: laidOut.pageBars[page],
                           request: laidOut.request)
    }

    /// Tints the first bar, then lets it fade (or go at once with Reduce Motion).
    private func showFirstBar() {
        guard settings.bool(.markFirstBar, for: piece.id) else { return }
        tintTask?.cancel()
        tintFirstBar = true
        tintTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { tintFirstBar = false }
        }
    }

    private func startAnnotating() {
        // Notes go on one whole page at a time.
        if turner.halfway { turner.back() }
        annotating = true
    }

    /// Takes the pen, the eraser or a mark while notes are being written. Touches are
    /// in points; the page is drawn at `scale` points a page unit, from `origin` (a
    /// screen of one long line starts partway along it).
    private func drawingLayer(_ geometry: BarGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let toPage = { (p: CGPoint) in CGPoint(x: origin.x + p.x / scale, y: origin.y + p.y / scale) }
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
        // Until the piece is laid out its pages aren't known: a second press of the
        // pedal while the next piece comes up must not skip it.
        guard laidOut != nil || failed else { return }
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
        laidOutPieceID = nil
        failed = false
        line = []
        notes = NotesStore(pieceID: piece.id, context: context)
        onShow(piece)
        UIAccessibility.post(notification: .announcement, argument: piece.title)
    }

    private func layOut(area: CGSize) async {
        guard area.width > 100, area.height > 100 else { return }
        do {
            let shown = piece
            let index = place.index
            let result = try await loader.layOut(shown, request: settings.layoutRequest(for: area, centred: true, piece: shown.id))
            // A layout for a size or piece that has since gone is dropped.
            guard !Task.isCancelled, place.index == index, piece == shown else { return }
            let page: Int
            if laidOutPieceID == shown.id, let old = laidOut, old.request.playingOrder || result.request.playingOrder {
                // In playing order a bar can come twice: keep the place by how far through.
                let through = old.pages.count > 1 ? Double(turner.page) / Double(old.pages.count - 1) : 0
                page = Int((through * Double(max(result.pages.count - 1, 0))).rounded())
            } else if laidOutPieceID == shown.id {
                // Same piece, new size or orientation: keep the place by bar.
                let firstBar = laidOut?.firstBars[safe: turner.page] ?? 1
                page = result.firstBars.lastIndex(where: { $0 <= firstBar }) ?? 0
            } else {
                page = startAtEnd ? result.pages.count - 1 : 0
            }
            laidOut = result
            laidOutPieceID = shown.id
            loader.readerArea = area
            if place.hasNext {
                // The rest of the programme laid out ahead, the next piece first, so
                // turning into any of them is immediate.
                let rest = Array(pieces[(place.index + 1)...])
                let settings = settings
                aheadTask?.cancel()
                aheadTask = Task(priority: .utility) {
                    await loader.layOutAhead(rest) { settings.layoutRequest(for: area, centred: true, piece: $0.id) }
                }
            }
            turner = PageTurner(pageCount: result.pages.count, halfPageTurns: settings.bool(.halfPageTurns, for: shown.id) && !result.request.oneLine, page: page)
            failed = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
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

    private var activation: NSObjectProtocol?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        claimKeys()
        // Coming back to the front can leave no first responder: take the keys again.
        if window != nil, activation == nil {
            activation = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.claimKeys() }
            }
        } else if window == nil, let activation {
            NotificationCenter.default.removeObserver(activation)
            self.activation = nil
        }
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
    /// The same piece twice in a programme (an encore) is laid out again.
    var index: Int
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
    /// The piece read, for the quick settings' size; none, no settings button.
    var pieceID: String? = nil
    @State private var showingSettings = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showTitle: true)
            row(showTitle: false)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) { backButton; Spacer(minLength: 0); notesButton; settingsButton }
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
            settingsButton
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let pieceID {
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .fixedSize()
            }
            .buttonStyle(.large)
            .accessibilityShowsLargeContentViewer()
            .popover(isPresented: $showingSettings) {
                QuickSettings(pieceID: pieceID)
            }
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

/// The screen stays awake while any reader is open: on the Mac there can be two.
@MainActor
enum AwakeReaders {
    private static var open = 0

    static func opened() {
        open += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func closed() {
        open = max(open - 1, 0)
        if open == 0 { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
