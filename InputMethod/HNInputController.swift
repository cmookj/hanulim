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

@objc(HNInputController)
class HNInputController: IMKInputController {

    private let inputContext = HNInputContext()
    private var currentCandidates: HNCandidates?

    /// The most recently active controller instance. Used by the CGEventTap
    /// to commit composition before switching to the ASCII layout.
    /// Only written on the main thread; reading from the tap thread is safe
    /// for the same reason as HNInputContext.isComposing.
    nonisolated(unsafe) static weak var active: HNInputController?

    /// The client passed to the most recent handle(_:client:) call. Stored so
    /// that commitForEsc() can reach the client without a handle() argument.
    private weak var activeClient: AnyObject?

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        HNLog("HNInputController \(String(describing: self)) initWithServer")
        inputContext.userDefaults = HNUserDefaults.shared
    }

    override func activateServer(_ sender: Any!) {
        HNLog("HNInputController \(String(describing: self)) activateServer")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        HNLog("HNInputController \(String(describing: self)) deactivateServer")
        super.deactivateServer(sender)
    }

    // MARK: - IMKInputController overrides

    override func annotationSelected(_ annotationString: NSAttributedString!, forCandidate candidateString: NSAttributedString!) {
        HNLog("HNInputController annotationSelected: \(annotationString.string) forCandidate: \(candidateString.string)")
    }

    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        HNLog("HNInputController candidateSelectionChanged: \(candidateString.string)")
        if let annotation = currentCandidates?.annotation(for: candidateString.string) {
            HNCandidatesController.shared?.showAnnotation(annotation)
        }
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        HNLog("HNInputController candidateSelected: \(candidateString.string)")
        client().insertText(
            candidateString.string,
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
        inputContext.cancelComposition()
    }

    override func hidePalettes() {
        HNLog("HNInputController hidePalettes")
        currentCandidates = nil
        super.hidePalettes()
    }

    override func menu() -> NSMenu! {
        HNLog("HNInputController menu")
        return HNAppController.shared?.menu
    }
}

// MARK: - ESC composition commit (called from event tap)

extension HNInputController {

    /// Called by HNEventTap when it has already consumed an ESC event and needs
    /// to commit any in-progress composition before posting a synthetic ESC.
    /// Must be called on the main thread.
    func commitForEsc() {
        let client = activeClient as? (any IMKTextInput)
        inputContext.commitComposition(client: client)
    }
}

// MARK: - IMKStateSetting

extension HNInputController {

    override func recognizedEvents(_ sender: Any!) -> Int {
        let mask: NSEvent.EventTypeMask
        if inputContext.composedString != nil {
            mask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        } else {
            mask = [.keyDown]
        }
        HNLog("HNInputController recognizedEvents: \(String(format: "%lx", mask.rawValue))")
        return Int(mask.rawValue)
    }

    /// Called by the system when the input mode changes — for example when the
    /// user picks a different Hanulim sub-mode (두벌식, 세벌식, …) from the menu
    /// bar or when the focused app activates.
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == kTSMDocumentInputModePropertyTag, let name = value as? String {
            HNLog("HNInputController setValue: mode=\(name)")
            inputContext.setKeyboardLayout(name: name)
        }
    }
}

// MARK: - IMKServerInput

extension HNInputController {

    // handle(_:client:) is used instead of inputText(_:key:modifiers:client:).
    // When handle returns false the raw NSEvent is re-dispatched through the
    // normal event chain and the app's keyDown: is called — which is what
    // terminal emulators like Ghostty require. inputText returning false goes
    // through IMK's text machinery and may not reach keyDown: reliably.
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown else { return false }

        // Keep the tap-accessible references current so commitForEsc() works.
        HNInputController.active = self
        activeClient = sender as AnyObject?

        HNLog("HNInputController handle: keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue)")

        var sHandled        = false
        var sShowCandidates = false

        let deviceFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let string      = event.characters ?? ""
        let keyCode     = Int(event.keyCode)
        let rawFlags    = Int(bitPattern: UInt(event.modifierFlags.rawValue))
        let firstChar   = string.unicodeScalars.first?.value

        let noModifiers = deviceFlags.intersection([.shift, .control, .option, .command]).isEmpty

        if noModifiers, keyCode == 53,
           HNUserDefaults.shared.switchesToRomanOnEsc,
           !HNEventTap.shared.isConsuming {
            // ESC fallback — only reached when the consuming tap is NOT active
            // (Accessibility permission not granted).  When the consuming tap IS
            // running, it handles both sub-cases itself:
            //   • Composing: tap consumes ESC, commits composition, switches to
            //     ASCII, then posts a synthetic ESC.  This branch is never
            //     reached for that event.
            //   • Not composing: tap passes ESC through and schedules
            //     switchToASCII() asynchronously.  The isConsuming guard above
            //     prevents a redundant second call from this branch.
            //
            // Here (no tap) we commit any in-progress composition, switch to the
            // ASCII layout, and pass the ESC through (return false) so the
            // focused app receives it.  Terminal emulators may need a second ESC
            // when composition was active, because they already classified the
            // original event as "dismiss preedit" at arrival time.
            HNLog("HNInputController: ESC fallback (no tap) → commit and switch to ASCII")
            inputContext.commitComposition(client: sender as? (any IMKTextInput))
            HNEventTap.shared.switchToASCII()
            sHandled = false
        } else if deviceFlags == .option, firstChar == 0x0d {
            // Option + Return: show abbreviation candidates
            if let composed = inputContext.composedString {
                currentCandidates = HNCandidatesController.shared?.candidates(for: composed)
                if currentCandidates != nil {
                    sShowCandidates = true
                }
                sHandled = true
            }
        } else {
            let textClient = sender as? (any IMKTextInput)
            sHandled = inputContext.handleKey(
                string: string,
                keyCode: keyCode,
                modifiers: rawFlags,
                client: textClient
            )
            currentCandidates = nil
        }

        if sShowCandidates {
            HNCandidatesController.shared?.show()
        } else {
            HNCandidatesController.shared?.hide()
        }

        HNLog("HNInputController handle => \(sHandled ? "YES" : "NO")")
        return sHandled
    }

    override func commitComposition(_ sender: Any!) {
        HNLog("HNInputController commitComposition")
        inputContext.commitComposition(client: sender as? (any IMKTextInput))
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        HNLog("HNInputController candidates")
        let result = currentCandidates?.expansions
        HNLog("HNInputController candidates => \(String(describing: result))")
        return result
    }
}

// MARK: - IMKMouseHandling

extension HNInputController {

    override func mouseDown(onCharacterIndex index: Int,
                            coordinate point: NSPoint,
                            withModifier flags: Int,
                            continueTracking keepTracking: UnsafeMutablePointer<ObjCBool>!,
                            client sender: Any!) -> Bool {
        HNLog("HNInputController mouseDown")
        inputContext.commitComposition(client: sender as? (any IMKTextInput))
        return false
    }
}
