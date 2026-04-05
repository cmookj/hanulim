/*
 * Hanulim
 *
 * http://code.google.com/p/hanulim
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

    private func toggleRomanMode() {
        // Roman mode is a registered input source (added in System Settings,
        // just like 2standard or 3final). TISSelectInputSource switches to it,
        // and the system calls setValue:forTag:client: which drives isRomanMode
        // via setKeyboardLayout — no direct flag manipulation needed here.
        let targetID = inputContext.isRomanMode
            ? inputContext.lastKoreanModeID
            : kRomanModeID
        selectInputSource(id: targetID)
    }

    private func selectInputSource(id: String) {
        let cfID = id as CFString
        let filterDict = [kTISPropertyInputSourceID: cfID] as CFDictionary
        guard let list = TISCreateInputSourceList(filterDict, true)?.takeRetainedValue(),
              CFArrayGetCount(list) > 0,
              let rawPtr = CFArrayGetValueAtIndex(list, 0) else {
            HNLog("selectInputSource: not found: \(id)")
            return
        }
        let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
        let err = TISSelectInputSource(source)
        HNLog("selectInputSource: \(id) → OSStatus \(err)")
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
        HNLog("HNInputController setValue: \(String(describing: value)) forTag: \(tag)")
        if tag == kTSMDocumentInputModePropertyTag, let name = value as? String {
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

        HNLog("HNInputController handle: keyCode=\(event.keyCode) modifiers=\(event.modifierFlags.rawValue)")

        var sHandled        = false
        var sShowCandidates = false

        let deviceFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let string      = event.characters ?? ""
        let keyCode     = Int(event.keyCode)
        let rawFlags    = Int(bitPattern: UInt(event.modifierFlags.rawValue))
        let firstChar   = string.unicodeScalars.first?.value

        let isShiftOnly = deviceFlags.contains(.shift) &&
            !deviceFlags.contains(.control) &&
            !deviceFlags.contains(.option) &&
            !deviceFlags.contains(.command)
        if isShiftOnly, keyCode == 49 {
            // Shift+Space: toggle Roman (Latin bypass) mode
            inputContext.commitComposition(client: sender as? (any IMKTextInput))
            toggleRomanMode()
            sHandled = true
            // Ghostty processes Shift+Space before calling the IME, inserting
            // an unwanted blank space into the PTY. Send DEL to remove it.
            if let c = sender as? (any IMKTextInput),
               c.bundleIdentifier() == "com.mitchellh.ghostty" {
                c.insertText(
                    "\u{7f}",
                    replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
                )
            }
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
