import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Files on their way into the library: each with the part to show and, when the
/// piece is already there, whether to replace its music or add it as a new piece.
@Observable
final class ImportSession: Identifiable {
    struct Candidate: Identifiable {
        var id: UUID { file.id }
        var file: MusicFile
        var title: String
        var composer: String
        /// The parts to show, in the file's order. More than one reads as a small score.
        var parts: [ScorePart]
        var existing: Score?
        var replace = true
        /// Worked out once: the sheet redraws on every key typed in the title.
        var data: Data
        var barCount: Int
    }

    struct Failure: Identifiable {
        var id = UUID()
        var fileName: String
        var reason: MusicFile.Failure
    }

    let id = UUID()
    var candidates: [Candidate] = []
    var failures: [Failure] = []

    var isReady: Bool { !candidates.isEmpty && candidates.allSatisfy { !$0.parts.isEmpty } }

    init(files: [MusicFile], failures: [Failure], instruments: [Instrument], library: [Score]) {
        // A file with no part to show could never be chosen, and would hold back the rest.
        self.failures = failures + files.filter(\.parts.isEmpty).map { Failure(fileName: $0.fileName, reason: .noParts) }
        candidates = files.filter { !$0.parts.isEmpty }.map { file in
            let matches = library.filter { $0.isSamePiece(as: file) }
            let existing = matches.first
            // A new version keeps the parts already chosen for the piece.
            let kept = existing.map { score in
                file.parts.filter { score.partIDs.contains($0.id) }
            } ?? []
            let suggested = file.suggestedPart(for: instruments).map { [$0] } ?? []
            return Candidate(file: file, title: file.title, composer: file.composer ?? "",
                             parts: kept.isEmpty ? suggested : kept, existing: existing,
                             replace: matches.count == 1,
                             data: Data(file.xml.utf8), barCount: file.barCount)
        }
    }

    /// Files that arrived while the sheet was open, unless already in it.
    func add(_ other: ImportSession) {
        let names = Set(candidates.map(\.file.fileName))
        candidates += other.candidates.filter { !names.contains($0.file.fileName) }
        failures += other.failures
    }

    /// Adds or replaces every piece, then saves. Returns how many were added or replaced.
    @discardableResult
    func apply(to context: ModelContext) -> Int {
        var count = 0
        // The music folder may have added one of these while the sheet was open.
        let library = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        for var candidate in candidates {
            if candidate.existing == nil || candidate.existing?.isDeleted == true {
                candidate.existing = library.first { !$0.isDeleted && $0.isSamePiece(as: candidate.file) }
            }
            guard !candidate.parts.isEmpty else { continue }
            var file = candidate.file
            file.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? file.title : candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let composer = candidate.composer.trimmingCharacters(in: .whitespacesAndNewlines)
            file.composer = composer.isEmpty ? nil : composer
            if let existing = candidate.existing, candidate.replace {
                existing.replaceMusic(with: file, parts: candidate.parts)
            } else {
                context.insert(Score(file: file, parts: candidate.parts))
            }
            count += 1
        }
        try? context.save()
        return count
    }

    /// Reads files from wherever they come from: the Files picker (iCloud Drive,
    /// Google Drive and other providers, which may need a download first), AirDrop,
    /// Open In and drag and drop.
    @concurrent
    nonisolated static func read(_ urls: [URL]) async -> (files: [MusicFile], failures: [Failure]) {
        var files: [MusicFile] = []
        var failures: [Failure] = []
        // PDFs picked with their MusicXML are kept with it, matched by name.
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        var usedPDFs: Set<URL> = []
        for url in urls where url.pathExtension.lowercased() != "pdf" {
            let name = url.lastPathComponent
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var data: Data?
            var coordinationError: NSError? // no data at all means it couldn't be read
            // Coordinated reading makes file providers download the file first.
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
                data = try? Data(contentsOf: readURL)
            }
            guard let data else {
                failures.append(Failure(fileName: name, reason: .unreadable))
                continue
            }
            do {
                var file = try MusicFile.read(data, fileName: name)
                let base = url.deletingPathExtension().lastPathComponent
                if let picked = pdfs.first(where: { $0.deletingPathExtension().lastPathComponent == base }) {
                    file.pdf = readPDF(picked)
                    usedPDFs.insert(picked)
                } else {
                    // In a music folder the PDF sits beside the file.
                    file.pdf = readPDF(url.deletingPathExtension().appendingPathExtension("pdf"))
                }
                files.append(file)
            } catch let failure as MusicFile.Failure {
                failures.append(Failure(fileName: name, reason: failure))
            } catch {
                failures.append(Failure(fileName: name, reason: .notMusicXML))
            }
        }
        for pdf in pdfs where !usedPDFs.contains(pdf) {
            failures.append(Failure(fileName: pdf.lastPathComponent, reason: .pdf))
        }
        return (files, failures)
    }

    /// The PDF at `url` if there is one and it can be read; nil otherwise.
    nonisolated private static func readPDF(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        guard let data, data.starts(with: Array("%PDF".utf8)) else { return nil }
        return data
    }
}

/// Where files arriving from outside (AirDrop, Open In, drops) wait for the sheet.
@Observable
final class ImportCoordinator {
    var session: ImportSession?
    /// Set by the Add Music command (⌘O) to open the file picker.
    var choosingFiles = false
    /// Set by the New Programme command (⌘N).
    var namingProgramme = false
    private(set) var isReading = false

    func receive(_ urls: [URL], instruments: [Instrument], context: ModelContext) async {
        guard !urls.isEmpty else { return }
        isReading = true
        let (files, failures) = await ImportSession.read(urls)
        isReading = false
        Self.removeInboxCopies(urls)
        let library = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        let arriving = ImportSession(files: files, failures: failures, instruments: instruments, library: library)
        if let session {
            // A sheet already open keeps what was typed and chosen; the new files join it.
            session.add(arriving)
        } else {
            session = arriving
        }
    }

    /// Files given to the app by AirDrop or Open In are copied into its Inbox; once
    /// read they're in the library and the copies can go.
    private static func removeInboxCopies(_ urls: [URL]) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox").standardizedFileURL.path
        for url in urls where url.standardizedFileURL.path.hasPrefix(inbox + "/") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// A MusicXML file dropped onto the library from another app.
nonisolated struct DroppedMusic: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .compressedMusicXML) { received in
            DroppedMusic(url: try copy(received.file))
        }
        FileRepresentation(importedContentType: .musicXML) { received in
            DroppedMusic(url: try copy(received.file))
        }
        FileRepresentation(importedContentType: .xml) { received in
            DroppedMusic(url: try copy(received.file))
        }
        FileRepresentation(importedContentType: .data) { received in
            DroppedMusic(url: try copy(received.file))
        }
    }

    /// A dropped file is only lent for the call; keep a copy to read.
    private static func copy(_ url: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
}

extension MusicFile.Failure {
    var message: LocalizedStringResource {
        switch self {
        case .notMusicXML: "This isn't a MusicXML file."
        case .timewise: "This MusicXML is written bar by bar instead of part by part. Export it again as a standard MusicXML file."
        case .damaged: "This compressed MusicXML file can't be opened. Export it again."
        case .pdf: "This is a PDF. Large Score reads MusicXML: convert the PDF on the Mac first, or add it together with its MusicXML."
        case .unreadable: "This file couldn't be opened. Check that it has finished downloading, then add it again."
        case .noParts: "This MusicXML file has no parts to show."
        }
    }
}
