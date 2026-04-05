/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import CoreData

class HNDataController: NSObject {

    nonisolated(unsafe) static let shared = HNDataController()

    private let persistentStoreCoordinator: NSPersistentStoreCoordinator
    private let managedObjectModel: NSManagedObjectModel
    let managedObjectContext: NSManagedObjectContext

    private override init() {
        managedObjectModel = NSManagedObjectModel.mergedModel(from: nil)!

        persistentStoreCoordinator = NSPersistentStoreCoordinator(
            managedObjectModel: managedObjectModel
        )

        managedObjectContext = NSManagedObjectContext(.mainQueue)
        managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
    }

    func addPersistentStores(inDomains domainMask: FileManager.SearchPathDomainMask) {
        let fileManager = FileManager.default

        for basePath in NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, domainMask, true) {
            let path = (basePath as NSString)
                .appendingPathComponent("Hanulim")
                .appending("/Abbrevs")

            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)

            guard let files = try? fileManager.contentsOfDirectory(atPath: path) else { continue }

            for file in files where (file as NSString).pathExtension == "db" {
                let url = URL(fileURLWithPath: (path as NSString).appendingPathComponent(file))
                do {
                    try persistentStoreCoordinator.addPersistentStore(
                        ofType: NSSQLiteStoreType,
                        configurationName: nil,
                        at: url,
                        options: nil
                    )
                } catch {
                    NSLog("adding database file failed at (\(url.path)) error: \(error)")
                }
            }
        }
    }

    func addPersistentStore(atPath path: String) -> Error? {
        let url = URL(fileURLWithPath: path)
        do {
            try persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: url,
                options: nil
            )
            return nil
        } catch {
            return error
        }
    }
}
