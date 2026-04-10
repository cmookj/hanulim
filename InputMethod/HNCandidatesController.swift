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

/// Singleton that owns the IMKCandidates panel and performs CoreData lookups.
///
/// `HNCandidatesController` is created once in `main.swift` immediately after
/// `IMKServer`, so it outlives every `HNInputController` instance (which are
/// created and destroyed by IMKit as text sessions open and close). This
/// lifetime guarantee means the CoreData stack and the candidates panel are
/// always available when an input controller needs them.
///
/// On initialisation the controller:
/// - Loads all `.db` abbreviation files from
///   `~/Library/Application Support/Hanulim/Abbrevs/` via `HNDataController`.
/// - Prepares a reusable `NSFetchRequest` targeting the `Expansion` entity,
///   sorted ascending by the `expansion` attribute.
/// - Creates the `IMKCandidates` panel in single-row stepping style.
///
/// The `shared` singleton is set inside `init` (after `super.init()`) so
/// that it is available to `HNInputController` instances as soon as the
/// first one is created by IMKit.
class HNCandidatesController: NSObject {

    /// The process-wide singleton, set during `init(server:)`.
    /// Declared `nonisolated(unsafe)` because it is written once on the main
    /// thread at startup and then read from IMKit callbacks.
    nonisolated(unsafe) static var shared: HNCandidatesController?

    /// Template predicate used for every abbreviation lookup. Substitution
    /// variables are filled in per-query via `withSubstitutionVariables(_:)`,
    /// which avoids reparsing the format string on every keystroke.
    ///
    /// Format: `"abbrev.abbrev == $ABBREV"`
    ///
    /// The `Expansion` entity has a to-one relationship called `abbrev` to the
    /// `Abbrev` entity. The `Abbrev` entity has a string attribute also named
    /// `abbrev`. The predicate therefore traverses the relationship and tests
    /// whether the parent `Abbrev`'s abbreviation string equals the composed
    /// input string. This design allows one abbreviation to have many
    /// associated expansions while keeping the lookup efficient.
    private let predicate: NSPredicate

    /// Reusable fetch request targeting the `Expansion` entity, sorted
    /// ascending by `expansion`. The predicate is replaced before each fetch.
    private let fetchRequest: NSFetchRequest<NSManagedObject>

    /// The floating candidates panel managed by InputMethodKit.
    private let candidates: IMKCandidates

    init(server: IMKServer) {
        // Load abbreviation databases before any fetch can be attempted.
        HNDataController.shared.addPersistentStores(inDomains: .userDomainMask)

        predicate    = NSPredicate(format: "abbrev.abbrev == $ABBREV")
        fetchRequest = NSFetchRequest<NSManagedObject>()
        // kIMKSingleRowSteppingCandidatePanel displays one candidate at a time
        // and lets the user step through them, which suits a narrow panel.
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

    /// Fetches all `Expansion` records whose parent `Abbrev.abbrev` equals
    /// `string` and wraps them in an `HNCandidates` value object.
    ///
    /// - Parameter string: The composed Hangul or Roman string to look up.
    /// - Returns: An `HNCandidates` containing the matching expansions, or
    ///   `nil` if no records were found or if the fetch throws an error.
    ///
    /// A substitution variable is used instead of building a new `NSPredicate`
    /// each call, which avoids repeated format-string parsing.
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

    /// Displays the candidates panel below the current insertion point.
    ///
    /// `kIMKLocateCandidatesBelowHint` asks IMKit to position the panel just
    /// below the preedit text so it does not obscure what the user is typing.
    func show() {
        candidates.show(kIMKLocateCandidatesBelowHint)
    }

    /// Hides the candidates panel without committing any candidate.
    func hide() {
        candidates.hide()
    }

    /// Displays `annotation` as supplementary text in the candidates panel.
    ///
    /// Called when the user dwells on or selects a candidate that has an
    /// associated annotation in the abbreviation database.
    ///
    /// - Parameter annotation: Plain text to show alongside the candidate.
    func showAnnotation(_ annotation: String) {
        candidates.showAnnotation(NSAttributedString(string: annotation))
    }
}
