/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import CoreData
@preconcurrency import InputMethodKit

class HNCandidatesController: NSObject {

    nonisolated(unsafe) static var shared: HNCandidatesController?

    private let predicate: NSPredicate
    private let fetchRequest: NSFetchRequest<NSManagedObject>
    private let candidates: IMKCandidates

    init(server: IMKServer) {
        HNDataController.shared.addPersistentStores(inDomains: .userDomainMask)

        predicate    = NSPredicate(format: "abbrev.abbrev == $ABBREV")
        fetchRequest = NSFetchRequest<NSManagedObject>()
        candidates   = IMKCandidates(server: server, panelType: kIMKSingleRowSteppingCandidatePanel)

        let sortDesc = NSSortDescriptor(key: "expansion", ascending: true)
        fetchRequest.entity = NSEntityDescription.entity(
            forEntityName: "Expansion",
            in: HNDataController.shared.managedObjectContext
        )
        fetchRequest.sortDescriptors = [sortDesc]

        super.init()

        HNCandidatesController.shared = self
    }

    func candidates(for string: String) -> HNCandidates? {
        let variables: [String: Any] = ["ABBREV": string]
        fetchRequest.predicate = predicate.withSubstitutionVariables(variables)

        do {
            let results = try HNDataController.shared.managedObjectContext
                .fetch(fetchRequest)
            if results.isEmpty { return nil }
            return HNCandidates(expansionManagedObjects: results)
        } catch {
            NSApplication.shared.presentError(error)
            return nil
        }
    }

    func show() {
        candidates.show(kIMKLocateCandidatesBelowHint)
    }

    func hide() {
        candidates.hide()
    }

    func showAnnotation(_ annotation: String) {
        candidates.showAnnotation(NSAttributedString(string: annotation))
    }
}
