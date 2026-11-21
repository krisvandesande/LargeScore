import SwiftUI

@main
struct LargeScoreApp: App {
    @State private var settings = ReaderSettings(store: LaunchOptions.store)
    @State private var loader = ScoreLoader()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(loader)
                .tint(Palette.accent)
        }
    }
}

struct RootView: View {
    enum Section: Hashable { case today, programmes, library, settings }

    @Environment(ReaderSettings.self) private var settings
    @State private var section = Section.library

    var body: some View {
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

/// Launch arguments for tests: `-resetSettings` starts from a clean slate,
/// `-skipOnboarding` goes straight to the tabs with the defaults.
enum LaunchOptions {
    static var store: UserDefaults {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSettings"), let suite = UserDefaults(suiteName: "uitest") {
            suite.removePersistentDomain(forName: "uitest")
            if arguments.contains("-skipOnboarding") {
                suite.set(true, forKey: "onboardingDone")
                suite.set(Instrument.bassoon.rawValue, forKey: "instrument")
            }
            return suite
        }
        return .standard
    }
}
