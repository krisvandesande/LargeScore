import Testing
import Foundation
import SwiftData
@testable import LargeScore

@MainActor
struct ConversionTests {
    private func url(_ name: String) throws -> URL {
        try #require(Bundle.main.url(forResource: name, withExtension: nil))
    }

    @Test func audiverisOutputIsRecognisedAndKeepsItsPDF() async throws {
        let (files, failures) = await ImportSession.read([try url("converted-by-audiveris.mxl"), try url("converted-by-audiveris.pdf")])
        #expect(failures.isEmpty)
        let file = try #require(files.first)
        #expect(file.software?.hasPrefix("Audiveris") == true)
        #expect(file.isRecognised)
        #expect(file.pdf?.starts(with: Array("%PDF".utf8)) == true)
        #expect(file.barCount == 16)
    }

    @Test func notationProgramsAreNotRecognisers() throws {
        let file = try MusicFile.read(try Data(contentsOf: try url("evening-air-quartet.musicxml")), fileName: "q.musicxml")
        #expect(!file.isRecognised)
        var edited = file
        edited.software = "MuseScore Studio 4.7.7"
        #expect(!edited.isRecognised)
        edited.software = "PlayScore 2"
        #expect(edited.isRecognised)
    }

    @Test func aPDFOnItsOwnSaysWhatToDo() async throws {
        let (files, failures) = await ImportSession.read([try url("converted-by-audiveris.pdf")])
        #expect(files.isEmpty)
        #expect(failures.map(\.reason) == [.pdf])
    }

    @Test func checkedStaysCheckedOnlyForAFixedVersion() async throws {
        let context = ModelContext(try ModelContainer(for: Score.self, Programme.self, ProgrammeEntry.self, Annotation.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)))
        let (files, _) = await ImportSession.read([try url("converted-by-audiveris.mxl"), try url("converted-by-audiveris.pdf")])
        let converted = try #require(files.first)
        let score = Score(file: converted, parts: converted.parts)
        context.insert(score)
        #expect(score.needsCheck)
        #expect(score.pdf != nil)
        // Fixed in MuseScore and saved: checked, and the PDF stays to compare with.
        var fixed = converted
        fixed.software = "MuseScore Studio 4.7.7"
        fixed.pdf = nil
        score.replaceMusic(with: fixed, parts: [])
        #expect(!score.needsCheck)
        #expect(score.pdf != nil)
        // Converted again: to be checked again.
        score.replaceMusic(with: converted, parts: [])
        #expect(score.needsCheck)
    }

    @Test func aLatePDFBringsItsMusicXMLBackIn() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let music = folder.appendingPathComponent("Piece.mxl")
        try FileManager.default.copyItem(at: try url("converted-by-audiveris.mxl"), to: music)
        let (first, seen) = await MusicFolder.changedFiles(in: folder, seen: [:])
        #expect(first.map(\.lastPathComponent) == ["Piece.mxl"])
        try FileManager.default.copyItem(at: try url("converted-by-audiveris.pdf"), to: folder.appendingPathComponent("Piece.pdf"))
        let (second, _) = await MusicFolder.changedFiles(in: folder, seen: seen)
        #expect(second.map(\.lastPathComponent) == ["Piece.mxl"])
    }
}
