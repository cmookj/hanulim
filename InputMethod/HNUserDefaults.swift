/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Foundation

class HNUserDefaults: NSObject, HNICUserDefaults {

    nonisolated(unsafe) static let shared = HNUserDefaults()

    private(set) var usesSmartQuotationMarks:     Bool = false
    private(set) var inputsBackSlashInsteadOfWon: Bool = false
    private(set) var handlesCapsLockAsShift:       Bool = false
    private(set) var commitsImmediately:           Bool = false
    private(set) var usesDecomposedUnicode:        Bool = false

    private enum Keys {
        static let smartQuotationMarks     = "usesSmartQuotationMarks"
        static let backSlashInsteadOfWon   = "inputsBackSlashInsteadOfWon"
        static let capsLockAsShift         = "handlesCapsLockAsShift"
        static let commitsImmediately      = "commitsImmediately"
        static let decomposedUnicode       = "usesDecomposedUnicode"
    }

    private override init() {
        super.init()
        loadUserDefaults()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func loadUserDefaults() {
        let defaults = UserDefaults.standard
        usesSmartQuotationMarks     = defaults.bool(forKey: Keys.smartQuotationMarks)
        inputsBackSlashInsteadOfWon = defaults.bool(forKey: Keys.backSlashInsteadOfWon)
        handlesCapsLockAsShift       = defaults.bool(forKey: Keys.capsLockAsShift)
        commitsImmediately           = defaults.bool(forKey: Keys.commitsImmediately)
        usesDecomposedUnicode        = defaults.bool(forKey: Keys.decomposedUnicode)
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        HNLog("HNUserDefaults userDefaultsDidChange")
        loadUserDefaults()
    }
}
