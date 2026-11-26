import Foundation
import SwiftData
import UIKit

/// Where music arrives by itself: Large Score's own folder in iCloud Drive (shown as
/// "Large Score" on every device; the Converter on the Mac Pro puts music there), and
/// a folder the player may choose, which a notation program exports into. Whenever the
/// app comes to the front, and every few seconds while it's open on a Mac, new and
/// changed MusicXML files there are added to the library, or replace the music of the
/// piece they're a new version of.
@Observable
final class MusicFolder {
    private(set) var folderName: String?
    /// What the last look found, for Settings and VoiceOver.
    private(set) var lastResult: String?

    private let store: UserDefaults
    private var watching: Task<Void, Never>?
    private var looking = false

    private enum Key {
        static let bookmark = "musicFolderBookmark"
        static let seen = "musicFolderSeen"
        // A new name: build 11 marked files as seen before iCloud had downloaded them,
        // so they were never added. Starting afresh looks at everything there once more.
        static let inboxSeen = "iCloudFolderSeen-2"
    }

    nonisolated static let container = "iCloud.com.kvds.LargeScore"

    /// Large Score's own folder in iCloud Drive, once iCloud has answered; nil with
    /// iCloud off. Asked for off the main thread, as Apple requires.
    private var inbox: URL?
    private var askedForInbox = false

    @concurrent
    nonisolated static func findInbox() async -> URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: container) else { return nil }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        folderName = resolve()?.lastPathComponent
    }

    var isSet: Bool { folderName != nil }

    func choose(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if targetEnvironment(macCatalyst)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let bookmark = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        store.set(bookmark, forKey: Key.bookmark)
        // Files already there count as new: the first look adds them.
        store.removeObject(forKey: Key.seen)
        folderName = url.lastPathComponent
    }

    func forget() {
        store.removeObject(forKey: Key.bookmark)
        store.removeObject(forKey: Key.seen)
        folderName = nil
        lastResult = nil
        stopWatching()
    }

    /// Music arrives while the app is open (sent from the Converter, saved by a
    /// notation program, still downloading from iCloud): look every few seconds while
    /// it's in front, on iPad as on the Mac. A look lists one small folder.
    func startWatching(_ look: @escaping @MainActor () -> Void) {
        stopWatching()
        watching = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { look() }
            }
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// Looks for new and changed files and brings them in. Pieces it can't place
    /// (no part to choose by the player's instruments) go to the import sheet.
    func look(instruments: [Instrument], context: ModelContext, importer: ImportCoordinator) async {
        guard !looking else { return }
        looking = true
        defer { looking = false }
        if !askedForInbox {
            askedForInbox = true
            inbox = await Self.findInbox()
        }
        if let inbox { await bringIn(from: inbox, seenKey: Key.inboxSeen, instruments: instruments, context: context, importer: importer) }
        if let folder = resolve() { await bringIn(from: folder, seenKey: Key.seen, instruments: instruments, context: context, importer: importer) }
    }

    private func bringIn(from folder: URL, seenKey: String, instruments: [Instrument], context: ModelContext, importer: ImportCoordinator) async {
        let seen = store.dictionary(forKey: seenKey) as? [String: Double] ?? [:]
        var (changed, stamps) = await Self.changedFiles(in: folder, seen: seen)
        store.set(stamps, forKey: seenKey)
        guard !changed.isEmpty else { return }
        defer { store.set(stamps, forKey: seenKey) }

        // The files are read through the folder's access, kept open meanwhile.
        let scoped = folder.startAccessingSecurityScopedResource()
        let (files, read) = await ImportSession.read(changed)
        if scoped { folder.stopAccessingSecurityScopedResource() }
        // A file whose contents couldn't be had (still on its way from iCloud) is tried
        // again at the next look, not counted as seen; one that isn't music is reported.
        var failures: [ImportSession.Failure] = []
        for failure in read {
            if failure.reason == .unreadable { stamps.removeValue(forKey: failure.fileName) } else { failures.append(failure) }
        }
        let library = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        var updated: [String] = [], added: [String] = []
        var unplaced: [MusicFile] = []
        for file in files {
            // Replaced without asking only when exactly one piece has that title and
            // composer: two "Ave Maria"s or two untitled scores go to the sheet instead.
            // Music sent from the Converter carries the piece's id: that finds it even
            // when its title was changed on the Mac or here. Otherwise title and composer.
            let byID = MusicXMLEdit.libraryID(in: file.xml).map { id in library.filter { $0.hasLibraryID(id) } } ?? []
            let matches = byID.count == 1 ? byID : library.filter { $0.isSamePiece(as: file) }
            if matches.count == 1, let existing = matches.first {
                existing.replaceMusic(with: file, parts: [])
                // Renamed on the Mac: the piece takes the name it was sent under.
                if byID.count == 1, !file.title.isEmpty { existing.title = file.title }
                updated.append(file.title)
            } else if matches.count > 1 {
                unplaced.append(file)
            } else if let part = file.suggestedPart(for: instruments) {
                context.insert(Score(file: file, parts: [part]))
                added.append(file.title)
            } else {
                unplaced.append(file)
            }
        }
        try? context.save()
        if !unplaced.isEmpty || !failures.isEmpty {
            let arriving = ImportSession(files: unplaced, failures: failures, instruments: instruments, library: library)
            // A sheet already open keeps what was typed and chosen.
            if let open = importer.session { open.add(arriving) } else { importer.session = arriving }
        }
        let result = Self.describe(added: added, updated: updated)
        if let result {
            lastResult = result
            UIAccessibility.post(notification: .announcement, argument: result)
        }
    }

    static func describe(added: [String], updated: [String]) -> String? {
        var parts: [String] = []
        if !added.isEmpty { parts.append(String(localized: "Added: \(added.joined(separator: ", "))")) }
        if !updated.isEmpty { parts.append(String(localized: "Updated: \(updated.joined(separator: ", "))")) }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    private func resolve() -> URL? {
        guard let bookmark = store.data(forKey: Key.bookmark) else { return nil }
        var stale = false
        #if targetEnvironment(macCatalyst)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            // Made again the way it was first made: on the Mac a plain bookmark would
            // lose the folder's access from the next launch.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            #if targetEnvironment(macCatalyst)
            let creation: URL.BookmarkCreationOptions = [.withSecurityScope]
            #else
            let creation: URL.BookmarkCreationOptions = []
            #endif
            if let fresh = try? url.bookmarkData(options: creation, includingResourceValuesForKeys: nil, relativeTo: nil) {
                store.set(fresh, forKey: Key.bookmark)
            }
        }
        return url
    }

    /// MusicXML files whose modification date differs from the last look, and the
    /// dates now. Files in iCloud Drive that aren't on the device yet are asked for
    /// and picked up next time.
    @concurrent
    nonisolated static func changedFiles(in folder: URL, seen: [String: Double]) async -> ([URL], [String: Double]) {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        var urls: [URL] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .withoutChanges, error: &coordinationError) { readURL in
            urls = (try? FileManager.default.contentsOfDirectory(at: readURL, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [])) ?? []
        }
        var stamps: [String: Double] = [:]
        var changed: [URL] = []
        let kinds: Set<String> = ["musicxml", "mxl", "xml"]
        for url in urls {
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                // ".Piece.mxl.icloud": not downloaded yet (older systems).
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            // Current systems list a file iCloud hasn't downloaded under its own name:
            // ask for it, and leave it unseen until its contents are here.
            let status = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            if status?.isUbiquitousItem == true, status?.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }
            let kind = url.pathExtension.lowercased()
            guard kinds.contains(kind) || kind == "pdf" else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            stamps[name] = date
            guard seen[name] != date else { continue }
            if kind == "pdf" {
                // A PDF that arrives after its MusicXML: bring that file in again with it.
                let base = url.deletingPathExtension()
                if let music = urls.first(where: { kinds.contains($0.pathExtension.lowercased()) && $0.deletingPathExtension() == base }),
                   !changed.contains(music) {
                    changed.append(music)
                }
            } else if !changed.contains(url) {
                changed.append(url)
            }
        }
        return (changed, stamps)
    }
}
