import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(MusicFolder.self) private var folder
    @Environment(ImportCoordinator.self) private var importer
    @Environment(\.modelContext) private var context
    @State private var choosingFolder = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SizeSettingsView()
                    } label: {
                        LabeledContent("Music Size") {
                            Text("Size \(settings.sizeStep + 1) of \(ReaderSettings.staffHeights.count)")
                        }
                    }
                    FittingPicker(String(localized: "Lines"), value: settings.boldLines ? String(localized: "Bold") : String(localized: "Thin"), selection: $settings.boldLines) {
                        Text("Thin").tag(false)
                        Text("Bold").tag(true)
                    }
                    FittingPicker(String(localized: "Color Mode"), value: String(localized: settings.pageColour.title), selection: $settings.pageColour) {
                        ForEach(ReaderSettings.PageColour.allCases) { colour in
                            Text(colour.title).tag(colour)
                        }
                    }
                    FittingPicker(String(localized: "Page Turns"), value: settings.scrollTurns ? String(localized: "Scroll") : String(localized: "Jump"),
                                  selection: $settings.scrollTurns) {
                        Text("Scroll").tag(true)
                        Text("Jump").tag(false)
                    }
                    Toggle("Half-Page Turns", isOn: $settings.halfPageTurns)
                    Toggle("Mark the First Bar", isOn: $settings.markFirstBar)
                } footer: {
                    Text("A half-page turn shows the top of the next page first, so you can read ahead while you finish the bottom. Marking the first bar tints it for a moment after each turn, to show where to start.")
                        .formNote()
                }
                Section {
                    Toggle("Repeats in Playing Order", isOn: $settings.playingOrder)
                    Toggle("Key Reminders", isOn: $settings.keyReminders)
                } footer: {
                    Text("Repeated bars are printed again where they're played, with D.C., D.S. and Coda followed, so pages only turn forward. Key reminders print the key's sharp or flat on every note it applies to.")
                        .formNote()
                }
                Section {
                    NavigationLink {
                        InstrumentSettingsView()
                    } label: {
                        LabeledContent("Instruments") {
                            Text(settings.instruments.map { String(localized: $0.title) }.joined(separator: ", "))
                        }
                    }
                    Button("Language") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .accessibilityHint("Opens Large Score in the Settings app, where the language is chosen.")
                }
                Section {
                    LabeledContent("Music Folder") {
                        Text(folder.folderName ?? String(localized: "None"))
                    }
                    Button(folder.isSet ? "Choose Another Folder" : "Choose Folder") { choosingFolder = true }
                    if folder.isSet {
                        Button("Stop Using This Folder", role: .destructive) { folder.forget() }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Music in the Large Score folder in iCloud Drive is added by itself. A folder chosen here is read too: new and changed MusicXML files are added whenever Large Score comes to the front. A new version replaces the music of the piece and keeps your notes.")
                        if let result = folder.lastResult { Text(result) }
                    }
                    .formNote()
                }
                .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                    guard case .success(let url) = result else { return }
                    folder.choose(url)
                    Task { await folder.look(instruments: settings.instruments, context: context, importer: importer) }
                }
                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .font(.title3)
            .navigationTitle("Settings")
        }
    }
}

struct SizeSettingsView: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        // The music at its real size, as wide as the reader's page, so the lines
        // break where they will when reading.
        MusicSizePreview(card: SampleCard(piece: .sample(for: settings.instrument), description: "Sample music",
                                          fills: true, asPage: true), floating: true)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Music Size")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct InstrumentSettingsView: View {
    var body: some View {
        ScrollView {
            InstrumentGrid()
                .air(.all, 32)
        }
        .background(Palette.ground)
        .navigationTitle("Instruments")
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Link("Source Code", destination: URL(string: "https://github.com/krisvandesande/LargeScore")!)
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Large Score").font(.headline)
                    Text("MIT License")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Verovio").font(.headline)
                    Text("GNU Lesser General Public License 3.0. Large Score uses Verovio unchanged; its source and Large Score's own let you build the app with another version.")
                    Link(destination: URL(string: "https://github.com/rism-digital/verovio")!) {
                        Text(verbatim: "github.com/rism-digital/verovio")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "Leipzig, Bravura").font(.headline)
                    Text("SIL Open Font License 1.1")
                }
            } header: {
                Text("Licences").formHeading()
            }
        }
        .font(.title3)
        .navigationTitle("About")
    }
}
