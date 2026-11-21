import SwiftUI
import SwiftData

@main
struct LargeScoreApp: App {
    @State private var settings = ReaderSettings(store: LaunchOptions.store)
    @State private var loader = ScoreLoader()
    @State private var importer = ImportCoordinator()
    private let container = LaunchOptions.container

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(loader)
                .environment(importer)
                .tint(Palette.accent)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    enum Section: Hashable { case today, programmes, library, settings }

    @Environment(ReaderSettings.self) private var settings
    @Environment(ImportCoordinator.self) private var importer
    @Environment(\.modelContext) private var context
    @State private var section = Section.library

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
            .task {
                guard LaunchOptions.importSamples else { return }
                let urls = ["evening-air-quartet.mxl", "evening-air-quartet.musicxml", "long-piece.musicxml"]
                    .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
                await importer.receive(urls, instruments: settings.instruments, context: context)
            }
    }

    @ViewBuilder
    private var content: some View {
        if settings.onboardingDone {
            TabView(selection: $section) {
                Tab("Today", systemImage: "music.note.list", value: .today) {
                    EmptyTab(title: "Today", heading: "No programme for today",
                             message: "Choose one in Programmes.")
                }
                Tab("Programmes", systemImage: "list.number", value: .programmes) {
                    EmptyTab(title: "Programmes", heading: "No programmes yet")
                }
                Tab("Library", systemImage: "books.vertical", value: .library) {
                    LibraryView()
                }
                Tab("Settings", systemImage: "gearshape", value: .settings) {
                    SettingsView()
                }
            }
        } else {
            OnboardingView()
        }
    }
}

/// Launch arguments for tests: `-resetSettings` starts from a clean slate with an
/// empty library kept in memory, `-skipOnboarding` goes straight to the tabs with the
/// defaults, `-importSamples` opens the import sheet with the bundled test files.
enum LaunchOptions {
    static var importSamples: Bool { ProcessInfo.processInfo.arguments.contains("-importSamples") }

    static var container: ModelContainer {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-resetSettings")
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: Score.self, configurations: configuration)
        } catch {
            fatalError("The library could not be opened: \(error)")
        }
    }

    static var store: UserDefaults {
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
    }
}
