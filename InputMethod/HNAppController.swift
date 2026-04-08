/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
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
