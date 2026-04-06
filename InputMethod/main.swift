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
import Carbon
import InputMethodKit

autoreleasepool {
    let bundle             = Bundle.main

    // Re-register the bundle so the system picks up any new or changed input
    // modes (e.g. the Roman mode icon) without requiring a logout/login.
    TISRegisterInputSource(bundle.bundleURL as CFURL)

    // Install the system-level event tap for Shift+Space mode toggle.
    // Must be called before NSApplication.run() so the run loop is available.
    HNEventTap.shared.start()

    let connectionName     = bundle.infoDictionary?["InputMethodConnectionName"] as! String
    let server             = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
    let candidatesController = HNCandidatesController(server: server!)

    Bundle.main.loadNibNamed("MainMenu", owner: NSApplication.shared, topLevelObjects: nil)

    NSApplication.shared.run()

    _ = candidatesController  // keep alive until app exits
    _ = server
}
