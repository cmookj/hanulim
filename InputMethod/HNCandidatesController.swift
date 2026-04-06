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
