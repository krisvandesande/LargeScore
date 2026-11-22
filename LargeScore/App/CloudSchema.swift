#if DEBUG
import Foundation
import CoreData
import SwiftData

/// Creates every record type of the library in CloudKit's development environment,
/// so the schema can be deployed to production in one go (docs/icloud-setup.md).
/// Runs once per install, in debug builds only, on a device signed in to iCloud;
/// it uses a store of its own in the temporary folder, apart from the library.
enum CloudSchema {
    static let container = "iCloud.com.kvds.LargeScore"
    private static let doneKey = "cloudSchemaInitialized"

    static func initializeIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey),
              !ProcessInfo.processInfo.arguments.contains("-resetSettings"),
              FileManager.default.ubiquityIdentityToken != nil,
              let model = NSManagedObjectModel.makeManagedObjectModel(for: [Score.self, Programme.self, ProgrammeEntry.self, Annotation.self])
        else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloudSchema.store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: container)
        description.shouldAddStoreAsynchronously = false
        let store = NSPersistentCloudKitContainer(name: "CloudSchema", managedObjectModel: model)
        store.persistentStoreDescriptions = [description]
        var loadError: Error?
        store.loadPersistentStores { _, error in loadError = error }
        guard loadError == nil else {
            print("CloudSchema: store not loaded: \(loadError!)")
            return
        }
        do {
            try store.initializeCloudKitSchema()
            defaults.set(true, forKey: doneKey)
            print("CloudSchema: development schema created in \(container)")
        } catch {
            print("CloudSchema: \(error)")
        }
        if let loaded = store.persistentStoreCoordinator.persistentStores.first {
            try? store.persistentStoreCoordinator.remove(loaded)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
