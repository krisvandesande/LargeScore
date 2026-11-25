import SwiftUI
import UniformTypeIdentifiers

/// The pieces on the left, newest last; the chosen one on the right. PDFs dropped
/// anywhere on the window are added.
struct ContentView: View {
    @EnvironmentObject private var queue: ConversionQueue
    @State private var selection: UUID?
    @State private var dropping = false

    var body: some View {
        NavigationView {
            List(selection: $selection) {
                if let problem = queue.problem {
                    Text(problem)
                        .font(.headline)
                        .foregroundColor(.orange)
                        .padding(.vertical, 4)
                }
                ForEach(queue.jobs) { job in
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
            }

            detail
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
            HStack(spacing: 6) {
                if job.state == .converting { ProgressView().controlSize(.small) }
                Text(status)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var status: String {
        switch job.state {
        case .waiting: String(localized: "Waiting")
        case .converting: String(localized: "Converting")
        case .ready: String(localized: "Ready to check")
        case .failed: String(localized: "Not converted")
        case .sent: String(localized: "In the library")
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
