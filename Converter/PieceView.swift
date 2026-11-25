import SwiftUI
import PDFKit

/// One converted piece: Large Score's engraving with the fix panel under it, beside
/// the PDF it came from. Send to Library puts it in iCloud Drive for the iPad.
struct PieceView: View {
    let job: Job
    @EnvironmentObject private var queue: ConversionQueue
    @StateObject private var model: FixModel
    @State private var checked = false
    @State private var message: String?

    init(job: Job, xml: String) {
        self.job = job
        _model = StateObject(wrappedValue: FixModel(xml: xml))
    }

    var body: some View {
        HSplitView {
            VSplitView {
                MusicPane(model: model)
                    .frame(minHeight: 300)
                FixPanel(model: model)
                    .frame(minHeight: 160, idealHeight: 240)
            }
            .frame(minWidth: 420)
            PDFPane(url: queue.pdf(of: job))
                .frame(minWidth: 320)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .keyboardShortcut("z")
                .help("Undo the last fix (⌘Z)")
                Toggle("Checked Against the PDF", isOn: $checked)
                    .toggleStyle(.checkbox)
                    .help("Ticked, the iPad no longer marks the piece Check Against the PDF")
                Button {
                    queue.saveFixes(model.xml, for: job)
                    model.markSaved()
                    message = queue.send(job, xml: model.xml, checked: checked)
                        ?? String(localized: "\(job.title) is in the library. The iPad shows it within a minute.")
                } label: {
                    Text("Send to Library")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Put the music and the PDF in iCloud Drive for the iPad (⌘Return)")
            }
        }
        .navigationTitle(job.title)
        .onChange(of: model.version) { _ in
            // Every fix is kept at once, so quitting loses nothing.
            queue.saveFixes(model.xml, for: job)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}

/// The original PDF, fitted to the pane's width.
struct PDFPane: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}
