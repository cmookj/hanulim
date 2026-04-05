/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Cocoa
import InputMethodKit

class HNAppController: NSObject {

    nonisolated(unsafe) static var shared: HNAppController?

    @IBOutlet var menu: NSMenu!

    override func awakeFromNib() {
        super.awakeFromNib()
        HNAppController.shared = self
    }
}
