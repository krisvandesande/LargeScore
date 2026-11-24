import Foundation
import CoreGraphics

/// The size and shape a piece is laid out for.
nonisolated struct LayoutRequest: Hashable, Sendable {
    /// The area the music is drawn in, in points.
    var pageSize: CGSize
    /// Height of one five-line staff, in points.
    var staffHeight: CGFloat
    /// Heavier lines than print, for low vision.
    var bold: Bool = true
    /// Room between lines of music, in half staff spaces on top of what Verovio
    /// already leaves for slurs and dynamics.
    var lineGap: Int = 1
    /// Room under the last line, in Verovio units. Tight first; more only when what
    /// hangs below the last line (dynamics, lyrics, chord names) would run off.
    var bottomRoom: Int = 40
    /// An interval to move every note by ("+P4"), for a part written for another instrument.
    var transpose: String?
    /// Pages with room left but not enough for another line get their music
    /// centred top to bottom (the reader); otherwise it starts at the top.
    var centred = false
    /// The whole part as one line, cut into screens (`OneLine`), for sizes where a busy
    /// bar is wider than a page.
    var oneLine = false
}

/// One engraved page.
nonisolated struct EngravedPage: Sendable {
    var number: Int
    var svg: String
}

/// A piece laid out for one request.
nonisolated struct EngravedScore: Sendable {
    var request: LayoutRequest
    var pages: [EngravedPage]
    /// Time spent engraving, for the speed checks.
    var duration: Duration
}

/// Anything that turns MusicXML into pages. Verovio today; kept behind this so
/// another engraver could take its place.
nonisolated protocol Engraver: Sendable {
    func engrave(musicXML: String, request: LayoutRequest) async throws -> EngravedScore
}

nonisolated enum EngravingError: Error, Equatable {
    case unreadable
    case empty
}
