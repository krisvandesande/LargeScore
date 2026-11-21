import CoreGraphics

/// Where the reader is in a piece. With half-page turns, a forward turn first replaces
/// the top of the page with the top of the next one, so the player can read ahead
/// while finishing the bottom; the next turn shows the whole next page.
nonisolated struct PageTurner: Equatable {
    var pageCount: Int
    var halfPageTurns: Bool
    private(set) var page = 0
    /// True while the top shows the next page and the bottom still this one.
    private(set) var halfway = false

    init(pageCount: Int, halfPageTurns: Bool, page: Int = 0) {
        self.pageCount = pageCount
        self.halfPageTurns = halfPageTurns
        self.page = min(max(page, 0), max(pageCount - 1, 0))
    }

    var isAtStart: Bool { page == 0 && !halfway }
    var isAtEnd: Bool { page >= pageCount - 1 }

    /// Returns false when there is nothing further.
    @discardableResult
    mutating func forward() -> Bool {
        if halfway {
            page += 1
            halfway = false
            return true
        }
        guard page + 1 < pageCount else { return false }
        if halfPageTurns {
            halfway = true
        } else {
            page += 1
        }
        return true
    }

    @discardableResult
    mutating func back() -> Bool {
        if halfway {
            halfway = false
            return true
        }
        guard page > 0 else { return false }
        page -= 1
        return true
    }

    /// Keeps the place when the layout changes and the page count with it.
    mutating func update(pageCount: Int, halfPageTurns: Bool) {
        self.pageCount = pageCount
        self.halfPageTurns = halfPageTurns
        page = min(page, max(pageCount - 1, 0))
        if !halfPageTurns || page + 1 >= pageCount { halfway = false }
    }
}

/// Where to divide a half-turned page: below the last line of the next page that fits
/// in about the top half, moved up if it would cut through a line of this page.
/// Lines are given top to bottom, in page units. Returns nil when no line fits.
nonisolated enum HalfPageSplit {
    static func split(current: [CGRect], next: [CGRect], pageHeight: CGFloat) -> CGFloat? {
        let gap: CGFloat = pageHeight * 0.01
        // Lines of the next page that end in the upper 60%.
        let fitting = next.filter { !$0.isNull && $0.maxY <= pageHeight * 0.6 }
        guard var y = fitting.last.map({ $0.maxY + gap }) else { return nil }
        // Never cut a line of this page: move the division to above it.
        for line in current where !line.isNull && line.minY < y && line.maxY > y {
            y = line.minY - gap
        }
        // The top must still show at least one whole line of the next page.
        guard let first = next.first(where: { !$0.isNull }), y >= first.maxY else { return nil }
        return y
    }
}
