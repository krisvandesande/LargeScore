import Foundation
import SwiftData
import UIKit

/// A folder the player's notation program exports into (on the Mac, or in iCloud
/// Drive). Whenever the app comes to the front, and every few seconds while it's open
/// on a Mac, new and changed MusicXML files there are added to the library, or replace
/// the music of the piece they're a new version of.
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

    /// On a Mac the app stays open while the notation program saves: look every
    /// few seconds while it's in front.
    func startWatching(_ look: @escaping @MainActor () -> Void) {
        #if targetEnvironment(macCatalyst)
        stopWatching()
        watching = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { look() }
            }
        }
        #endif
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    /// Looks for new and changed files and brings them in. Pieces it can't place
    /// (no part to choose by the player's instruments) go to the import sheet.
    func look(instruments: [Instrument], context: ModelContext, importer: ImportCoordinator) async {
        guard !looking, let folder = resolve() else { return }
        looking = true
        defer { looking = false }
        let seen = store.dictionary(forKey: Key.seen) as? [String: Double] ?? [:]
        let (changed, stamps) = await Self.changedFiles(in: folder, seen: seen)
        store.set(stamps, forKey: Key.seen)
        guard !changed.isEmpty else { return }

        // The files are read through the folder's access, kept open meanwhile.
        let scoped = folder.startAccessingSecurityScopedResource()
        let (files, failures) = await ImportSession.read(changed)
        if scoped { folder.stopAccessingSecurityScopedResource() }
        let library = (try? context.fetch(FetchDescriptor<Score>())) ?? []
        var updated: [String] = [], added: [String] = []
        var unplaced: [MusicFile] = []
        for file in files {
            // Replaced without asking only when exactly one piece has that title and
            // composer: two "Ave Maria"s or two untitled scores go to the sheet instead.
            let matches = library.filter { $0.isSamePiece(as: file) }
            if matches.count == 1, let existing = matches.first {
                existing.replaceMusic(with: file, parts: [])
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
                // ".Piece.mxl.icloud": not downloaded yet.
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
