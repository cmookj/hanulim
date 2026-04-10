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

import Foundation

class HNUserDefaults: NSObject, HNICUserDefaults {

    nonisolated(unsafe) static let shared = HNUserDefaults()

    private(set) var usesSmartQuotationMarks:       Bool = false
    private(set) var inputsBackSlashInsteadOfWon:   Bool = false
    private(set) var handlesCapsLockAsShift:         Bool = false
    private(set) var commitsImmediately:             Bool = false
    private(set) var usesDecomposedUnicode:          Bool = false
    /// When true, pressing ESC while a Hanulim Korean mode is active
    /// commits any in-progress composition and switches to the system's
    /// current ASCII-capable keyboard layout (useful for vi/vim users).
    private(set) var switchesToRomanOnEsc:           Bool = false

    private enum Keys {
        static let smartQuotationMarks       = "usesSmartQuotationMarks"
        static let backSlashInsteadOfWon     = "inputsBackSlashInsteadOfWon"
        static let capsLockAsShift           = "handlesCapsLockAsShift"
        static let commitsImmediately        = "commitsImmediately"
        static let decomposedUnicode         = "usesDecomposedUnicode"
        static let switchesToRomanOnEsc      = "switchesToRomanOnEsc"
    }

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            Keys.switchesToRomanOnEsc: false,
        ])
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
        usesSmartQuotationMarks       = defaults.bool(forKey: Keys.smartQuotationMarks)
        inputsBackSlashInsteadOfWon   = defaults.bool(forKey: Keys.backSlashInsteadOfWon)
        handlesCapsLockAsShift         = defaults.bool(forKey: Keys.capsLockAsShift)
        commitsImmediately             = defaults.bool(forKey: Keys.commitsImmediately)
        usesDecomposedUnicode          = defaults.bool(forKey: Keys.decomposedUnicode)
        switchesToRomanOnEsc           = defaults.bool(forKey: Keys.switchesToRomanOnEsc)
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        HNLog("HNUserDefaults userDefaultsDidChange")
        loadUserDefaults()
    }
}
