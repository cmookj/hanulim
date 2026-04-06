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

class HNCandidates {

    let expansions: [String]
    private let annotations: [String: String]

    init(expansionManagedObjects records: [NSManagedObject]) {
        let allExpansions = (records as NSArray).value(forKey: "expansion") as? [String] ?? []
        let allAnnotations = (records as NSArray).value(forKey: "annotation") as? [Any] ?? []

        expansions = allExpansions

        var dict = [String: String]()
        for (expansion, annotation) in zip(allExpansions, allAnnotations) {
            if let str = annotation as? String, !str.isEmpty {
                dict[expansion] = str
            }
        }
        annotations = dict
    }

    func annotation(for string: String) -> String? {
        return annotations[string]
    }
}
