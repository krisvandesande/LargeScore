import Foundation

/// What the library knows about a piece beyond its title and composer, one line each,
/// for its card and for VoiceOver's More Content. Free of SwiftUI so it can be tested.
nonisolated enum PieceFacts {
    enum Kind: String, CaseIterable {
        case arranger, parts, bars, transposed, programmes, settings, played
    }

    struct Fact: Equatable {
        var kind: Kind
        var text: String
    }

    struct Input {
        var arranger: String?
        var partName: String
        var barCount: Int
        var transposition: String?
        var programmes: [String]
        var ownSettings: Bool
        var lastOpenedAt: Date?
        var addedAt: Date
        var now: Date = .now
    }

    static func facts(_ input: Input) -> [Fact] {
        var facts: [Fact] = []
        if let arranger = input.arranger?.trimmingCharacters(in: .whitespacesAndNewlines), !arranger.isEmpty {
            facts.append(Fact(kind: .arranger, text: String(localized: "Arranged by \(arranger)")))
        }
        if !input.partName.isEmpty {
            facts.append(Fact(kind: .parts, text: input.partName))
        }
        if input.barCount > 0 {
            facts.append(Fact(kind: .bars, text: String(AttributedString(localized: "^[\(input.barCount) bar](inflect: true)").characters)))
        }
        if let transposition = input.transposition {
            facts.append(Fact(kind: .transposed, text: String(localized: "Transposed: \(transposition)")))
        }
        // Each programme once, in the order given.
        var seen = Set<String>()
        let names = input.programmes.filter { !$0.isEmpty && seen.insert($0).inserted }
        if !names.isEmpty {
            let list = names.formatted(.list(type: .and))
            facts.append(Fact(kind: .programmes, text: String(localized: "In \(list)")))
        }
        if input.ownSettings {
            facts.append(Fact(kind: .settings, text: String(localized: "Read with its own settings")))
        }
        if let played = input.lastOpenedAt {
            facts.append(Fact(kind: .played, text: String(localized: "Played \(day(played, now: input.now))")))
        } else {
            facts.append(Fact(kind: .played, text: String(localized: "Added \(day(input.addedAt, now: input.now))")))
        }
        return facts
    }

    /// "24 November", with the year when it isn't this one.
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
    }
}
