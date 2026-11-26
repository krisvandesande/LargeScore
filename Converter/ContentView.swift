import SwiftUI
import UniformTypeIdentifiers

/// The pieces on the left, newest last; the chosen one on the right. PDFs dropped
/// anywhere on the window are added.
struct ContentView: View {
    @EnvironmentObject private var queue: ConversionQueue
    @State private var selection: UUID?
    @State private var dropping = false
    @State private var confirmingAll = false
    @State private var sentMessage: String?

    private enum Group: CaseIterable {
        case new, toCheck, inLibrary
    }

    private func jobs(in group: Group) -> [Job] {
        queue.jobs.filter { job in
            switch (group, job.state) {
            case (.toCheck, .ready), (.inLibrary, .sent): true
            case (.new, .waiting), (.new, .converting), (.new, .failed): true
            default: false
            }
        }
    }

    private func title(_ group: Group) -> Text {
        switch group {
        case .new: Text("New")
        case .toCheck: Text("To Check")
        case .inLibrary: Text("In the Library")
        }
    }

    private var readyCount: Int { jobs(in: .toCheck).count }

    var body: some View {
        NavigationView {
            List(selection: $selection) {
                if let problem = queue.problem {
                    Text(problem)
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.vertical, 4)
                }
                // Where each piece is: being converted, waiting to be checked, or sent.
                ForEach(Group.allCases, id: \.self) { group in
                    let members = jobs(in: group)
                    if !members.isEmpty {
                        Section {
                            ForEach(members) { job in
                                JobRow(job: job)
                                    .tag(job.id)
                                    .contextMenu {
                                        if case .failed = job.state {
                                            Button("Try Again") { queue.retry(job) }
                                        }
                                        Button("Remove") {
                                            if selection == job.id { selection = nil }
                                            queue.remove(job)
                                        }
                                    }
                            }
                        } header: {
                            HStack {
                                title(group)
                                Spacer()
                                Text(verbatim: "\(members.count)").monospacedDigit()
                                    // As far in from the right as the title is from the left (14 pt).
                                    .padding(.trailing, 11)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(title(group))
                            .accessibilityValue(Text(verbatim: "\(members.count)"))
                            .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 280)
            .toolbar {
                ToolbarItem {
                    Button { queue.choosePDFs() } label: {
                        Label("Add PDFs", systemImage: "plus")
                    }
                    .help("Add PDFs to convert (⌘O)")
                }
                ToolbarItem {
                    Button("Add All to Library") { confirmingAll = true }
                        .disabled(readyCount == 0)
                        .help("Send every piece under To Check to the library as it is")
                }
            }

            detail
        }
        .confirmationDialog(Text(readyCount == 1 ? "Add 1 piece to the library?" : "Add \(readyCount) pieces to the library?"),
                            isPresented: $confirmingAll) {
            Button("Add All to Library") {
                let result = queue.sendAllReady()
                sentMessage = result.problem ?? (result.sent == 1
                    ? String(localized: "1 piece is in the library. The iPad shows it within a minute.")
                    : String(localized: "\(result.sent) pieces are in the library. The iPad shows them within a minute."))
            }
        } message: {
            Text("They go as they are, named after their PDFs. The iPad marks them to check against the PDF.")
        }
        .alert(sentMessage ?? "", isPresented: Binding(get: { sentMessage != nil }, set: { if !$0 { sentMessage = nil } })) {
            Button("OK") { sentMessage = nil }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            Task { queue.add(await Self.urls(from: providers)) }
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 4)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let job = queue.jobs.first(where: { $0.id == selection }) {
            if job.isConverted, let data = try? Data(contentsOf: queue.music(of: job)) {
                PieceView(job: job, xml: String(decoding: data, as: UTF8.self))
                    .id(job.id)
            } else {
                Placeholder(text: placeholderText(job))
            }
        } else if queue.jobs.isEmpty {
            VStack(spacing: 20) {
                Text("Drag PDFs here")
                    .font(.largeTitle.weight(.semibold))
                Text("Each one is converted to music you can check against the PDF, fix, and send to the library on the iPad.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Button { queue.choosePDFs() } label: {
                    Text("Add PDFs…").font(.body).padding(.horizontal, 8)
                }
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Placeholder(text: String(localized: "Choose a piece on the left."))
        }
    }

    private func placeholderText(_ job: Job) -> String {
        switch job.state {
        case .waiting: String(localized: "Waiting for the piece before it.")
        case .converting: String(localized: "Converting. A long piece can take several minutes.")
        case .failed(let reason): reason
        case .ready, .sent: String(localized: "The music couldn't be read.")
        }
    }

    private static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { done in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in done.resume(returning: url) }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}

private struct JobRow: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.title)
                .font(.headline)
                .lineLimit(2)
            // The section already says "To Check" or "In the Library"; new ones say how far along.
            if let status {
                HStack(spacing: 6) {
                    if job.state == .converting { ProgressView().controlSize(.small) }
                    Text(status)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var status: String? {
        switch job.state {
        case .waiting: String(localized: "Waiting")
        case .converting: String(localized: "Converting")
        case .failed: String(localized: "Not converted")
        case .ready, .sent: nil
        }
    }
}

private struct Placeholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
