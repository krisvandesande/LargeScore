import SwiftUI
import Sparkle

@main
struct ConverterApp: App {
    @StateObject private var queue = ConversionQueue()
    /// Sparkle: checks daily and installs new versions by itself (Info.plist).
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(queue)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add PDFs…") { queue.choosePDFs() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
            }
        }
    }
}
