import SwiftUI
import PDFKit

/// The original PDF beside Large Score's engraving of it, to check a converted piece
/// bar by bar. Side by side in landscape, one above the other upright.
struct CompareView: View {
    let score: Score
    /// Opens straight into fixing notes.
    var startFixing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ScoreLoader.self) private var loader
    @State private var laidOut: LaidOutPiece?
    @State private var session: FixSession?
    @State private var confirmingCancel = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let showsPDF = score.pdf != nil
                let wide = proxy.size.width > proxy.size.height
                let layout = wide ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
                let half = !showsPDF ? proxy.size
                    : wide ? CGSize(width: proxy.size.width / 2, height: proxy.size.height)
                    : CGSize(width: proxy.size.width, height: proxy.size.height / 2)
                layout {
                    if let pdf = score.pdf {
                        // Upright while fixing, the music and its buttons get two thirds.
                        pane(title: "PDF") { PDFPane(data: pdf) }
                            .frame(height: !wide && session != nil ? proxy.size.height * 0.3 : nil)
                    }
                    pane(title: "Large Score") {
                        engraving
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if let session {
                                    FixBar(session: session, barNumber: session.selectedBar.flatMap(barNumber),
                                           maxHeight: (wide || !showsPDF ? proxy.size.height : proxy.size.height * 0.7) * 0.5)
                                }
                            }
                    }
                }
                .background(Color(.separator))
                .task(id: EngraveKey(width: showsPDF ? half.width : min(half.width, 900), version: session?.version)) {
                    await engrave(width: showsPDF ? half.width : min(half.width, 900))
                }
            }
            .navigationTitle(score.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Discard your fixes?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Discard Fixes", role: .destructive) { stopFixing() }
            }
        }
        .onAppear {
            if startFixing, session == nil { startSession() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let session {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if session.hasChanges { confirmingCancel = true } else { stopFixing() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Undo") { session.undo() }
                    .disabled(!session.hasChanges)
                    .keyboardShortcut("z", modifiers: .command)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Fixes") { save(session) }
                    .fontWeight(.semibold)
                    .disabled(!session.hasChanges)
                    .keyboardShortcut("s", modifiers: .command)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Fix Notes") { startSession() }
            }
            if score.needsCheck {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as Checked") {
                        score.needsCheck = false
                        try? context.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var engraving: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let session, !session.wrongBars.isEmpty {
                    Text(wrongBarsText(session.wrongBars))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.notes)
                }
                if let laidOut {
                    ForEach(Array(laidOut.pages.enumerated()), id: \.offset) { _, page in
                        ScoreCanvas(scene: page, ink: .black)
                            .aspectRatio(page.viewBox.width / page.viewBox.height, contentMode: .fit)
                            .background(Color.white)
                            .overlay { if let session { FixOverlay(page: page, session: session) } }
                    }
                }
            }
            .padding(12)
        }
        .accessibilityLabel("Large Score's engraving")
    }

    private func pane<Content: View>(title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .formHeading()
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private struct EngraveKey: Hashable {
        var width: CGFloat
        var version: Date?
    }

    /// The engraving at print-like size for the pane's width, so bars line up with the
    /// PDF's as closely as the layout allows. While fixing, the music being fixed.
    private func engrave(width: CGFloat) async {
        guard width > 100 else { return }
        let area = CGSize(width: width - 24, height: (width - 24) * 1.414)
        let request = LayoutRequest(pageSize: area, staffHeight: max(width / 22, 24), bold: false, lineGap: 1)
        var piece = score.piece
        // As written, so it matches the PDF and the notes being fixed.
        piece.transposition = nil
        if let session {
            piece.source = .stored(Data(session.xml.utf8))
            piece.version = session.version
        }
        do {
            let result = try await loader.layOut(piece, request: request)
            guard !Task.isCancelled, piece.version == (session?.version ?? piece.version) else { return }
            laidOut = result
        } catch is CancellationError {
            return
        } catch {
            // An edit the engraver can't read is never saved: take it back.
            guard !Task.isCancelled, let session, session.version == piece.version else { return }
            session.rejectLastChange()
        }
    }

    private func startSession() {
        guard let data = score.musicXML else { return }
        session = FixSession(xml: String(decoding: data, as: UTF8.self))
    }

    private func stopFixing() {
        session = nil
        if startFixing { dismiss() }
    }

    private func save(_ session: FixSession) {
        score.saveFixes(session.xml)
        try? context.save()
        stopFixing()
    }

    /// A bar's number counted from 1, as the reader shows it.
    private func barNumber(_ id: String) -> Int? {
        if let number = session?.barNumbers[id] { return number }
        guard let laidOut else { return nil }
        for (index, page) in laidOut.pages.enumerated() {
            if let i = page.measureIDs.firstIndex(of: id) { return laidOut.pageBars[index][safe: i] }
        }
        return nil
    }

    private func wrongBarsText(_ ids: [String]) -> String {
        let numbers = ids.compactMap(barNumber).map(String.init)
        guard !numbers.isEmpty else { return "" }
        if numbers.count > 5 {
            return String(localized: "The notes in \(numbers.count) bars don't add up to the time signature, from bar \(numbers[0]).")
        }
        let list = numbers.formatted(.list(type: .and))
        return numbers.count == 1
            ? String(localized: "The notes in bar \(list) don't add up to the time signature.")
            : String(localized: "The notes in bars \(list) don't add up to the time signature.")
    }
}

/// Taps on a page while fixing: a note selects the note and its bar, elsewhere in a
/// bar selects the bar. The selection and the bars that don't add up are outlined.
private struct FixOverlay: View {
    let page: SVGScene
    @Bindable var session: FixSession

    var body: some View {
        GeometryReader { proxy in
            let scale = ScoreCanvas.scale(of: page, in: proxy.size)
            let box = page.viewBox
            let toView = CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: -box.minX, y: -box.minY)
            ZStack {
                Path { path in
                    for (index, id) in page.measureIDs.enumerated() where id.map(session.wrongBars.contains) == true {
                        path.addRect(page.measures[index].applying(toView).insetBy(dx: 0, dy: -6))
                    }
                }
                .stroke(Palette.notes, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                Path { path in
                    if let bar = session.selectedBar, let index = page.measureIDs.firstIndex(of: bar) {
                        path.addRect(page.measures[index].applying(toView).insetBy(dx: 0, dy: -10))
                    }
                }
                .stroke(Palette.notes.opacity(0.6), lineWidth: 2)
                Path { path in
                    if let note = session.selectedNote, let rect = page.noteBoxes[note] {
                        path.addRoundedRect(in: rect.applying(toView).insetBy(dx: -5, dy: -5), cornerSize: CGSize(width: 6, height: 6))
                    }
                }
                .stroke(Palette.notes, lineWidth: 3)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let point = location.applying(toView.inverted())
                let reach = 22 / scale
                session.problem = nil
                if let note = page.note(at: point, reach: reach) {
                    session.selectedNote = note
                    let box = page.noteBoxes[note] ?? .null
                    session.selectedBar = page.measure(at: CGPoint(x: box.midX, y: box.midY), reach: box.height)
                        ?? page.measure(at: point, reach: reach * 4)
                } else {
                    session.selectedNote = nil
                    session.selectedBar = page.measure(at: point, reach: reach * 2)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Music to fix")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }
}

/// PDFKit's own viewer, pages one under the other, fitted to the width.
private struct PDFPane: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(data: data)
        view.accessibilityLabel = String(localized: "The original PDF")
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
