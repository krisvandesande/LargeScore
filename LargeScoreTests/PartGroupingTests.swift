import Testing
@testable import LargeScore

/// Real titles from the first player's folder of parts.
struct PartGroupingTests {
    @Test(arguments: [
        ("Alexander_s Ragtime Band-Trombone_2", "Alexander's Ragtime Band", 2),
        ("Besame Mucho-(Trombone_1_Bb)", "Besame Mucho", 1),
        ("Besame Mucho-(Trombone_2Bb)", "Besame Mucho", 2),
        ("Final -countdown-(Trbn2_Bariton)", "Final -countdown", 2),
        ("English style-Trombone-Bariton_II", "English style", 2),
        ("Alaaf 1- (Trombone 1 in Bb)", "Alaaf 1", 1),
        ("Alaaf 1-(Trombone 2 in Bb)", "Alaaf 1", 2),
        ("Als de nacht verdwijnt (verkorte versie)-Trombone_Bb_(Trb._2)", "Als de nacht verdwijnt (verkorte versie)", 2),
        ("Ameezing Medley 4 Trombone in Bb 2(1)", "Ameezing Medley 4", 2),
        ("Funiculi Funicula-(Tbn.1-Barit.)", "Funiculi Funicula", 1),
        ("Carnaval de Paris-(Trbn2)", "Carnaval de Paris", 2),
        ("Cherie-(Trbn)", "Cherie", nil),
        ("Feest vieren 1-(Trbn)", "Feest vieren 1", nil),
        ("64 Gloria", "64 Gloria", nil),
        ("Böhmische Mädchen", "Böhmische Mädchen", nil),
        ("CHINDLER_S KIST- (Tromboon-Trompet)", "CHINDLER'S KIST", nil),
    ] as [(String, String, Int?)])
    func parses(title: String, name: String, part: Int?) {
        let parsed = PartGrouping.parse(title)
        #expect(parsed.name == name)
        #expect(parsed.part == part)
    }

    @Test func keysStayApart() {
        #expect(PartGrouping.parse("Ameezing Medley 4 Trombone in C 1").key == "c")
        #expect(PartGrouping.parse("Ameezing Medley 4 Trombone in Bb 1").key == "bb")
    }

    @Test func otherPartsGoAsideOnlyWhenMyPartIsThere() {
        let pieces = [(id: 1, title: "Copacabana-(Trombone 1)"), (id: 2, title: "Copacabana-(Trombone 2)"),
                      (id: 3, title: "De Postkoets-(Stem  3  in Bb)"), (id: 4, title: "Cherie-(Trbn)"),
                      (id: 5, title: "Ameezing Medley 4 Trombone in C 1"), (id: 6, title: "Ameezing Medley 4 Trombone in Bb 2")]
        let split = PartGrouping.split(pieces, myPart: 1)
        #expect(split.others == [2])
        #expect(split.shown == [1, 3, 4, 5, 6])
        // Playing part 2: part 1 of Copacabana goes aside instead.
        #expect(PartGrouping.split(pieces, myPart: 2).others == [1])
    }
}
