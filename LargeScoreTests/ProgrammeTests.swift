import Testing
import Foundation
import SwiftData
@testable import LargeScore

@MainActor
struct ProgrammeTests {
    private func setUp() throws -> (ModelContext, [Score]) {
        let container = try ModelContainer(for: Score.self, Programme.self, ProgrammeEntry.self, Annotation.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let url = try #require(Bundle.main.url(forResource: "evening-air-quartet.musicxml", withExtension: nil))
        let file = try MusicFile.read(try Data(contentsOf: url), fileName: "q.musicxml")
        let scores = ["Air", "Largo", "Nimrod"].map { title -> Score in
            var named = file
            named.title = title
            let score = Score(file: named, parts: [file.parts[2]])
            context.insert(score)
            return score
        }
        return (context, scores)
    }

    @Test func keepsOrderAndMoves() throws {
        let (context, scores) = try setUp()
        let programme = Programme(name: "Thursday")
        context.insert(programme)
        programme.append(scores)
        #expect(programme.scores.map(\.title) == ["Air", "Largo", "Nimrod"])
        programme.move(from: [2], to: 0)
        #expect(programme.scores.map(\.title) == ["Nimrod", "Air", "Largo"])
        programme.remove(at: [1], in: context)
        #expect(programme.scores.map(\.title) == ["Nimrod", "Largo"])
        #expect(programme.orderedEntries.map(\.order) == [0, 1])
    }

    @Test func samePieceTwiceAndInTwoProgrammes() throws {
        let (context, scores) = try setUp()
        let a = Programme(name: "A"), b = Programme(name: "B")
        context.insert(a); context.insert(b)
        a.append([scores[0], scores[0]])
        b.append([scores[0]])
        #expect(a.scores.count == 2)
        #expect(b.scores.count == 1)
    }

    @Test func onlyOneToday() throws {
        let (context, _) = try setUp()
        let a = Programme(name: "A"), b = Programme(name: "B")
        context.insert(a); context.insert(b)
        try context.save()
        a.makeToday(in: context)
        b.makeToday(in: context)
        #expect(!a.isToday && b.isToday)
    }

    @Test func deletingAPieceTakesItOutOfProgrammes() throws {
        let (context, scores) = try setUp()
        let programme = Programme(name: "A")
        context.insert(programme)
        programme.append(scores)
        try context.save()
        context.delete(scores[1])
        try context.save()
        #expect(programme.scores.map(\.title) == ["Air", "Nimrod"])
    }

    @Test func turningPastEitherEnd() {
        var place = ProgrammePlace(count: 3, index: 0)
        let a = place.previous()
        #expect(!a)
        let b = place.next()
        #expect(b && place.index == 1)
        let c = place.next()
        #expect(c && place.index == 2)
        let d = place.next()
        #expect(!d)
        let e = place.previous()
        #expect(e && place.index == 1)
    }
}
