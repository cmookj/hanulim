/*
 * Hanulim
 *
 * Original Objective-C code - https://github.com/han9kin/hanulim
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
