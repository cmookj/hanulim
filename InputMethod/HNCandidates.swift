/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
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
