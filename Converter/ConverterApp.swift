import SwiftUI
import UniformTypeIdentifiers

@main
struct ConverterApp: App {
    @StateObject private var queue = ConversionQueue()

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
        }
    }
}
