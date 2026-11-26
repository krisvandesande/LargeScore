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
    private var firstBarID: String { model.xml.firstMatch(#"<measure\b[^>]*\bid="([^"]+)""#) ?? "" }

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
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(name))
        }
    }

    var body: some View {
        HSplitView {
            // The music the full height, the tools beside it as a Mac inspector, then
            // the PDF it came from.
            MusicPane(model: model)
                .frame(minWidth: 420)
            VStack(spacing: 0) {
                FixPanel(model: model)
                Divider()
                // The last step for a piece, at the foot: its name, then sending.
                VStack(alignment: .leading, spacing: 12) {
                    detailField("Title", text: $title)
                    detailField("Composer", text: $composer)
                    Toggle("Checked Against the PDF", isOn: $checked)
                        .toggleStyle(.checkbox)
                        .help("Ticked, the iPad no longer marks the piece Check Against the PDF")
                    Button(action: send) {
                        Text("Send to Library").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .help("Put the music and the PDF in iCloud Drive for the iPad (⌘Return)")
                }
                .padding(FixPanel.inset)
            }
            .frame(minWidth: 290, idealWidth: 300, maxWidth: 320)
            .background(Color(nsColor: .windowBackgroundColor))
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
                // A clef read wrongly: the notes stay where they are on the staff.
                Menu {
                    ForEach(MusicXMLEdit.Clef.allCases) { clef in
                        Button { model.setClef(clef, fromStart: true) } label: {
                            if clef == model.edit.clef(atBar: firstBarID) { Label(clef.name, systemImage: "checkmark") } else { Text(clef.name) }
                        }
                    }
                } label: {
                    Text(model.edit.clef(atBar: firstBarID).name)
                }
                .help("Set the clef of the piece. The notes stay on their lines, as on the PDF.")
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
            TransposeSheet(from: model.edit.firstKey, bassClef: model.edit.clef(atBar: firstBarID) == .bass) { key, up in
                model.transpose(toKey: key, up: up)
                transposing = false
            } forInstrument: { transposition in
                model.transpose(for: transposition)
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

/// Moves all the music: to another key, up or down; or for another instrument,
/// such as a part in C in the bass clef rewritten for B♭ in the treble clef.
struct TransposeSheet: View {
    let from: Int
    var bassClef = false
    let done: (Int, Bool) -> Void
    var forInstrument: (Transposition) -> Void = { _ in }
    let cancel: () -> Void
    @State private var key: Int
    @State private var up = true
    @State private var mode = Mode.key
    @State private var writtenFor: WrittenFor
    @State private var readBy: WrittenFor = .bFlat
    @State private var octaves = 0

    enum Mode { case key, instrument }

    init(from: Int, bassClef: Bool = false, startWithInstrument: Bool = false, done: @escaping (Int, Bool) -> Void,
         forInstrument: @escaping (Transposition) -> Void = { _ in }, cancel: @escaping () -> Void) {
        _mode = State(initialValue: startWithInstrument ? .instrument : .key)
        self.from = from
        self.bassClef = bassClef
        self.done = done
        self.forInstrument = forInstrument
        self.cancel = cancel
        _key = State(initialValue: from)
        _writtenFor = State(initialValue: bassClef ? .cBass : .bFlat)
    }

    private var transposition: Transposition { Transposition(from: writtenFor, to: readBy, octaves: octaves) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transpose").font(.title3.weight(.semibold))
            Picker("Transpose", selection: $mode) {
                Text("To Another Key").tag(Mode.key)
                Text("For Another Instrument").tag(Mode.instrument)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // A Form lines the names up on the Mac, colons and all.
            Form {
            if mode == .key {
                Text("Now: \(KeyName.name(from))").foregroundColor(.secondary)
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
            } else {
                Picker("Written For", selection: $writtenFor) {
                    ForEach(WrittenFor.allCases) { Text($0.name).tag($0) }
                }
                Picker("Read By", selection: $readBy) {
                    ForEach(WrittenFor.allCases) { Text($0.name).tag($0) }
                }
                Stepper(value: $octaves, in: -2...2) {
                    Text(octaveText)
                }
                .accessibilityLabel(Text("Octave"))
                .accessibilityValue(Text(octaveText))
                Text(resultText).foregroundColor(.secondary)
            }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Transpose") {
                    if mode == .key { done(key, up) } else { forInstrument(transposition) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .key ? key == from : transposition.isNothing)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 520)
    }

    private var octaveText: String {
        switch octaves {
        case 0: String(localized: "No octave added")
        case 1: String(localized: "An octave higher")
        case -1: String(localized: "An octave lower")
        case let n where n > 0: String(localized: "\(n) octaves higher")
        default: String(localized: "\(-octaves) octaves lower")
        }
    }

    /// "Up a ninth, treble clef": what will happen, in words.
    private var resultText: String {
        var text = transposition.description
        if transposition.changesClef {
            text += ", " + (readBy.bassClef ? String(localized: "bass clef") : String(localized: "treble clef"))
        }
        return text
    }
}
