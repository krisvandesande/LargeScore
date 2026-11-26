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
        picture(FixPanel(model: model).frame(width: 640, height: 300), size: CGSize(width: 640, height: 300), name: "fix-panel")
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
        picture(TransposeSheet(from: 0, done: { _, _ in }, cancel: {}), size: CGSize(width: 460, height: 260), name: "transpose-sheet")
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
