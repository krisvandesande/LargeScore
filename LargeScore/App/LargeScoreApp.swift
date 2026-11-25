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
    enum Section: Hashable { case today, programmes, library, settings }

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
                // The music folder is looked at whenever the app comes to the front.
                guard now == .active, folder.isSet else { folder.stopWatching(); return }
                let look = { Task { await folder.look(instruments: settings.instruments, context: context, importer: importer) } }
                _ = look()
                folder.startWatching { _ = look() }
            }
            .task {
                // Open on Today's programme when there is one.
                let pinned = (try? context.fetchCount(FetchDescriptor<Programme>(predicate: #Predicate { $0.isToday }))) ?? 0
                if pinned > 0 { section = .today }
            }
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
                Tab("Today", systemImage: "music.note.list", value: .today) {
                    TodayView(showProgrammes: { section = .programmes })
                }
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
