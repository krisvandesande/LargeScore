import SwiftUI
import PDFKit

/// The original PDF beside Large Score's engraving of it, to check a converted piece
/// bar by bar. Side by side in landscape, one above the other upright.
struct CompareView: View {
    let score: Score
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ScoreLoader.self) private var loader
    @State private var pages: [SVGScene] = []

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let wide = proxy.size.width > proxy.size.height
                let layout = wide ? AnyLayout(HStackLayout(spacing: 1)) : AnyLayout(VStackLayout(spacing: 1))
                let half = wide ? CGSize(width: proxy.size.width / 2, height: proxy.size.height)
                                : CGSize(width: proxy.size.width, height: proxy.size.height / 2)
                layout {
                    pane(title: "PDF") {
                        if let pdf = score.pdf { PDFPane(data: pdf) }
                    }
                    pane(title: "Large Score") {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                                    ScoreCanvas(scene: page, ink: .black)
                                        .aspectRatio(page.viewBox.width / page.viewBox.height, contentMode: .fit)
                                        .background(Color.white)
                                }
                            }
                            .padding(12)
                        }
                        .accessibilityLabel("Large Score's engraving")
                    }
                }
                .background(Color(.separator))
                .task(id: half) { await engrave(width: half.width) }
            }
            .navigationTitle(score.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
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
    }

    private func pane<Content: View>(title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .formHeading()
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    /// The engraving at print-like size for the pane's width, so bars line up with the
    /// PDF's as closely as the layout allows.
    private func engrave(width: CGFloat) async {
        guard width > 100 else { return }
        let area = CGSize(width: width - 24, height: (width - 24) * 1.414)
        let request = LayoutRequest(pageSize: area, staffHeight: max(width / 22, 24), bold: false, lineGap: 4)
        if let laidOut = try? await loader.layOut(score.piece, request: request) {
            pages = laidOut.pages
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
