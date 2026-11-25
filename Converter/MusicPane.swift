import SwiftUI
import CoreText

/// The converted music engraved by Large Score's own engraver, page under page, as
/// the iPad will show it. A click selects the note under it, or else the bar. The
/// selection is outlined; bars whose notes don't add up are tinted, and also listed
/// in words by the fix panel.
struct MusicPane: View {
    @ObservedObject var model: FixModel
    @State private var pages: [SVGScene] = []
    @State private var failed = false
    private let engraver = Engravers.shared

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 32, 200)
            ScrollView {
                VStack(spacing: 16) {
                    if failed {
                        Text("This music couldn't be shown.")
                            .font(.reading)
                            .padding(40)
                    }
                    ForEach(pages.indices, id: \.self) { index in
                        page(pages[index], width: width)
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .task(id: EngraveKey(version: model.version, width: Int(width))) {
                await engrave(width: width)
            }
        }
    }

    private func page(_ scene: SVGScene, width: CGFloat) -> some View {
        let height = width * scene.viewBox.height / max(scene.viewBox.width, 1)
        let wrong = Set(model.wrongBars)
        let selectedBar = model.selectedBar
        let selectedNote = model.selectedNote
        return Canvas { context, size in
            context.withCGContext { cg in
                PageDrawing.draw(scene, in: cg, size: size, wrongBars: wrong,
                                 selectedBar: selectedBar, selectedNote: selectedNote)
            }
        }
        .frame(width: width, height: height)
        .background(Color.white)
        .contentShape(Rectangle())
        // macOS 12 has no tap location; a drag of no distance gives it.
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            select(at: value.location, in: scene, size: CGSize(width: width, height: height))
        })
        .accessibilityElement()
        .accessibilityLabel(Text("Music"))
        .accessibilityHint(Text("Click a note or a bar to fix it."))
    }

    private func select(at point: CGPoint, in scene: SVGScene, size: CGSize) {
        let scale = PageDrawing.scale(of: scene, in: size)
        let unit = CGPoint(x: point.x / scale + scene.viewBox.minX, y: point.y / scale + scene.viewBox.minY)
        let reach = 12 / scale
        if let note = scene.note(at: unit, reach: reach) {
            model.selectedNote = note
            model.selectedBar = scene.measure(at: unit, reach: reach)
        } else {
            model.selectedNote = nil
            model.selectedBar = scene.measure(at: unit, reach: reach)
        }
    }

    private func engrave(width: CGFloat) async {
        // One part is shown without its name before every line, as on the iPad.
        let full = model.xml
        let parts = PartSplitter.parts(in: full)
        let xml = parts.count == 1 ? PartSplitter.keeping(partIDs: [parts[0].id], in: full) ?? full : full
        // A Mac screen is read closer than a music stand: a little smaller than the iPad's
        // standard size, with the page as wide as the pane.
        let request = LayoutRequest(pageSize: CGSize(width: width, height: width * 1.3), staffHeight: 56)
        do {
            let score = try await engraver.engrave(musicXML: xml, request: request)
            guard !Task.isCancelled else { return }
            pages = score.pages.compactMap { SVGScene(svg: $0.svg) }
            failed = pages.isEmpty
        } catch {
            guard !Task.isCancelled else { return }
            if model.canUndo { model.rejectLastChange() } else { failed = true }
        }
    }

    private struct EngraveKey: Hashable {
        var version: Date
        var width: Int
    }
}

/// One engraver for the app: Verovio keeps a single toolkit.
enum Engravers {
    static let shared = VerovioEngraver()
}

/// Draws an engraved page in black, as the iPad's `ScoreCanvas` does, with the fix
/// selection on top.
enum PageDrawing {
    static func scale(of scene: SVGScene, in size: CGSize) -> CGFloat {
        min(size.width / scene.viewBox.width, size.height / scene.viewBox.height)
    }

    static func draw(_ scene: SVGScene, in cg: CGContext, size: CGSize, wrongBars: Set<String>,
                     selectedBar: String?, selectedNote: String?) {
        let box = scene.viewBox
        let scale = scale(of: scene, in: size)
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -box.minX, y: -box.minY)

        // Bars that don't add up, under the music: a pale orange.
        cg.setFillColor(CGColor(red: 1, green: 0.6, blue: 0, alpha: 0.18))
        for (index, id) in scene.measureIDs.enumerated() {
            guard let id, wrongBars.contains(id), scene.measures.indices.contains(index) else { continue }
            cg.fill(scene.measures[index])
        }

        let ink = CGColor(gray: 0, alpha: 1)
        cg.setFillColor(ink)
        cg.setStrokeColor(ink)
        for item in scene.items {
            switch item {
            case .fill(let path):
                cg.addPath(path)
                cg.fillPath()
            case .stroke(let path, let width, let round):
                cg.setLineWidth(width)
                cg.setLineCap(round ? .round : .butt)
                cg.setLineJoin(round ? .round : .miter)
                cg.addPath(path)
                cg.strokePath()
            case .text(let line, let origin):
                cg.saveGState()
                cg.translateBy(x: origin.x, y: origin.y)
                cg.scaleBy(x: 1, y: -1)
                cg.textPosition = .zero
                CTLineDraw(line, cg)
                cg.restoreGState()
            }
        }

        // The selection: the bar outlined thinly, the note boldly, in the system accent.
        let accent = NSColor.controlAccentColor.cgColor
        cg.setStrokeColor(accent)
        if let selectedBar, let index = scene.measureIDs.firstIndex(of: selectedBar), scene.measures.indices.contains(index) {
            cg.setLineWidth(2 / scale)
            cg.stroke(scene.measures[index].insetBy(dx: -4 / scale, dy: -4 / scale))
        }
        if let selectedNote, let note = scene.noteBoxes[selectedNote] {
            cg.setLineWidth(3 / scale)
            cg.stroke(note.insetBy(dx: -6 / scale, dy: -6 / scale))
        }
        cg.restoreGState()
    }
}
