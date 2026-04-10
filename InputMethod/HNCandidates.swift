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

/// Immutable value object that holds the result of a single abbreviation lookup.
///
/// `HNCandidates` is created by `HNCandidatesController.candidates(for:)` from
/// an array of `Expansion` managed objects returned by a CoreData fetch. It
/// extracts the plain-string data it needs and discards the managed objects,
/// so the caller does not need to keep the managed object context alive.
///
/// The two main pieces of data are:
/// - `expansions`: the ordered list of Korean strings to show in the
///   candidates panel.
/// - `annotations`: a dictionary mapping each expansion string to its
///   optional annotation, used to display supplementary information in the
///   panel when the user dwells on a candidate.
class HNCandidates {

    /// The expanded Korean strings to present in the IMKCandidates panel,
    /// in the same order as the CoreData fetch results (sorted ascending by
    /// the `expansion` attribute).
    let expansions: [String]

    /// Maps expansion strings to their annotation text. Only entries where
    /// the annotation is non-empty are stored, so a lookup returns `nil`
    /// when no annotation exists rather than returning an empty string.
    private let annotations: [String: String]

    /// Initialises a `HNCandidates` from an array of `Expansion` managed objects.
    ///
    /// KVC batch access (`value(forKey:)` on the array cast to `NSArray`) is
    /// used to extract all `expansion` and `annotation` attribute values in
    /// a single pass, which is more efficient than iterating and calling
    /// `value(forKey:)` on each object individually.
    ///
    /// - Parameter records: `Expansion` managed objects returned by the
    ///   CoreData fetch in `HNCandidatesController`.
    init(expansionManagedObjects records: [NSManagedObject]) {
        let allExpansions  = (records as NSArray).value(forKey: "expansion")  as? [String] ?? []
        let allAnnotations = (records as NSArray).value(forKey: "annotation") as? [Any]    ?? []

        expansions = allExpansions

        // Build the annotations dictionary, skipping entries where the
        // annotation attribute is NSNull or an empty string.
        var dict = [String: String]()
        for (expansion, annotation) in zip(allExpansions, allAnnotations) {
            if let str = annotation as? String, !str.isEmpty {
                dict[expansion] = str
            }
        }
        annotations = dict
    }

    /// Returns the annotation for `string`, or `nil` if no annotation exists.
    ///
    /// Called by `HNCandidatesController.showAnnotation(_:)` when the user
    /// selects a candidate in the panel.
    func annotation(for string: String) -> String? {
        return annotations[string]
    }
}
