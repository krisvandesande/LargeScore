import Foundation
import AppKit

/// One PDF on its way to the library.
struct Job: Identifiable, Codable, Equatable {
    enum State: Codable, Equatable {
        case waiting
        case converting
        case ready
        case failed(String)
        case sent
    }

    var id = UUID()
    var title: String
    var state: State = .waiting
    var added = Date()

    var isConverted: Bool { state == .ready || state == .sent }
}

/// The PDFs dropped on the window, converted one at a time with Audiveris. Each job
/// keeps its files in its own folder under Application Support:
/// `original.pdf`, then `music.musicxml` once converted (and fixed).
@MainActor
final class ConversionQueue: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    /// Why nothing can be converted at all (no Audiveris), shown above the list.
    @Published private(set) var problem: String?
    private var running = false

    /// The Audiveris inside this app (release builds carry one in Contents/Helpers),
    /// else one in Applications. `AUDIVERIS` names another, which the tests use for a
    /// stand-in.
    nonisolated static var audiveris: URL {
        if let other = ProcessInfo.processInfo.environment["AUDIVERIS"] { return URL(fileURLWithPath: other) }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Audiveris.app/Contents/MacOS/Audiveris")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return URL(fileURLWithPath: "/Applications/Audiveris.app/Contents/MacOS/Audiveris")
    }

    /// Application Support's "Large Score Converter"; `LARGESCORE_CONVERTER_HOME`
    /// names another, for the tests.
    nonisolated static var home: URL {
        if let other = ProcessInfo.processInfo.environment["LARGESCORE_CONVERTER_HOME"] {
            return URL(fileURLWithPath: other, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Large Score Converter", isDirectory: true)
    }

    /// The folder in iCloud Drive the iPad reads.
    /// Large Score's own folder in iCloud Drive ("Large Score", read by every Large
    /// Score app by itself), once iCloud has brought it to this Mac; until then the
    /// "Large Score" folder made in iCloud Drive itself, which the apps read when it's
    /// chosen in their Settings. `LARGESCORE_LIBRARY_FOLDER` names another, for the tests.
    nonisolated static var libraryFolder: URL {
        if let other = ProcessInfo.processInfo.environment["LARGESCORE_LIBRARY_FOLDER"] {
            return URL(fileURLWithPath: other, isDirectory: true)
        }
        let mobile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        let own = mobile.appendingPathComponent("iCloud~com~kvds~LargeScore/Documents", isDirectory: true)
        if FileManager.default.fileExists(atPath: own.path) { return own }
        return mobile.appendingPathComponent("com~apple~CloudDocs/Large Score", isDirectory: true)
    }

    /// Whether music sent now reaches the apps without a folder being chosen.
    nonisolated static var sendsToOwnFolder: Bool { libraryFolder.path.contains("iCloud~com~kvds~LargeScore") }

    private static var listURL: URL { home.appendingPathComponent("pieces.json") }

    init() {
        load()
        // A conversion cut off by quitting starts again.
        for index in jobs.indices where jobs[index].state == .converting { jobs[index].state = .waiting }
        runNext()
    }

    func folder(of job: Job) -> URL { Self.home.appendingPathComponent(job.id.uuidString, isDirectory: true) }
    func pdf(of job: Job) -> URL { folder(of: job).appendingPathComponent("original.pdf") }
    func music(of job: Job) -> URL { folder(of: job).appendingPathComponent("music.musicxml") }

    // MARK: Adding

    func choosePDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose the PDFs to convert.")
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Copies the PDFs in, so the originals can be moved or deleted.
    func add(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            var job = Job(title: url.deletingPathExtension().lastPathComponent)
            do {
                try FileManager.default.createDirectory(at: folder(of: job), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: pdf(of: job))
            } catch {
                job.state = .failed(String(localized: "The PDF couldn't be read."))
            }
            jobs.append(job)
        }
        save()
        runNext()
    }

    func remove(_ job: Job) {
        try? FileManager.default.removeItem(at: folder(of: job))
        jobs.removeAll { $0.id == job.id }
        save()
    }

    func retry(_ job: Job) {
        update(job.id) { $0.state = .waiting }
        runNext()
    }

    // MARK: Converting

    private func runNext() {
        guard !running, let job = jobs.first(where: { $0.state == .waiting }) else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.audiveris.path) else {
            problem = String(localized: "Audiveris is missing, so PDFs can't be converted. Download Large Score Converter again.")
            return
        }
        problem = nil
        running = true
        update(job.id) { $0.state = .converting }
        let pdf = pdf(of: job)
        let music = music(of: job)
        Task {
            let result = await Self.convert(pdf, to: music)
            running = false
            update(job.id) { $0.state = result.map { .failed($0) } ?? .ready }
            if result == nil { _ = NSApp?.requestUserAttention(.informationalRequest) }
            runNext()
        }
    }

    /// Runs Audiveris on one PDF, off the main thread. Nil when it worked, otherwise
    /// what went wrong in a sentence.
    nonisolated static func convert(_ pdf: URL, to music: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: work) }
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = audiveris
            // As the Mac Pro's converter script: Leland, MuseScore's music font, reads
            // MuseScore parts (Bravura missed every whole note), and a busy page on a
            // slow Mac needs up to 20 minutes a step.
            process.arguments = ["-batch", "-export",
                                 "-option", "org.audiveris.omr.ui.symbol.MusicFont.defaultMusicFamily=Leland",
                                 "-option", "org.audiveris.omr.Main.sheetStepTimeOut=1200",
                                 "-output", work.path, "--", pdf.path]
            var environment = ProcessInfo.processInfo.environment
            let tessdata = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/LargeScoreConverter/tessdata").path
            if environment["TESSDATA_PREFIX"] == nil, FileManager.default.fileExists(atPath: tessdata) {
                environment["TESSDATA_PREFIX"] = tessdata
            }
            process.environment = environment
            let log = home.appendingPathComponent("audiveris.log")
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: log) {
                handle.seekToEndOfFile()
                process.standardOutput = handle
                process.standardError = handle
            }
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return String(localized: "Audiveris didn't start.")
            }
            // Audiveris names its output after the PDF, but may tidy the name.
            let made = FileManager.default.enumerator(at: work, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.pathExtension.lowercased() == "mxl" }
            guard let made, let data = try? Data(contentsOf: made),
                  let file = try? MusicFile.read(data, fileName: made.lastPathComponent) else {
                return String(localized: "Audiveris couldn't read any music in this PDF.")
            }
            do {
                try Data(file.xml.utf8).write(to: music, options: .atomic)
            } catch {
                return String(localized: "The music couldn't be saved.")
            }
            return nil
        }.value
    }

    // MARK: Fixes and sending

    func saveFixes(_ xml: String, for job: Job) {
        try? Data(xml.utf8).write(to: music(of: job), options: .atomic)
    }

    /// Puts the music and its PDF in the Large Score folder in iCloud Drive, where the
    /// iPad picks them up. Checked music says so, and the iPad drops its "Check against
    /// the PDF" mark. Nil when it worked.
    func send(_ job: Job, xml: String, checked: Bool) -> String? {
        let fm = FileManager.default
        let cloud = Self.libraryFolder.deletingLastPathComponent()
        guard fm.fileExists(atPath: cloud.path) else {
            return String(localized: "iCloud Drive is off on this Mac. Turn it on in System Preferences, Apple ID, iCloud.")
        }
        do {
            try fm.createDirectory(at: Self.libraryFolder, withIntermediateDirectories: true)
            let name = Self.fileName(job.title)
            let text = checked ? Self.markChecked(xml) : xml
            let musicURL = Self.libraryFolder.appendingPathComponent(name + ".musicxml")
            let pdfURL = Self.libraryFolder.appendingPathComponent(name + ".pdf")
            // The PDF first: the iPad pairs a PDF that arrives with music already there.
            if fm.fileExists(atPath: pdfURL.path) { try fm.removeItem(at: pdfURL) }
            try fm.copyItem(at: pdf(of: job), to: pdfURL)
            try Data(text.utf8).write(to: musicURL, options: .atomic)
        } catch {
            return String(localized: "The music couldn't be put in iCloud Drive.")
        }
        update(job.id) { $0.state = .sent }
        return nil
    }

    /// The file's own name for the piece: no characters iCloud Drive refuses.
    nonisolated static func fileName(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Piece" : cleaned
    }

    /// Music checked against its PDF names this app as the program that wrote it, so
    /// it no longer counts as a recognition program's work.
    nonisolated static func markChecked(_ xml: String) -> String {
        let pattern = #"<software>[^<]*</software>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return xml }
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "<software>Large Score Converter</software>")
    }

    // MARK: Keeping the list

    func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.listURL),
              let list = try? JSONDecoder().decode([Job].self, from: data) else { return }
        jobs = list.filter { FileManager.default.fileExists(atPath: pdf(of: $0).path) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.home, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(jobs) { try? data.write(to: Self.listURL, options: .atomic) }
    }
}
