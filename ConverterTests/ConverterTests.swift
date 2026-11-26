import XCTest
import SwiftUI
import AppKit
import PDFKit

/// The companion's work, with no app and no window on screen: a stand-in Audiveris,
/// folders in the temporary directory, and the views drawn off screen to pictures in
/// `build/converter` for a look.
nonisolated final class ConverterTests: XCTestCase, @unchecked Sendable {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let samples = repo.appendingPathComponent("LargeScore/Resources/Samples")
    static let pictures = repo.appendingPathComponent("build/converter")
    nonisolated(unsafe) var temp: URL!

    override func setUp() async throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("converter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        setenv("LARGESCORE_CONVERTER_HOME", temp.appendingPathComponent("home").path, 1)
        // A folder under one standing in for iCloud Drive, so "iCloud Drive is on".
        setenv("LARGESCORE_LIBRARY_FOLDER", temp.appendingPathComponent("cloud/Large Score").path, 1)
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("cloud"), withIntermediateDirectories: true)
        // Audiveris's stand-in writes the sample conversion where -output says.
        let script = temp.appendingPathComponent("audiveris.sh")
        let mxl = Self.samples.appendingPathComponent("converted-by-audiveris.mxl").path
        try """
        #!/bin/bash
        out=""
        while [ $# -gt 0 ]; do [ "$1" = "-output" ] && out="$2"; shift; done
        cp "\(mxl)" "$out/piece.mxl"
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        setenv("AUDIVERIS", script.path, 1)
        try FileManager.default.createDirectory(at: Self.pictures, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: temp)
    }

    @MainActor func testCheckedMusicNoLongerCountsAsRecognised() throws {
        let data = try Data(contentsOf: Self.samples.appendingPathComponent("converted-by-audiveris.mxl"))
        let file = try MusicFile.read(data, fileName: "converted-by-audiveris.mxl")
        XCTAssertTrue(file.isRecognised)
        let checked = ConversionQueue.markChecked(file.xml)
        XCTAssertFalse(try MusicFile.read(Data(checked.utf8), fileName: "piece.musicxml").isRecognised)
    }

    @MainActor func testFileNames() {
        XCTAssertEqual(ConversionQueue.fileName("Air / Bach: G"), "Air - Bach- G")
        XCTAssertEqual(ConversionQueue.fileName("  "), "Piece")
    }

    @MainActor func testConvertFixAndSend() async throws {
        let queue = ConversionQueue()
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        let job = try XCTUnwrap(queue.jobs.first)
        try await waitFor { queue.jobs.first?.state == .ready }
        let xml = try String(contentsOf: queue.music(of: job), encoding: .utf8)
        XCTAssertTrue(xml.contains("<score-partwise"))

        // A fix: the first note a step higher, then undone.
        let model = FixModel(xml: xml)
        let note = try XCTUnwrap(model.edit.xml.firstMatch(#"<note\b[^>]*\bid="([^"]+)""#))
        model.selectedNote = note
        let before = model.xml
        model.apply(.step(1))
        XCTAssertNotEqual(model.xml, before)
        XCTAssertTrue(model.canUndo)
        model.undo()
        XCTAssertEqual(model.xml, before)

        XCTAssertNil(queue.send(job, xml: model.xml, checked: true))
        let folder = ConversionQueue.libraryFolder
        let sent = try String(contentsOf: folder.appendingPathComponent("converted-by-audiveris.musicxml"), encoding: .utf8)
        XCTAssertTrue(sent.contains("Large Score Converter"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("converted-by-audiveris.pdf").path))
        XCTAssertEqual(queue.jobs.first?.state, .sent)

        // The list is kept for the next launch.
        let again = ConversionQueue()
        XCTAssertEqual(again.jobs.map(\.id), [job.id])
    }

    /// A send under a new title replaces the old files and keeps the id; a second
    /// piece with the same title gets a name of its own instead of overwriting.
    @MainActor func testRenamedAndSameNamedPieces() async throws {
        let queue = ConversionQueue()
        let pdf = Self.samples.appendingPathComponent("converted-by-audiveris.pdf")
        queue.add([pdf])
        let job = try XCTUnwrap(queue.jobs.first)
        try await waitFor { queue.jobs.first?.state == .ready }
        let xml = try String(contentsOf: queue.music(of: job), encoding: .utf8)
        let folder = ConversionQueue.libraryFolder
        XCTAssertNil(queue.send(job, xml: xml, checked: false))

        queue.update(job.id) { $0.title = "Alte Kameraden" }
        XCTAssertNil(queue.send(try XCTUnwrap(queue.jobs.first), xml: xml, checked: false))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["Alte Kameraden.musicxml", "Alte Kameraden.pdf"])
        let sent = try String(contentsOf: folder.appendingPathComponent("Alte Kameraden.musicxml"), encoding: .utf8)
        XCTAssertEqual(MusicXMLEdit.libraryID(in: sent), job.id.uuidString)

        // Another piece of the same name.
        var other = Job(title: "Alte Kameraden")
        other.state = .ready
        XCTAssertEqual(ConversionQueue.freeName(for: other, in: folder), "Alte Kameraden 2")
    }

    /// Add All to Library sends what's waiting to be checked, named after the PDF.
    @MainActor func testSendAllReady() async throws {
        let queue = ConversionQueue()
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { queue.jobs.first?.state == .ready }
        let result = queue.sendAllReady()
        XCTAssertEqual(result.sent, 1)
        XCTAssertNil(result.problem)
        XCTAssertEqual(queue.jobs.first?.state, .sent)
        let sent = try String(contentsOf: ConversionQueue.libraryFolder.appendingPathComponent("converted-by-audiveris.musicxml"), encoding: .utf8)
        XCTAssertTrue(sent.contains("<work-title>converted-by-audiveris</work-title>"))
        XCTAssertEqual(queue.sendAllReady().sent, 0)
        // Two more: one checked next, one still converting, for a picture of the sidebar.
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { queue.jobs.count == 2 && queue.jobs[1].state == .ready }
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        picture(ContentView().environmentObject(queue), size: CGSize(width: 1100, height: 600), name: "sidebar-groups")
    }

    @MainActor func testFailedConversionSaysSo() async throws {
        let script = temp.appendingPathComponent("nothing.sh")
        try "#!/bin/bash\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        setenv("AUDIVERIS", script.path, 1)
        let queue = ConversionQueue()
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { if case .failed = queue.jobs.first?.state { true } else { false } }
    }

    @MainActor func testEngravedPagesAndSelection() async throws {
        let xml = try String(contentsOf: Self.samples.appendingPathComponent("evening-air.musicxml"), encoding: .utf8)
        let model = FixModel(xml: xml)
        // As the music pane engraves one part: without its name, keeping every id.
        let parts = PartSplitter.parts(in: model.xml)
        XCTAssertEqual(parts.count, 1)
        let shown = try XCTUnwrap(PartSplitter.keeping(partIDs: [parts[0].id], in: model.xml))
        let score = try await Engravers.shared.engrave(musicXML: shown, request: LayoutRequest(pageSize: CGSize(width: 800, height: 1040), staffHeight: 56))
        let scene = try XCTUnwrap(score.pages.first.flatMap { SVGScene(svg: $0.svg) })
        XCTAssertFalse(scene.noteBoxes.isEmpty)
        // A click on a note's middle selects that note.
        let (id, box) = try XCTUnwrap(scene.noteBoxes.first)
        XCTAssertTrue(model.xml.contains(#"id="\#(id)""#), "the clicked note is one the fixes can find")
        XCTAssertEqual(scene.note(at: CGPoint(x: box.midX, y: box.midY), reach: 2), id)
        model.selectedNote = id
        model.selectedBar = scene.measure(at: CGPoint(x: box.midX, y: box.midY), reach: 2)
        draw(scene, selectedNote: id, selectedBar: model.selectedBar, name: "page-selected")
        // The fix buttons for that note and its bar, as the panel shows them.
        picture(FixPanel(model: model).frame(width: 320, height: 760), size: CGSize(width: 320, height: 760), name: "fix-panel")
    }

    /// Dragging a note says what it will become before the change is made, and the
    /// note's tools sit around it on the page.
    @MainActor func testDragPreviewAndNoteTools() async throws {
        let xml = try String(contentsOf: Self.samples.appendingPathComponent("evening-air.musicxml"), encoding: .utf8)
        let model = FixModel(xml: xml)
        let ids = try NSRegularExpression(pattern: #"<note\b[^>]*\bid="([^"]+)""#)
            .matches(in: model.xml, range: NSRange(model.xml.startIndex..., in: model.xml))
            .compactMap { Range($0.range(at: 1), in: model.xml).map { String(model.xml[$0]) } }
        let pitched = ids.filter { id in
            model.edit.elementRange("note", id: id).map { model.xml[$0].contains("<pitch>") } ?? false
        }
        let id = try XCTUnwrap(pitched.dropFirst(6).first)
        model.selectedNote = id
        let before = try XCTUnwrap(model.selectedSummary)
        let up = try XCTUnwrap(model.preview(.step(1)))
        XCTAssertNotEqual(up, before)
        XCTAssertEqual(model.xml, model.edit.xml, "a preview changes nothing")
        XCTAssertFalse(model.canUndo)
        model.apply(.step(1))
        XCTAssertEqual(model.selectedSummary, up, "the change is what the preview said")
        XCTAssertEqual(model.preview(.length(.whole))?.hasSuffix(FixModel.name(.whole)), true)

        let pane = MusicPane(model: model).frame(width: 820, height: 700)
        let window = host(pane, size: CGSize(width: 820, height: 700))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        save(window, name: "note-tools")
    }

    /// Each bar's place on the PDF, from Audiveris's page layout: pictures of a few bars
    /// cut from the sample PDF, to compare by eye.
    @MainActor func testBarPlacesOnThePDF() async throws {
        let queue = ConversionQueue()
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { queue.jobs.first?.state == .ready }
        let job = try XCTUnwrap(queue.jobs.first)
        let xml = MusicXMLEdit.withIDs(try String(contentsOf: queue.music(of: job), encoding: .utf8))
        let pdf = try XCTUnwrap(PDFDocument(url: queue.pdf(of: job)))
        let staves = PDFPlaces.staves(in: pdf)
        XCTAssertEqual(staves.count, 3)
        let places = PDFPlaces.bars(in: xml, staves: staves)
        XCTAssertEqual(places.count, 16)
        let ids = try NSRegularExpression(pattern: #"<measure\b[^>]*\bid="([^"]+)""#)
            .matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            .compactMap { Range($0.range(at: 1), in: xml).map { String(xml[$0]) } }
        // The whole first page with every bar's place outlined.
        if let page = pdf.page(at: 0) {
            let box = page.bounds(for: .mediaBox)
            print("PDF page", box)
            let image = NSImage(size: box.size, flipped: false) { _ in
                guard let cg = NSGraphicsContext.current?.cgContext else { return false }
                cg.setFillColor(.white); cg.fill(box)
                page.draw(with: .mediaBox, to: cg)
                cg.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                for place in places.values where place.page == 0 {
                    cg.stroke(CGRect(x: place.bar.minX * box.width, y: (1 - place.bar.maxY) * box.height,
                                     width: place.bar.width * box.width, height: place.bar.height * box.height))
                }
                return true
            }
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try rep.representation(using: .png, properties: [:])?.write(to: Self.pictures.appendingPathComponent("pdf-places.png"))
            }
        }
        for (number, id) in ids.enumerated() where [0, 3, 6, 12, 15].contains(number) {
            let place = try XCTUnwrap(places[id])
            let image = try XCTUnwrap(PDFPlaces.picture(of: place, in: pdf, mark: true))
            let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
            try rep.representation(using: .png, properties: [:])?.write(to: Self.pictures.appendingPathComponent("pdf-bar-\(number + 1).png"))
        }
    }

    /// With LS_PROBE set to a folder of `pdfs/` and Audiveris's `out/Leland/*.mxl`:
    /// how many of Audiveris's lines found a staff on the PDF, piece by piece, with each
    /// first page drawn with its bars outlined. Skipped otherwise.
    @MainActor func testProbeBarPlaces() throws {
        guard let root = ProcessInfo.processInfo.environment["LS_PROBE"] else { throw XCTSkip("LS_PROBE not set") }
        let folder = URL(fileURLWithPath: root)
        let out = Self.pictures.appendingPathComponent("probe")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var report = ""
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("out/Leland").path).filter { $0.hasSuffix(".mxl") }.sorted()
        for name in names {
            let base = String(name.dropLast(4))
            let pdfURL = folder.appendingPathComponent("pdfs/\(base).pdf")
            guard let pdf = PDFDocument(url: pdfURL),
                  let data = try? Data(contentsOf: folder.appendingPathComponent("out/Leland/\(name)")),
                  let xml = try? MusicFile.text(of: data) else { report += "\(base)\tunreadable\n"; continue }
            let tagged = MusicXMLEdit.withIDs(xml)
            let staves = PDFPlaces.staves(in: pdf)
            let lines = tagged.components(separatedBy: #"new-system="yes""#).count + tagged.components(separatedBy: #"new-page="yes""#).count - 1
            let bars = tagged.components(separatedBy: "<measure ").count - 1
            let places = PDFPlaces.bars(in: tagged, staves: staves)
            report += "\(base)\tpages \(pdf.pageCount)\tstaves \(staves.count)\tlines ~\(lines)\tbars \(bars)\tplaced \(places.count)\n"
            if let page = pdf.page(at: 0) {
                let box = page.bounds(for: .mediaBox)
                let image = NSImage(size: box.size, flipped: false) { _ in
                    guard let cg = NSGraphicsContext.current?.cgContext else { return false }
                    cg.setFillColor(.white); cg.fill(box)
                    page.draw(with: .mediaBox, to: cg)
                    cg.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
                    cg.setLineWidth(1.5)
                    for place in places.values where place.page == 0 {
                        cg.stroke(CGRect(x: box.minX + place.bar.minX * box.width, y: box.minY + (1 - place.bar.maxY) * box.height,
                                         width: place.bar.width * box.width, height: place.bar.height * box.height))
                    }
                    return true
                }
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(base + ".png"))
                }
            }
        }
        try report.write(to: out.appendingPathComponent("report.tsv"), atomically: true, encoding: .utf8)
    }

    /// The proofreader goes through the missing key, then each bar that doesn't add
    /// up; a fixed or passed item drops off.
    @MainActor func testProofreader() async throws {
        let queue = ConversionQueue()
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { queue.jobs.first?.state == .ready }
        let job = try XCTUnwrap(queue.jobs.first)
        var edit = MusicXMLEdit(xml: MusicXMLEdit.withIDs(try String(contentsOf: queue.music(of: job), encoding: .utf8)))
        // Bar 7 a note short, and no key read.
        let bars = try NSRegularExpression(pattern: #"<measure\b[^>]*\bid="([^"]+)""#)
            .matches(in: edit.xml, range: NSRange(edit.xml.startIndex..., in: edit.xml))
            .compactMap { Range($0.range(at: 1), in: edit.xml).map { String(edit.xml[$0]) } }
        let bar7 = bars[6]
        let barRange = try XCTUnwrap(edit.elementRange("measure", id: bar7))
        let note = try XCTUnwrap(String(edit.xml[barRange]).firstMatch(#"<note\b[^>]*\bid="([^"]+)""#))
        try edit.delete(note: note)
        let xml = edit.xml.replacingOccurrences(of: #"<key>\s*<fifths>-1</fifths>\s*</key>"#, with: "", options: .regularExpression)

        let model = FixModel(xml: xml)
        XCTAssertEqual(model.checkItems, [.key, .bar(bar7)])
        model.show(.bar(bar7))
        XCTAssertEqual(model.selectedBar, bar7)
        XCTAssertEqual(model.revealBar, bar7)
        model.pass(.bar(bar7))
        XCTAssertEqual(model.checkItems, [.key])
        model.setKey(-1, fromStart: true)
        XCTAssertEqual(model.checkItems, [])

        let view = PieceView(job: job, xml: xml).environmentObject(queue)
        let window = host(view, size: CGSize(width: 1300, height: 860))
        try await Task.sleep(nanoseconds: 4_000_000_000)
        save(window, name: "proofreader-key")
        let barOnly = xml.replacingOccurrences(of: "<attributes>", with: "<attributes><key><fifths>-1</fifths></key>", options: [], range: xml.range(of: "<attributes>"))
        let second = host(PieceView(job: job, xml: barOnly).environmentObject(queue), size: CGSize(width: 1300, height: 860))
        try await Task.sleep(nanoseconds: 4_000_000_000)
        save(second, name: "proofreader-bar")
    }

    /// The window as it looks, drawn off screen: the list and a piece being fixed.
    @MainActor func testWindowPictures() async throws {
        let queue = ConversionQueue()
        picture(ContentView().environmentObject(queue), size: CGSize(width: 1100, height: 700), name: "window-empty")
        queue.add([Self.samples.appendingPathComponent("converted-by-audiveris.pdf")])
        try await waitFor { queue.jobs.first?.state == .ready }
        let job = try XCTUnwrap(queue.jobs.first)
        let xml = try String(contentsOf: queue.music(of: job), encoding: .utf8)
        // The PDF pane draws in a layer this capture doesn't see: check the document instead.
        let pdf = try XCTUnwrap(PDFDocument(url: queue.pdf(of: job)))
        XCTAssertGreaterThan(pdf.pageCount, 0)
        let view = PieceView(job: job, xml: xml).environmentObject(queue)
        // The engraving runs in a task: give it time before the picture.
        let window = host(view, size: CGSize(width: 1300, height: 860))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        save(window, name: "window-piece")
        picture(TransposeSheet(from: -2, bassClef: true, readBy: .bFlat, done: { _, _, _ in }, cancel: {}),
                size: CGSize(width: 560, height: 420), name: "transpose-sheet")
        let noKey = FixModel(xml: KeyTests.bar.replacingOccurrences(of: "<key><fifths>0</fifths></key>", with: ""))
        picture(FixPanel(model: noKey).frame(width: 300, height: 260), size: CGSize(width: 300, height: 260), name: "no-key")
    }

    // MARK: Helpers

    @MainActor private func waitFor(_ condition: () -> Bool, seconds: Double = 20) async throws {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { XCTFail("Timed out"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @MainActor private func draw(_ scene: SVGScene, selectedNote: String?, selectedBar: String?, name: String) {
        let size = CGSize(width: 800, height: 800 * scene.viewBox.height / scene.viewBox.width)
        let scale: CGFloat = 2
        guard let cg = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        cg.setFillColor(.white)
        cg.fill(CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        // Top-left origin, as SwiftUI's Canvas gives it.
        cg.translateBy(x: 0, y: size.height * scale)
        cg.scaleBy(x: scale, y: -scale)
        PageDrawing.draw(scene, in: cg, size: size, wrongBars: [], selectedBar: selectedBar, selectedNote: selectedNote)
        guard let image = cg.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: Self.pictures.appendingPathComponent(name + ".png"))
    }

    @MainActor @discardableResult
    private func host<V: View>(_ view: V, size: CGSize) -> NSWindow {
        // Never ordered front: nothing appears on the screen.
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        // Light, whatever this Mac is set to: the capture's own background is white.
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: view)
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor private func picture<V: View>(_ view: V, size: CGSize, name: String) {
        save(host(view, size: size), name: name)
    }

    @MainActor private func save(_ window: NSWindow, name: String) {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
        content.cacheDisplay(in: content.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: Self.pictures.appendingPathComponent(name + ".png"))
    }
}
