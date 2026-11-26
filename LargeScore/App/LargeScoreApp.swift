import SwiftUI
import SwiftData

@main
struct LargeScoreApp: App {
    @State private var settings = ReaderSettings(store: LaunchOptions.store)
    @State private var loader = ScoreLoader()
    @State private var importer = ImportCoordinator()
    @State private var folder = MusicFolder(store: LaunchOptions.store)
    @State private var section = RootView.Section.library
    private let container = LaunchOptions.container

    var body: some Scene {
        WindowGroup {
            RootView(section: $section)
                .environment(settings)
                .environment(loader)
                .environment(importer)
                .environment(folder)
                .tint(Palette.accent)
        }
        .modelContainer(container)
        .commands {
            // The main actions from the keyboard, listed in the menus.
            CommandGroup(replacing: .newItem) {
                Button("Add Music…") {
                    section = .library
                    importer.choosingFiles = true
                }
                .keyboardShortcut("o")
                Button("New Programme") {
                    section = .programmes
                    importer.namingProgramme = true
                }
                .keyboardShortcut("n")
            }
        }
    }
}

struct RootView: View {
    enum Section: Hashable { case programmes, library, settings }

    @Environment(ReaderSettings.self) private var settings
    @Environment(ImportCoordinator.self) private var importer
    @Environment(MusicFolder.self) private var folder
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Binding var section: Section

    var body: some View {
        @Bindable var importer = importer
        content
            // AirDrop, Open In and the share sheet hand files over here.
            .onOpenURL { url in
                section = .library
                Task { await importer.receive([url], instruments: settings.instruments, context: context) }
            }
            .sheet(item: $importer.session) { session in
                ImportSheet(session: session)
            }
            .onChange(of: phase, initial: true) { _, now in
                // Music folders are looked at whenever the app comes to the front: Large
                // Score's own in iCloud Drive always, a chosen one too.
                guard now == .active else { folder.stopWatching(); return }
                let look = { Task { await folder.look(instruments: settings.instruments, context: context, importer: importer) } }
                _ = look()
                folder.startWatching { _ = look() }
            }
            .task {
                // Open on Today's programme when there is one (Programmes shows it).
                let pinned = (try? context.fetchCount(FetchDescriptor<Programme>(predicate: #Predicate { $0.isToday }))) ?? 0
                if pinned > 0 { section = .programmes }
            }
            #if DEBUG
            .task {
                // -demoLibrary: a library the size of a real player's, for screenshots.
                guard ProcessInfo.processInfo.arguments.contains("-demoLibrary"),
                      let url = Bundle.main.url(forResource: "evening-air", withExtension: "musicxml"),
                      let data = try? Data(contentsOf: url),
                      let file = try? MusicFile.read(data, fileName: "evening-air.musicxml") else { return }
                var scores: [Score] = []
                for title in Self.demoTitles {
                    let score = Score(file: file, parts: Array(file.parts.prefix(1)))
                    score.title = title
                    score.composer = nil
                    context.insert(score)
                    scores.append(score)
                }
                // A short programme, to show turning from one piece into the next.
                let programme = Programme(name: "Rehearsal")
                context.insert(programme)
                programme.append(Array(scores.dropFirst(2).prefix(3)))
                try? context.save()
            }
            #endif
            .task {
                guard LaunchOptions.importSamples else { return }
                let urls = ["evening-air-quartet.mxl", "evening-air-quartet.musicxml", "long-piece.musicxml",
                            "converted-by-audiveris.mxl", "converted-by-audiveris.pdf"]
                    .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
                await importer.receive(urls, instruments: settings.instruments, context: context)
            }
    }

    @ViewBuilder
    private var content: some View {
        if settings.onboardingDone {
            #if targetEnvironment(macCatalyst)
            MacRootView(section: $section)
            #else
            tabs
            #endif
        } else {
            OnboardingView()
        }
    }

    private var tabs: some View {
            TabView(selection: $section) {
                Tab("Programmes", systemImage: "list.number", value: .programmes) {
                    ProgrammesView()
                }
                Tab("Library", systemImage: "books.vertical", value: .library) {
                    LibraryView()
                }
                Tab("Settings", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
    }
}

#if DEBUG
extension RootView {
    /// Titles of a real player's parts (first 70 of his folder), for -demoLibrary.
    static let demoTitles: [String] = [
            "25 OR 6 TO 4 - (Bariton_Trombone 2)",
            "25 OR 6 TO 4- (Trombone__Bariton 1)",
            "49. Reiter-Marsch-(Trbn)",
            "50. Blau-Augelein--(Trbn)",
            "51. Klärchen--(Trbn)",
            "52. Vielliebchen-(Trbn)",
            "53. Mein Taum-(Trbn)",
            "54. Junges Blut-(Trbn)",
            "55. Blumensträusschen-(Trbn)",
            "56. Osterglocken-(Trbn)",
            "57. Auf der Flucht-(Trbn)",
            "58. Hannchen-(Trbn)",
            "59. O süsze Heimat-(Trbn)",
            "60. Immer Heiter",
            "61 Kadetten- Marsch",
            "62 Heimliche Liebe",
            "63 Kasino-Polka",
            "64 Gloria",
            "65 Am Meer",
            "66 Dora-Polka",
            "67 Seeschwalben",
            "68 Trau Liebchen",
            "69 Confetti",
            "70 Zauberklänge",
            "71  Agnes Polka",
            "72 Zum Schluss",
            "A Klezmer karnival-(verkorte versie)-Trombone 1",
            "A Klezmer karnival-(verkorte versie)-Trombone 2",
            "Aambeeld Polka-(Trombone-(A.s1)",
            "Afscheidslied-(Trbn)",
            "Al you need is love-(Trbn)",
            "Alaaf 1- (Trombone 1 in Bb)",
            "Alaaf 1-(Trombone 2 in Bb)",
            "Alexander_s Ragtime Band-Trombone_1",
            "Alexander_s Ragtime Band-Trombone_2",
            "Als de nacht verdwijnt (verkorte versie)-Trombone_Bb_(Trb._2)",
            "Alte Kameraden-(Trbn)",
            "Ameezing Medley 4 Trombone in Bb 1",
            "Ameezing Medley 4 Trombone in Bb 2(1)",
            "Ameezing Medley 4 Trombone in Bb 2",
            "Ameezing Medley 4 Trombone in C 1",
            "Ameezing Medley 4 Trombone in C 2",
            "Arabian Nights-Trombone_1",
            "Arabian Nights-Trombone_2",
            "BEAT IT-(Trombone)",
            "Bella Ciao -Trombone",
            "Berliner Luft-(Bariton-Trbn)",
            "Besame Mucho-(Trombone_1_Bb)",
            "Besame Mucho-(Trombone_2Bb)",
            "Borsicka-Polka-Trombone",
            "Böhmische Mädchen",
            "CHINDLER_S KIST- (Tromboon-Trompet)",
            "Carnaval de Paris-(Trbn1)",
            "Carnaval de Paris-(Trbn2)",
            "Celebration-(Trombone)",
            "Cha Cha Cha-(Trbn1)",
            "Cherie-(Trbn)",
            "Copacabana-(Trombone 1)",
            "Copacabana-(Trombone 2)",
            "Daar komt de bruid-(Euph)",
            "Dans je de hele nacht met mij-(Trbn)",
            "De Postkoets-(Stem  3  in Bb)",
            "Demasido Corazon- (Trombone_1-L)",
            "Demasido Corazon- (Trombone_2-L)",
            "Down by the Riverside-Trombone",
            "Dreadlock Holiday-(Trombone_ Euphonium_)",
            "El Bimbo - Paul Mauriat    Trombone1+2  C",
            "El Bimbo - Paul Mauriat    Trombone3+4  C",
            "English style-Trombone-Bariton_II",
            "English style-Trombone_1"
    ]
}
#endif

/// Launch arguments for tests: `-resetSettings` starts from a clean slate with an
/// empty library kept in memory, `-skipOnboarding` goes straight to the tabs with the
/// defaults, `-importSamples` opens the import sheet with the bundled test files.
enum LaunchOptions {
    static var importSamples: Bool { ProcessInfo.processInfo.arguments.contains("-importSamples") }

    /// Made once per launch: two containers on one synced store fight over it.
    static let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-resetSettings")
        // Synced through the iCloud container in the entitlements; in tests, on this
        // device only.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: inMemory ? .none : .automatic)
        #if DEBUG
        CloudSchema.initializeIfNeeded()
        #endif
        let models: [any PersistentModel.Type] = [Score.self, Programme.self, ProgrammeEntry.self, Annotation.self]
        if let container = try? ModelContainer(for: Schema(models), configurations: configuration) { return container }
        // Should sync refuse to start, the library still opens, on this device only;
        // failing that, an empty one for this launch rather than an app that won't open.
        if let local = try? ModelContainer(for: Schema(models), configurations: ModelConfiguration(cloudKitDatabase: .none)) {
            return local
        }
        do {
            return try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        } catch {
            fatalError("The library could not be opened: \(error)")
        }
    }()

    /// Made once per launch: SwiftUI may build the app's state again (when the iPad
    /// turns), and wiping the test store each time sent a test run back to setup.
    static let store: UserDefaults = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSettings"), let suite = UserDefaults(suiteName: "uitest") {
            suite.removePersistentDomain(forName: "uitest")
            if arguments.contains("-skipOnboarding") {
                suite.set(true, forKey: "onboardingDone")
                suite.set(Instrument.bassoon.rawValue, forKey: "instruments")
            }
            return suite
        }
        return .standard
    }()
}
