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
    @State private var drag: NoteDrag?
    @State private var pressed = false
    private let engraver = Engravers.shared

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 32, 200)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 16) {
                        if failed {
                            Text("This music couldn't be shown.")
                                .font(.body)
                                .padding(40)
                        }
                        ForEach(pages.indices, id: \.self) { index in
                            page(pages[index], width: width)
                        }
                    }
                    .padding(16)
                }
                // The proofreader asks for a bar: it is scrolled to the middle.
                .onChange(of: model.revealBar) { bar in
                    guard let bar else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) { scroller.scrollTo(Self.revealID(bar), anchor: .center) }
                    }
                }
                .onChange(of: pages.count) { _ in
                    guard let bar = model.selectedBar else { return }
                    DispatchQueue.main.async { scroller.scrollTo(Self.revealID(bar), anchor: .center) }
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .task(id: EngraveKey(version: model.version, width: Int(width))) {
                await engrave(width: width)
            }
        }
    }

    private func page(_ scene: SVGScene, width: CGFloat) -> some View {
        let height = width * scene.viewBox.height / max(scene.viewBox.width, 1)
        let size = CGSize(width: width, height: height)
        let wrong = Set(model.wrongBars)
        let selectedBar = model.selectedBar
        // While a note is dragged to a new line, the outline moves with it (drawn on top).
        let moving = drag.map { $0.kind == .pitch && $0.steps != 0 } ?? false
        let selectedNote = moving ? nil : model.selectedNote
        return ZStack(alignment: .topLeading) {
            Canvas { context, size in
                context.withCGContext { cg in
                    PageDrawing.draw(scene, in: cg, size: size, wrongBars: wrong,
                                     selectedBar: selectedBar, selectedNote: selectedNote)
                }
            }
            .frame(width: width, height: height)
            .background(Color.white)
            .contentShape(Rectangle())
            // macOS 12 has no tap location; a drag of no distance gives it. A press on a
            // note selects it, and moving it up or down moves it by lines and spaces.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { pitchDragChanged($0, in: scene, size: size) }
                .onEnded { pitchDragEnded($0, in: scene, size: size) })
            .accessibilityElement()
            .accessibilityLabel(Text("Music"))
            .accessibilityHint(Text("Click a note or a bar to fix it. Drag a note up or down to change its pitch."))

            // A mark to scroll to, on the selected bar.
            if let bar = model.selectedBar, let index = scene.measureIDs.firstIndex(of: bar), scene.measures.indices.contains(index) {
                let rect = viewRect(scene.measures[index], in: scene, size: size)
                Color.clear
                    .frame(width: 1, height: max(rect.height, 1))
                    .position(x: rect.midX, y: rect.midY)
                    .id(Self.revealID(bar))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let id = model.selectedNote, let box = scene.noteBoxes[id] {
                noteTools(around: viewRect(box, in: scene, size: size), step: stepSize(of: scene, size: size), page: size)
            }
        }
        .frame(width: width, height: height)
    }

    static func revealID(_ bar: String) -> String { "bar-" + bar }

    // MARK: Dragging

    private struct NoteDrag {
        enum Kind { case pitch, length }
        var kind: Kind
        var steps = 0
        var label: String?
    }

    /// Lengths from shortest to longest: dragging the handle right makes a note longer.
    private static let lengths = MusicXMLEdit.Length.allCases.reversed() as [MusicXMLEdit.Length]
    /// Points of sideways drag for one length.
    private static let lengthStep: CGFloat = 28

    private func pitchDragChanged(_ value: DragGesture.Value, in scene: SVGScene, size: CGSize) {
        if !pressed {
            pressed = true
            let unit = unitPoint(value.startLocation, in: scene, size: size)
            let reach = 12 / PageDrawing.scale(of: scene, in: size)
            if let note = scene.note(at: unit, reach: reach) {
                model.selectedNote = note
                model.selectedBar = scene.measure(at: unit, reach: reach)
                drag = NoteDrag(kind: .pitch)
            }
        }
        guard var current = drag, current.kind == .pitch, !model.selectedIsRest else { return }
        let steps = Int((-value.translation.height / stepSize(of: scene, size: size)).rounded())
        guard steps != current.steps else { return }
        current.steps = steps
        current.label = steps == 0 ? model.selectedSummary : model.preview(.step(steps))
        drag = current
    }

    private func pitchDragEnded(_ value: DragGesture.Value, in scene: SVGScene, size: CGSize) {
        let steps = drag?.kind == .pitch ? drag?.steps ?? 0 : 0
        let onNote = drag != nil
        drag = nil
        pressed = false
        if steps != 0 {
            model.apply(.step(steps))
        } else if !onNote {
            select(at: value.location, in: scene, size: size)
        }
    }

    private func lengthDragChanged(_ value: DragGesture.Value) {
        guard let length = model.selectedLength, let index = Self.lengths.firstIndex(of: length) else { return }
        let wanted = index + Int((value.translation.width / Self.lengthStep).rounded())
        let steps = min(max(wanted, 0), Self.lengths.count - 1) - index
        var current = drag ?? NoteDrag(kind: .length)
        guard current.kind == .length, steps != current.steps || current.label == nil else { return }
        current.steps = steps
        current.label = steps == 0 ? model.selectedSummary : model.preview(.length(Self.lengths[index + steps]))
        drag = current
    }

    private func lengthDragEnded() {
        let steps = drag?.kind == .length ? drag?.steps ?? 0 : 0
        drag = nil
        guard steps != 0, let length = model.selectedLength, let index = Self.lengths.firstIndex(of: length) else { return }
        model.apply(.length(Self.lengths[index + steps]))
    }

    // MARK: The tools around the selected note

    @ViewBuilder
    private func noteTools(around rect: CGRect, step: CGFloat, page: CGSize) -> some View {
        let lift = drag?.kind == .pitch ? CGFloat(drag?.steps ?? 0) * step : 0
        let moved = rect.offsetBy(dx: 0, dy: -lift)
        let outline = moved.insetBy(dx: -6, dy: -6)
        if lift != 0 {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: outline.width, height: outline.height)
                .position(x: outline.midX, y: outline.midY)
                .allowsHitTesting(false)
        }
        if let label = drag?.label {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(white: 0.12)))
                .fixedSize()
                .position(x: outline.midX, y: outline.minY - 16)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        if drag?.kind != .pitch {
            if model.selectedLength != nil {
                LengthHandle()
                    .position(x: outline.maxX + 14, y: outline.midY)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged(lengthDragChanged)
                        .onEnded { _ in lengthDragEnded() })
                    .help("Drag sideways to make the note shorter or longer")
                    .accessibilityHidden(true)
            }
            if drag == nil {
                let below = outline.maxY + 8 + NoteBar.height / 2
                let fitsBelow = below + NoteBar.height / 2 <= page.height
                NoteBar(model: model)
                    .position(x: min(max(outline.midX, NoteBar.halfWidth(rest: model.selectedIsRest)),
                                     page.width - NoteBar.halfWidth(rest: model.selectedIsRest)),
                              y: fitsBelow ? below : outline.minY - 8 - NoteBar.height / 2)
            }
        }
    }

    // MARK: Geometry

    private func unitPoint(_ point: CGPoint, in scene: SVGScene, size: CGSize) -> CGPoint {
        let scale = PageDrawing.scale(of: scene, in: size)
        return CGPoint(x: point.x / scale + scene.viewBox.minX, y: point.y / scale + scene.viewBox.minY)
    }

    private func viewRect(_ box: CGRect, in scene: SVGScene, size: CGSize) -> CGRect {
        let scale = PageDrawing.scale(of: scene, in: size)
        return CGRect(x: (box.minX - scene.viewBox.minX) * scale, y: (box.minY - scene.viewBox.minY) * scale,
                      width: box.width * scale, height: box.height * scale)
    }

    /// Half a staff space on screen: one line or space up or down.
    private func stepSize(of scene: SVGScene, size: CGSize) -> CGFloat {
        let scale = PageDrawing.scale(of: scene, in: size)
        return scene.staffSpan.map { $0 / 8 * scale } ?? 7
    }

    private func select(at point: CGPoint, in scene: SVGScene, size: CGSize) {
        let unit = unitPoint(point, in: scene, size: size)
        let reach = 12 / PageDrawing.scale(of: scene, in: size)
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

/// The round handle beside a selected note: drag it sideways for the length.
private struct LengthHandle: View {
    @State private var hovering = false

    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}

/// The small bar under a selected note: sharp, flat, natural, dot, rest and delete,
/// the same changes as the inspector, where the eye already is.
private struct NoteBar: View {
    @ObservedObject var model: FixModel
    static let height: CGFloat = 32

    static func halfWidth(rest: Bool) -> CGFloat { rest ? 100 : 160 }

    var body: some View {
        HStack(spacing: 2) {
            if !model.selectedIsRest {
                symbol("♯", name: "Sharp", on: model.selectedAccidental == .sharp) { model.apply(.accidental(.sharp)) }
                symbol("♭", name: "Flat", on: model.selectedAccidental == .flat) { model.apply(.accidental(.flat)) }
                symbol("♮", name: "Natural", on: model.selectedAccidental == .natural) { model.apply(.accidental(.natural)) }
                Divider().frame(height: 18).padding(.horizontal, 4)
            }
            word("Dot", on: model.selectedHasDot) { model.apply(.toggleDot) }
            word("Rest", on: model.selectedIsRest) { model.apply(.toggleRest) }
            word("Delete", on: false) { model.deleteNote() }
                .accessibilityLabel(Text("Delete Note"))
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .fixedSize()
    }

    private func symbol(_ glyph: String, name: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 17))
                .frame(width: 30, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor.opacity(0.2) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(Text(name))
    }

    private func word(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Color.accentColor.opacity(0.2) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
