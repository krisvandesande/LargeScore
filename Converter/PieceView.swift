import SwiftUI
import PDFKit

/// One converted piece: Large Score's engraving with the fix panel under it, beside
/// the PDF it came from. Send to Library puts it in iCloud Drive for the iPad.
struct PieceView: View {
    let job: Job
    @EnvironmentObject private var queue: ConversionQueue
    @StateObject private var model: FixModel
    @State private var checked = false
    @State private var title = ""
    @State private var composer = ""
    @State private var arranger = ""
    @State private var message: String?
    @StateObject private var pdfZoom = PDFZoom()
    @State private var transposing = false

    init(job: Job, xml: String) {
        self.job = job
        _model = StateObject(wrappedValue: FixModel(xml: xml))
    }

    private func send() {
        queue.saveFixes(model.xml, for: job)
        model.markSaved()
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var sending = job
        if !name.isEmpty {
            sending.title = name
            queue.update(job.id) { $0.title = name }
        }
        let xml = MusicXMLEdit.settingDetails(model.xml, title: sending.title, composer: composer, arranger: arranger)
        message = queue.send(sending, xml: xml, checked: checked)
            ?? (ConversionQueue.sendsToOwnFolder
                ? String(localized: "\(job.title) is in the library. The iPad shows it within a minute.")
                : String(localized: "\(job.title) is in the Large Score folder in iCloud Drive. Choose that folder in Large Score's Settings, Music Folder, to add it."))
    }

    private func detailField(_ name: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(name).accessibilityHidden(true)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(name))
        }
    }

    var body: some View {
        HSplitView {
            // The music takes the height; the buttons keep a fixed band under it.
            VStack(spacing: 0) {
                MusicPane(model: model)
                Divider()
                FixPanel(model: model)
                    .frame(height: 220)
                Divider()
                // The last step for a piece, under everything else: its name, then sending.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        detailField("Title", text: $title)
                        detailField("Composer", text: $composer)
                    }
                    HStack(spacing: 16) {
                        Toggle("Checked Against the PDF", isOn: $checked)
                            .toggleStyle(.checkbox)
                            .fixedSize()
                            .help("Ticked, the iPad no longer marks the piece Check Against the PDF")
                        Spacer()
                        Button("Send to Library", action: send)
                            .keyboardShortcut(.return, modifiers: .command)
                            .controlSize(.large)
                            .buttonStyle(.borderedProminent)
                            .help("Put the music and the PDF in iCloud Drive for the iPad (⌘Return)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(minWidth: 480)
            VStack(spacing: 0) {
                PDFZoomBar(zoom: pdfZoom)
                Divider()
                PDFPane(url: queue.pdf(of: job), zoom: pdfZoom)
            }
            .frame(minWidth: 320)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // The key of the whole piece: Audiveris often misses it, and the notes
                // then lack its sharps or flats. Setting it spells them again.
                Menu {
                    ForEach(MusicXMLEdit.keys.reversed(), id: \.self) { fifths in
                        Button {
                            model.setKey(fifths, fromStart: true)
                        } label: {
                            if fifths == model.edit.firstKey {
                                Label(KeyName.name(fifths), systemImage: "checkmark")
                            } else {
                                Text(KeyName.name(fifths))
                            }
                        }
                    }
                } label: {
                    Text("Key: \(KeyName.signature(model.edit.firstKey))")
                }
                .help("Set the key of the piece. Notes without their own sharp or flat follow it.")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Transpose…") { transposing = true }
                    .help("Move all the music to another key")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .keyboardShortcut("z")
                .help("Undo the last fix (⌘Z)")
            }
        }
        .navigationTitle(job.title)
        .onAppear {
            // The PDF's own name: Audiveris reads a title from the page, often a line
            // of the part's heading ("Bariton/Posaune in B") rather than the piece.
            let file = try? MusicFile.read(Data(model.xml.utf8), fileName: job.title + ".musicxml")
            title = PartGrouping.tidy(job.title)
            composer = file?.composer ?? ""
            arranger = file?.arranger ?? ""
        }
        .onChange(of: model.version) { _ in
            // Every fix is kept at once, so quitting loses nothing.
            queue.saveFixes(model.xml, for: job)
        }
        .sheet(isPresented: $transposing) {
            TransposeSheet(from: model.edit.firstKey) { key, up in
                model.transpose(toKey: key, up: up)
                transposing = false
            } cancel: {
                transposing = false
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        }
    }
}

/// Zoom for the PDF beside the music: buttons over it, ⌘+ and ⌘− from the View menu,
/// and the trackpad's pinch. Fit Width goes back to the whole width of the pane.
final class PDFZoom: ObservableObject {
    weak var view: PDFView?

    func zoomIn() { view?.zoomIn(nil) }
    func zoomOut() { view?.zoomOut(nil) }
    func fitWidth() { view?.autoScales = true }
}

struct PDFZoomBar: View {
    @ObservedObject var zoom: PDFZoom

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            Button(action: zoom.zoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-")
            .help("Zoom out on the PDF (⌘−)")
            Button(action: zoom.fitWidth) {
                Label("Fit Width", systemImage: "arrow.left.and.right")
            }
            .keyboardShortcut("0")
            .help("Fit the PDF to the width of the pane (⌘0)")
            Button(action: zoom.zoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("=")
            .help("Zoom in on the PDF (⌘+)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.large)
        .font(.title2)
        .frame(minHeight: 32)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// The original PDF, fitted to the pane's width until zoomed.
struct PDFPane: NSViewRepresentable {
    let url: URL
    var zoom: PDFZoom? = nil

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.minScaleFactor = 0.25
        view.maxScaleFactor = 8
        view.document = PDFDocument(url: url)
        zoom?.view = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        zoom?.view = view
    }
}

/// Moves all the music to another key: the new key, and up or down to it.
struct TransposeSheet: View {
    let from: Int
    let done: (Int, Bool) -> Void
    let cancel: () -> Void
    @State private var key: Int
    @State private var up = true

    init(from: Int, done: @escaping (Int, Bool) -> Void, cancel: @escaping () -> Void) {
        self.from = from
        self.done = done
        self.cancel = cancel
        _key = State(initialValue: from)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transpose").font(.title3.weight(.semibold))
            Text("Now: \(KeyName.name(from))").foregroundStyle(.secondary)
            Picker("New Key", selection: $key) {
                ForEach(MusicXMLEdit.keys.reversed(), id: \.self) { fifths in
                    Text(KeyName.name(fifths)).tag(fifths)
                }
            }
            Picker("Direction", selection: $up) {
                Text("Up").tag(true)
                Text("Down").tag(false)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Transpose") { done(key, up) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key == from)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460)
    }
}
