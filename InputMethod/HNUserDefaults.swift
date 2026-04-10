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

/// Singleton that mirrors the input method's user preferences.
///
/// `HNUserDefaults` wraps `UserDefaults.standard` and conforms to the
/// `HNICUserDefaults` protocol, which is the interface through which
/// `HNInputContext` reads preferences (see `HNInputContext.swift`).
///
/// On initialisation the current values are loaded from `UserDefaults.standard`.
/// The class then subscribes to `UserDefaults.didChangeNotification` so that
/// any preference change — made, for example, in a companion preference pane —
/// takes effect immediately without requiring the user to log out or restart
/// the input method process.
///
/// All properties are read-only externally (`private(set)`). Callers should
/// access the singleton via `HNUserDefaults.shared`.
class HNUserDefaults: NSObject, HNICUserDefaults {

    /// The process-wide singleton. Created once and kept alive for the
    /// lifetime of the input method process.
    nonisolated(unsafe) static let shared = HNUserDefaults()

<<<<<<< HEAD
    /// When `true`, the input method converts straight apostrophes and
    /// quotation marks to their typographic ("curly") equivalents.
    private(set) var usesSmartQuotationMarks: Bool = false
||||||| b1e72a5
    private(set) var usesSmartQuotationMarks:     Bool = false
    private(set) var inputsBackSlashInsteadOfWon: Bool = false
    private(set) var handlesCapsLockAsShift:       Bool = false
    private(set) var commitsImmediately:           Bool = false
    private(set) var usesDecomposedUnicode:        Bool = false
=======
    private(set) var usesSmartQuotationMarks:       Bool = false
    private(set) var inputsBackSlashInsteadOfWon:   Bool = false
    private(set) var handlesCapsLockAsShift:         Bool = false
    private(set) var commitsImmediately:             Bool = false
    private(set) var usesDecomposedUnicode:          Bool = false
    /// When true, pressing ESC while a Hanulim Korean mode is active
    /// commits any in-progress composition and switches to the system's
    /// current ASCII-capable keyboard layout (useful for vi/vim users).
    private(set) var switchesToRomanOnEsc:           Bool = false
>>>>>>> develop

    /// When `true`, the backslash key (U+005C) is inserted literally instead
    /// of being mapped to the Korean Won sign (U+20A9), which occupies the
    /// same physical key on Korean keyboards.
    private(set) var inputsBackSlashInsteadOfWon: Bool = false

    /// When `true`, the Caps Lock key is treated as a Shift modifier rather
    /// than toggling between Roman and Korean input modes.
    private(set) var handlesCapsLockAsShift: Bool = false

    /// When `true`, each composed syllable block is committed to the client
    /// immediately upon completion rather than being held in the preedit
    /// buffer until the next keystroke resolves any ambiguity.
    private(set) var commitsImmediately: Bool = false

    /// When `true`, composed Hangul text is sent to the client in NFD
    /// (decomposed) Unicode form. Most modern applications work correctly
    /// with NFC; this option exists for legacy software that requires NFD.
    private(set) var usesDecomposedUnicode: Bool = false

    // Keys used to read values from UserDefaults.standard. They must match
    // the key strings declared in the preference pane and in any defaults
    // registration code.
    private enum Keys {
<<<<<<< HEAD
        static let smartQuotationMarks   = "usesSmartQuotationMarks"
        static let backSlashInsteadOfWon = "inputsBackSlashInsteadOfWon"
        static let capsLockAsShift       = "handlesCapsLockAsShift"
        static let commitsImmediately    = "commitsImmediately"
        static let decomposedUnicode     = "usesDecomposedUnicode"
||||||| b1e72a5
        static let smartQuotationMarks     = "usesSmartQuotationMarks"
        static let backSlashInsteadOfWon   = "inputsBackSlashInsteadOfWon"
        static let capsLockAsShift         = "handlesCapsLockAsShift"
        static let commitsImmediately      = "commitsImmediately"
        static let decomposedUnicode       = "usesDecomposedUnicode"
=======
        static let smartQuotationMarks       = "usesSmartQuotationMarks"
        static let backSlashInsteadOfWon     = "inputsBackSlashInsteadOfWon"
        static let capsLockAsShift           = "handlesCapsLockAsShift"
        static let commitsImmediately        = "commitsImmediately"
        static let decomposedUnicode         = "usesDecomposedUnicode"
        static let switchesToRomanOnEsc      = "switchesToRomanOnEsc"
>>>>>>> develop
    }

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [
            Keys.switchesToRomanOnEsc: false,
        ])
        loadUserDefaults()
        // Re-read all values whenever any preference changes so that the
        // running input method picks up the new settings without restarting.
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
<<<<<<< HEAD
        usesSmartQuotationMarks     = defaults.bool(forKey: Keys.smartQuotationMarks)
        inputsBackSlashInsteadOfWon = defaults.bool(forKey: Keys.backSlashInsteadOfWon)
        handlesCapsLockAsShift      = defaults.bool(forKey: Keys.capsLockAsShift)
        commitsImmediately          = defaults.bool(forKey: Keys.commitsImmediately)
        usesDecomposedUnicode       = defaults.bool(forKey: Keys.decomposedUnicode)
||||||| b1e72a5
        usesSmartQuotationMarks     = defaults.bool(forKey: Keys.smartQuotationMarks)
        inputsBackSlashInsteadOfWon = defaults.bool(forKey: Keys.backSlashInsteadOfWon)
        handlesCapsLockAsShift       = defaults.bool(forKey: Keys.capsLockAsShift)
        commitsImmediately           = defaults.bool(forKey: Keys.commitsImmediately)
        usesDecomposedUnicode        = defaults.bool(forKey: Keys.decomposedUnicode)
=======
        usesSmartQuotationMarks       = defaults.bool(forKey: Keys.smartQuotationMarks)
        inputsBackSlashInsteadOfWon   = defaults.bool(forKey: Keys.backSlashInsteadOfWon)
        handlesCapsLockAsShift         = defaults.bool(forKey: Keys.capsLockAsShift)
        commitsImmediately             = defaults.bool(forKey: Keys.commitsImmediately)
        usesDecomposedUnicode          = defaults.bool(forKey: Keys.decomposedUnicode)
        switchesToRomanOnEsc           = defaults.bool(forKey: Keys.switchesToRomanOnEsc)
>>>>>>> develop
    }

    @objc private func userDefaultsDidChange(_ notification: Notification) {
        HNLog("HNUserDefaults userDefaultsDidChange")
        loadUserDefaults()
    }
}
