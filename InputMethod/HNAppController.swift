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

import Cocoa
import InputMethodKit

/// Controller object instantiated from MainMenu.nib.
///
/// `HNAppController` owns the `NSMenu` that the input method displays in the
/// macOS menu bar (or in the Input Sources menu). It is created automatically
/// when `loadNibNamed("MainMenu")` is called in `main.swift`.
///
/// After the nib is loaded, `awakeFromNib()` stores `self` in the `shared`
/// singleton so that `HNInputController` instances — which are created later,
/// on demand, by `IMKServer` — can retrieve the menu without needing a direct
/// reference to the nib owner.
class HNAppController: NSObject {

    /// The singleton instance set when the nib is loaded.
    /// Declared `nonisolated(unsafe)` because it is written from the main
    /// thread at startup and subsequently read from IMKit callbacks that may
    /// arrive on other threads.
    nonisolated(unsafe) static var shared: HNAppController?

    /// The input method's menu, connected via the MainMenu.nib IBOutlet.
    /// Passed to `IMKInputController.menu()` so macOS can display it in the
    /// Input Sources menu.
    @IBOutlet var menu: NSMenu!

    override func awakeFromNib() {
        super.awakeFromNib()
        HNAppController.shared = self
    }
}
