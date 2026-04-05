/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Cocoa
import InputMethodKit

autoreleasepool {
    let bundle             = Bundle.main
    let connectionName     = bundle.infoDictionary?["InputMethodConnectionName"] as! String
    let server             = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
    let candidatesController = HNCandidatesController(server: server!)

    Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: nil)

    NSApplication.shared.run()

    _ = candidatesController  // keep alive until app exits
    _ = server
}
