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
import CoreData

class AEAppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        HNDataController.shared.addPersistentStores(inDomains: .userDomainMask)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let context = HNDataController.shared.managedObjectContext

        guard context.commitEditing() else { return .terminateCancel }

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let presented = sender.presentError(error)
                if presented { return .terminateCancel }

                let alert = NSAlert()
                alert.messageText = "Could not save changes while quitting. Quit anyway?"
                alert.addButton(withTitle: "Quit anyway")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertSecondButtonReturn {
                    return .terminateCancel
                }
            }
        }
        return .terminateNow
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        return HNDataController.shared.managedObjectContext.undoManager
    }

    var managedObjectContext: NSManagedObjectContext {
        return HNDataController.shared.managedObjectContext
    }

    @IBAction func saveAction(_ sender: Any) {
        do {
            try HNDataController.shared.managedObjectContext.save()
        } catch {
            NSApplication.shared.presentError(error)
        }
    }
}
