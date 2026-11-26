import SwiftUI
import PDFKit

/// Goes through what Audiveris often gets wrong, one thing at a time: the bar as the
/// PDF has it, above the music where it is fixed (drag the notes, or the inspector).
/// A fixed item drops off by itself; Looks Right passes one that was read right.
struct Proofreader: View {
    @ObservedObject var model: FixModel
    /// Where each bar is on the PDF, once the PDF's staves have been found.
    let pdf: PDFDocument?
    let staves: [PDFPlaces.Staff]?
    @State private var index = 0
    @State private var picture: NSImage?

    private var items: [FixModel.CheckItem] { model.checkItems }
    private var current: FixModel.CheckItem? {
        let items = items
        return items.isEmpty ? nil : items[min(index, items.count - 1)]
    }

    var body: some View {
        Group {
            if let current {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(heading(current))
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 12)
                        Text(items.count == 1 ? String(localized: "1 to check") : String(localized: "\(items.count) to check"))
                            .foregroundColor(.secondary)
                    }
                    Label {
                        Text(reason(current)).foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let picture {
                        Image(nsImage: picture)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: 140)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                            .accessibilityLabel(Text("The line on the PDF"))
                    }
                    HStack(spacing: 8) {
                        fix(current)
                        Spacer(minLength: 8)
                        if items.count > 1 {
                            Button("Next") { index = (min(index, items.count - 1) + 1) % items.count }
                                .help("Leave this for now and go to the next one")
                                .accessibilityLabel(Text("Next to Check"))
                        }
                        Button("Looks Right") { passRight(current) }
                            .keyboardShortcut(.return, modifiers: [])
                            .help(current == .key ? "The PDF has no sharps or flats either (Return)" : "The PDF has it like this (Return)")
                    }
                    .controlSize(.large)
                }
                .font(.body)
                .padding(FixPanel.inset)
                .task(id: Shown(item: current, version: model.version, found: staves != nil)) {
                    model.show(current)
                    picture = makePicture(for: current)
                }
            } else {
                Label {
                    Text("Nothing left to check.").foregroundColor(.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FixPanel.inset)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private struct Shown: Hashable {
        var item: FixModel.CheckItem
        var version: Date
        var found: Bool
    }

    private func heading(_ item: FixModel.CheckItem) -> String {
        switch item {
        case .key: String(localized: "Key Signature")
        case .time: String(localized: "Time Signature")
        case .bar(let id): model.barNumbers[id].map { String(localized: "Bar \($0)") } ?? String(localized: "Bar")
        }
    }

    private func reason(_ item: FixModel.CheckItem) -> String {
        switch item {
        case .key: return String(localized: "No key signature was read.")
        case .time: return String(localized: "No time signature was read.")
        case .bar(let id):
            let time = model.edit.time(atBar: id)
            return String(localized: "The notes don't add up to \(time.beats)/\(time.beatType).")
        }
    }

    @ViewBuilder
    private func fix(_ item: FixModel.CheckItem) -> some View {
        switch item {
        case .key:
            Menu {
                ForEach(MusicXMLEdit.keys.reversed(), id: \.self) { fifths in
                    Button(KeyName.name(fifths)) { model.setKey(fifths, fromStart: true) }
                }
            } label: {
                Text("Set Key")
            }
            .fixedSize()
        case .time:
            Menu {
                ForEach(0..<FixPanel.times.count, id: \.self) { index in
                    let time = FixPanel.times[index]
                    Button("\(time.0)/\(time.1)") { model.setTime(beats: time.0, beatType: time.1) }
                }
            } label: {
                Text("Set Time")
            }
            .fixedSize()
        case .bar:
            EmptyView()
        }
    }

    private func passRight(_ item: FixModel.CheckItem) {
        // No key on the PDF either: written down as no sharps or flats, so the piece
        // isn't flagged again.
        if item == .key { model.setKey(0, fromStart: true) } else { model.pass(item) }
    }

    private func makePicture(for item: FixModel.CheckItem) -> NSImage? {
        guard let pdf, let staves, let bar = model.bar(of: item),
              let place = PDFPlaces.bars(in: model.xml, staves: staves)[bar] else { return nil }
        if case .bar = item {
            return PDFPlaces.picture(of: place, in: pdf, mark: true)
        }
        return PDFPlaces.picture(of: place, in: pdf, mark: false)
    }
}
