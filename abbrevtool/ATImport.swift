/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation
import CoreData

class ATImport: NSObject {

    private let predicateAbbrev:    NSPredicate
    private let predicateExpansion: NSPredicate
    private let fetchReqAbbrev:     NSFetchRequest<NSManagedObject>
    private let fetchReqExpansion:  NSFetchRequest<NSManagedObject>

    private var usesFilter    = false
    private var processCount  = 0
    private var importCount   = 0

    override init() {
        let context = HNDataController.shared.managedObjectContext

        predicateAbbrev    = NSPredicate(format: "abbrev == $ABBREV")
        predicateExpansion = NSPredicate(format: "abbrev == $ABBREV and expansion == $EXPANSION")

        fetchReqAbbrev = NSFetchRequest<NSManagedObject>()
        fetchReqAbbrev.entity = NSEntityDescription.entity(
            forEntityName: "Abbrev", in: context
        )

        fetchReqExpansion = NSFetchRequest<NSManagedObject>()
        fetchReqExpansion.entity = NSEntityDescription.entity(
            forEntityName: "Expansion", in: context
        )

        super.init()
    }

    // MARK: - Command entry point

    @objc func doWithArguments(_ args: [String]) {
        let context = HNDataController.shared.managedObjectContext
        var outFile: String?
        var inFiles = [String]()

        var idx = args.startIndex
        while idx < args.endIndex {
            let arg = args[idx]
            if arg == "-o" {
                idx = args.index(after: idx)
                if idx < args.endIndex { outFile = args[idx] }
            } else if arg == "-f" {
                usesFilter = true
            } else {
                inFiles.append(arg)
            }
            idx = args.index(after: idx)
        }

        guard let outPath = outFile else { return }

        context.undoManager = nil

        if let error = HNDataController.shared.addPersistentStore(atPath: outPath) {
            NSLog("\(error)")
            return
        }

        let categoryName = ((outPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        guard let category = categoryObject(named: categoryName, createIfNeeded: true) else { return }

        processCount = 0
        importCount  = 0

        for file in inFiles {
            importFile(at: file, category: category)
            do {
                try context.save()
            } catch {
                NSLog("\(error)")
                NSLog("\(error as NSError)")
            }
        }

        NSLog("\(processCount) records processed, \(importCount) records imported")
    }

    // MARK: - Private helpers

    private func abbrevObject(for string: String, createIfNeeded create: Bool) -> NSManagedObject? {
        let context = HNDataController.shared.managedObjectContext
        fetchReqAbbrev.predicate = predicateAbbrev
            .withSubstitutionVariables(["ABBREV": string])

        guard let results = try? context.fetch(fetchReqAbbrev) else {
            NSLog("Error fetching abbrev \(string)")
            return nil
        }

        if results.isEmpty {
            guard create else { return nil }
            let obj = NSEntityDescription.insertNewObject(forEntityName: "Abbrev", into: context)
            obj.setValue(string, forKey: "abbrev")
            return obj
        } else if results.count == 1 {
            return results[0]
        } else {
            NSLog("Too many abbrev records for \(string)")
            return nil
        }
    }

    private func categoryObject(named name: String, createIfNeeded create: Bool) -> NSManagedObject? {
        let context = HNDataController.shared.managedObjectContext
        let request = NSFetchRequest<NSManagedObject>()
        request.entity = NSEntityDescription.entity(forEntityName: "Category", in: context)
        request.predicate = NSPredicate(format: "category == %@", name)

        guard let results = try? context.fetch(request) else {
            NSLog("Error fetching category \(name)")
            return nil
        }

        if results.isEmpty {
            guard create else { return nil }
            let obj = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
            obj.setValue(name, forKey: "category")
            return obj
        } else {
            return results[0]
        }
    }

    private func expansionObject(for abbrev: NSManagedObject, string: String) -> NSManagedObject? {
        let context = HNDataController.shared.managedObjectContext
        fetchReqExpansion.predicate = predicateExpansion
            .withSubstitutionVariables(["ABBREV": abbrev, "EXPANSION": string])

        guard let results = try? context.fetch(fetchReqExpansion) else {
            NSLog("Error fetching expansion \(string)")
            return nil
        }

        if results.isEmpty {
            return NSEntityDescription.insertNewObject(forEntityName: "Expansion", into: context)
        } else if results.count == 1 {
            return results[0]
        } else {
            NSLog("Too many expansion records for \(string)")
            return nil
        }
    }

    private func shouldImport(expansion: String, abbrev: String) -> Bool {
        for ch in abbrev.unicodeScalars {
            if expansion.unicodeScalars.contains(ch) { return false }
        }
        return true
    }

    @discardableResult
    private func addExpansion(_ expansion: String, annotation: String,
                               forAbbrev abbrevStr: String,
                               inCategory category: NSManagedObject) -> Bool {
        let doImport = usesFilter
            ? shouldImport(expansion: expansion, abbrev: abbrevStr)
            : true

        if doImport {
            guard let abbrevObj = abbrevObject(for: abbrevStr, createIfNeeded: true),
                  let expObj    = expansionObject(for: abbrevObj, string: expansion)
            else { return false }

            expObj.setValue(abbrevObj, forKey: "abbrev")
            expObj.setValue(category, forKey: "category")
            expObj.setValue(expansion, forKey: "expansion")
            if !annotation.isEmpty {
                expObj.setValue(annotation, forKey: "annotation")
            }
        }
        return doImport
    }

    private func importFile(at path: String, category: NSManagedObject) {
        let context = HNDataController.shared.managedObjectContext

        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            NSLog("Could not read file \(path)")
            return
        }

        for line in contents.components(separatedBy: "\n") {
            autoreleasepool {
                guard !line.hasPrefix("#") else { return }
                let parts = line.components(separatedBy: ":")
                guard parts.count == 3 else { return }

                processCount += 1

                if addExpansion(parts[1], annotation: parts[2],
                                forAbbrev: parts[0], inCategory: category) {
                    importCount += 1
                }

                if processCount % 1000 == 0 {
                    do {
                        try context.save()
                    } catch {
                        NSLog("\(error)")
                    }
                    NSLog("\(processCount) records processed, \(importCount) records imported")
                }
            }
        }
    }
}
