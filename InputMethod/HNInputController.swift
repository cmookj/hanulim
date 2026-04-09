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

private let kRomanModeID = "org.cocomelo.inputmethod.Hanulim.Roman"

@objc(HNInputController)
class HNInputController: IMKInputController {

    private let inputContext = HNInputContext()
    private var currentCandidates: HNCandidates?

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        HNLog("HNInputController \(String(describing: self)) initWithServer")
        inputContext.userDefaults = HNUserDefaults.shared
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

// MARK: - Roman Mode Toggle

extension HNInputController {

    // Delegate to HNEventTap.shared which reads TIS state directly (ground
    // truth) rather than per-instance inputContext.isRomanMode, ensuring the
    // toggle works correctly regardless of which controller instance is active.
    private func toggleRomanMode() {
        HNLog("HNInputController: toggleRomanMode called")
        HNEventTap.shared.toggleRomanMode()
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

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == kTSMDocumentInputModePropertyTag, let name = value as? String {
            HNLog("HNInputController setValue: mode=\(name)")
            inputContext.setKeyboardLayout(name: name)
            if name != kRomanModeID {
                HNEventTap.shared.lastKoreanModeID = name
            }
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

        HNLog("HNInputController handle: keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue)")

        var sHandled        = false
        var sShowCandidates = false

        let deviceFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let string      = event.characters ?? ""
        let keyCode     = Int(event.keyCode)
        let rawFlags    = Int(bitPattern: UInt(event.modifierFlags.rawValue))
        let firstChar   = string.unicodeScalars.first?.value

        let noModifiers = deviceFlags.intersection([.shift, .control, .option, .command]).isEmpty

        let isShiftOnly = deviceFlags.contains(.shift) &&
            !deviceFlags.contains(.control) &&
            !deviceFlags.contains(.option) &&
            !deviceFlags.contains(.command)
        if isShiftOnly, keyCode == 49,
           HNUserDefaults.shared.usesShiftSpaceForRomanMode {
            // Shift+Space: toggle Roman (Latin bypass) mode.
            // Only active when usesShiftSpaceForRomanMode is enabled.
            // When HNEventTap is active (Accessibility granted) this branch is
            // never reached because the event tap consumes Shift+Space before
            // any application — including Ghostty — sees it. This branch acts
            // as a fallback when Accessibility permission has not been granted.
            HNLog("HNInputController: Shift+Space in handle() — tapConsuming=\(HNEventTap.shared.isConsuming)")
            inputContext.commitComposition(client: sender as? (any IMKTextInput))
            toggleRomanMode()
            sHandled = true
        } else if noModifiers, keyCode == 53,
                  HNUserDefaults.shared.switchesToRomanOnEsc,
                  HNEventTap.shared.isCurrentlyKoreanHanulimMode() {
            // ESC: commit any in-progress composition, switch to Roman mode,
            // and pass the original ESC through so that the application
            // (e.g. vim/neovim) receives it and exits insert mode.
            HNLog("HNInputController: ESC → switching to Roman mode")
            inputContext.commitComposition(client: sender as? (any IMKTextInput))
            HNEventTap.shared.selectInputSource(id: "org.cocomelo.inputmethod.Hanulim.Roman")
            sHandled = false  // always pass ESC through
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
