/*
 * Hanulim
 *
 * Copyright (C) 2007-2017  Sanghyuk Suh <han9kin@mac.com>
 * Copyright (C) 2026  Changmook Chun <cmookj@duck.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import CoreData

/// Singleton that manages the CoreData stack for the abbreviation system.
///
/// `HNDataController` owns the `NSManagedObjectModel` (compiled from the
/// bundled `.xcdatamodeld`), the `NSPersistentStoreCoordinator`, and a
/// single main-queue `NSManagedObjectContext`. All abbreviation lookups run
/// on the main queue through this shared context.
///
/// Persistent stores are SQLite databases (`.db` files) discovered at runtime
/// rather than at compile time, so users can add or remove abbreviation
/// databases by dropping files into:
///
///     ~/Library/Application Support/Hanulim/Abbrevs/
///
/// Call `addPersistentStores(inDomains:)` once at startup (done by
/// `HNCandidatesController.init`) to attach all `.db` files found in the
/// above directory for the specified search-path domain(s).
class HNDataController: NSObject {

    /// The process-wide singleton.
    nonisolated(unsafe) static let shared = HNDataController()

    private let persistentStoreCoordinator: NSPersistentStoreCoordinator
    private let managedObjectModel: NSManagedObjectModel

    /// Main-queue context used for all abbreviation fetch requests. Because
    /// it runs on the main queue, no additional locking is required as long
    /// as callers access it from the main thread (which IMKit callbacks do).
    let managedObjectContext: NSManagedObjectContext

    private override init() {
        // Merge all .xcdatamodeld definitions found in the main bundle into a
        // single model. Hanulim ships one model, so this is equivalent to
        // loading it by name.
        managedObjectModel = NSManagedObjectModel.mergedModel(from: nil)!

        persistentStoreCoordinator = NSPersistentStoreCoordinator(
            managedObjectModel: managedObjectModel
        )

        managedObjectContext = NSManagedObjectContext(.mainQueue)
        managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
    }

    /// Scans for `.db` files in `<ApplicationSupport>/Hanulim/Abbrevs/` within
    /// the given file-system domain(s) and attaches each one as a read-write
    /// SQLite persistent store.
    ///
    /// - Parameter domainMask: The search-path domain(s) to look in.
    ///   Passing `.userDomainMask` searches the current user's home directory,
    ///   which is the normal case for a per-user input method.
    ///
    /// The directory is created if it does not exist, so the user sees the
    /// expected location in Finder even on a fresh installation. Files that
    /// cannot be opened are logged and silently skipped so one corrupt
    /// database does not prevent the others from loading.
    func addPersistentStores(inDomains domainMask: FileManager.SearchPathDomainMask) {
        let fileManager = FileManager.default

        for basePath in NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, domainMask, true) {
            let path = (basePath as NSString)
                .appendingPathComponent("Hanulim")
                .appending("/Abbrevs")

            // Ensure the directory exists so the user can find the right
            // location without consulting documentation.
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

    /// Attaches a single `.db` file at the given absolute path as a SQLite
    /// persistent store.
    ///
    /// - Parameter path: Absolute file-system path to the SQLite database.
    /// - Returns: The error produced by CoreData if the store could not be
    ///   opened, or `nil` on success.
    ///
    /// This method is provided for callers (e.g. tests or a preference pane)
    /// that know the exact path of a store and do not need the directory-scan
    /// behaviour of `addPersistentStores(inDomains:)`.
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
