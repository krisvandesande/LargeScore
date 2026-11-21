import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(ReaderSettings.self) private var settings

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
                    FittingPicker(String(localized: "Page"), value: String(localized: settings.pageColour.title), selection: $settings.pageColour) {
                        ForEach(ReaderSettings.PageColour.allCases) { colour in
                            Text(colour.title).tag(colour)
                        }
                    }
                    Toggle("Half-Page Turns", isOn: $settings.halfPageTurns)
                } footer: {
                    Text("A half-page turn shows the top of the next page first, so you can read ahead while you finish the bottom.")
                }
                Section {
                    NavigationLink {
                        InstrumentSettingsView()
                    } label: {
                        LabeledContent("Instrument") {
                            if let instrument = settings.instrument { Text(instrument.title) }
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
        VStack(spacing: 32) {
            SampleCard(piece: .sample(for: settings.instrument), description: "Sample music")
                .frame(minHeight: 280)
            SizeStepper()
        }
        .air(.all, 32)
        .background(Palette.ground)
        .navigationTitle("Music Size")
    }
}

struct InstrumentSettingsView: View {
    var body: some View {
        ScrollView {
            InstrumentGrid()
                .air(.all, 32)
        }
        .background(Palette.ground)
        .navigationTitle("Instrument")
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
            Section("Licences") {
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
            }
        }
        .font(.title3)
        .navigationTitle("About")
    }
}
