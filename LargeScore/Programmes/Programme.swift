import Foundation
import SwiftData

/// An ordered list of pieces for a rehearsal or concert. One can be Today's: the
/// app opens on it. Shaped for CloudKit like `Score`.
@Model
final class Programme {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    var isToday: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \ProgrammeEntry.programme)
    var entries: [ProgrammeEntry]? = []

    init(name: String) {
        self.name = name
    }

    /// The pieces in playing order; entries whose piece was deleted are left out.
    var orderedEntries: [ProgrammeEntry] {
        (entries ?? []).filter { $0.score != nil }.sorted { $0.order < $1.order }
    }

    var scores: [Score] { orderedEntries.compactMap(\.score) }

    func append(_ scores: [Score]) {
        var next = (orderedEntries.last?.order ?? -1) + 1
        for score in scores {
            let entry = ProgrammeEntry(order: next)
            entry.score = score
            entry.programme = self
            entries = (entries ?? []) + [entry]
            next += 1
        }
    }

    /// Moves pieces as a list's drag does, then numbers every entry again from 0.
    func move(from source: IndexSet, to destination: Int) {
        var list = orderedEntries
        list.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in list.enumerated() { entry.order = index }
    }

    func remove(at offsets: IndexSet, in context: ModelContext) {
        let list = orderedEntries
        for index in offsets where list.indices.contains(index) {
            entries?.removeAll { $0 === list[index] }
            context.delete(list[index])
        }
        for (index, entry) in orderedEntries.enumerated() { entry.order = index }
    }

    /// Makes this Today's programme, and no other.
    func makeToday(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Programme>())) ?? []
        for programme in all { programme.isToday = programme === self }
    }
}

/// One place in a programme. The same piece can be in several programmes, or twice
/// in one.
@Model
final class ProgrammeEntry {
    var id: UUID = UUID()
    var order: Int = 0
    var programme: Programme?
    var score: Score?

    init(order: Int) {
        self.order = order
    }
}

/// Where the reader is in a programme: which piece, and what turning past either end
/// of a piece does. Kept free of SwiftUI so it can be tested.
nonisolated struct ProgrammePlace: Equatable {
    var count: Int
    var index: Int

    var hasNext: Bool { index + 1 < count }
    var hasPrevious: Bool { index > 0 }

    /// After the last page of a piece, the first page of the next one.
    mutating func next() -> Bool {
        guard hasNext else { return false }
        index += 1
        return true
    }

    /// Before the first page of a piece, the last page of the previous one.
    mutating func previous() -> Bool {
        guard hasPrevious else { return false }
        index -= 1
        return true
    }
}
