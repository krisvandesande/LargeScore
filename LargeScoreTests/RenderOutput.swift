import Foundation

/// Where render tests leave their pictures to look at: the project's build folder from
/// the simulator; on the Mac the sandbox allows only the app's own temporary folder.
func renderOutput(_ name: String) -> URL {
    #if targetEnvironment(macCatalyst)
    FileManager.default.temporaryDirectory.appendingPathComponent(name)
    #else
    URL(fileURLWithPath: "/Users/kris/Developer/LargeScore/build/\(name)")
    #endif
}
