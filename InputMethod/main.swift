/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
 *
 * Entry point for the Hanulim input method process.
 *
 * macOS launches input methods as ordinary background applications. This file
 * performs the minimal bootstrap required before handing control to the run
 * loop:
 *
 *   1. Read the Mach port name from Info.plist ("InputMethodConnectionName").
 *      IMKit uses this name to locate the input method process on the system
 *      message bus.
 *   2. Create an IMKServer bound to that port. IMKServer is the connection point
 *      between the macOS text input infrastructure and this process; it accepts
 *      incoming connections from client applications and vends
 *      HNInputController instances to handle each text session.
 *   3. Create HNCandidatesController, which owns the IMKCandidates panel and
 *      sets up the CoreData stack (including loading all .db abbreviation files
 *      from ~/Library/Application Support/Hanulim/Abbrevs/).
 *   4. Load MainMenu.nib, which instantiates HNAppController and connects the
 *      NSMenu outlet used by the input method's menu bar item.
 *   5. Enter the run loop.  The `_ =` assignments after the run loop return
 *      are the only references that keep `server` and `candidatesController`
 *      alive for the entire lifetime of the process; without them the ARC
 *      optimizer could release those objects before the run loop exits.
 */

import Cocoa
import InputMethodKit

autoreleasepool {
    let bundle = Bundle.main

    // "InputMethodConnectionName" is declared in Info.plist and must match the
    // MachServices entry in the launchd plist that registers this input method
    // with the system. IMKServer registers itself under this Mach port name so
    // that client apps can find and connect to the process.
    let connectionName = bundle.infoDictionary?["InputMethodConnectionName"] as! String

    // IMKServer listens on the named Mach port and creates one
    // HNInputController per client text session (identified by bundleIdentifier).
    let server = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)

    // HNCandidatesController initialises the CoreData persistent store
    // coordinator and loads abbreviation .db files, so it must be created
    // before any key events can trigger an abbreviation lookup.
    let candidatesController = HNCandidatesController(server: server!)

    // Loading MainMenu.nib instantiates HNAppController and connects the
    // NSMenu IBOutlet that the input method's menu bar item displays.
    Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: nil)

    NSApplication.shared.run()

    // Explicit references after run() returns prevent ARC from releasing these
    // objects before the autorelease pool drains at process exit.
    _ = candidatesController
    _ = server
}
