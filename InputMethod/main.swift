/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 */

import Cocoa
import Carbon
import InputMethodKit

autoreleasepool {
    let bundle             = Bundle.main

    // Re-register the bundle so the system picks up any new or changed input
    // modes (e.g. the Roman mode icon) without requiring a logout/login.
    TISRegisterInputSource(bundle.bundleURL as CFURL)

    let connectionName     = bundle.infoDictionary?["InputMethodConnectionName"] as! String
    let server             = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
    let candidatesController = HNCandidatesController(server: server!)

    Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: nil)

    NSApplication.shared.run()

    _ = candidatesController  // keep alive until app exits
    _ = server
}
