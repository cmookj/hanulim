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
        if inputContext.isRomanMode {
            // Restore the previous Korean layout immediately.
            let koreanID = inputContext.lastKoreanModeID
            inputContext.setKeyboardLayout(name: koreanID)
            // Best-effort icon update via TIS (Korean is already enabled).
            selectInputSource(id: koreanID, enableIfNeeded: false)
        } else {
            // Enter Roman bypass immediately.
            inputContext.setKeyboardLayout(name: kRomanModeID)
            // Best-effort icon update via TIS.
            // TISEnableInputSource shows a one-time system security dialog;
            // we do NOT call TISSelectInputSource until the source is enabled,
            // because TISEnableInputSource is asynchronous on modern macOS.
            selectInputSource(id: kRomanModeID, enableIfNeeded: true)
        }
    }

    private func selectInputSource(id: String, enableIfNeeded: Bool) {
        let cfID = id as CFString
        let filterDict = [kTISPropertyInputSourceID: cfID] as CFDictionary
        guard let list = TISCreateInputSourceList(filterDict, true)?.takeRetainedValue(),
              CFArrayGetCount(list) > 0,
              let rawPtr = CFArrayGetValueAtIndex(list, 0) else {
            HNLog("selectInputSource: not found: \(id)")
            return
        }
        // Retain the source across the async dispatch.
        let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).retain().takeRetainedValue()

        // Dispatch after the current IMK event handler returns.
        // TISSelectInputSource called synchronously inside inputText may be
        // ignored by the system; running it asynchronously avoids that.
        DispatchQueue.main.async {
            if enableIfNeeded {
                // No-op if already enabled; shows one-time security dialog otherwise.
                TISEnableInputSource(source)
            }
            let err = TISSelectInputSource(source)
            HNLog("selectInputSource: \(id) → OSStatus \(err)")
        }
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

    override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        HNLog("HNInputController inputText: \(String(describing: string)) key: \(keyCode) modifiers: \(flags)")

        var sHandled        = false
        var sShowCandidates = false

        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: flags))
        let deviceFlags   = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let firstChar     = string?.unicodeScalars.first?.value

        let isShiftOnly = deviceFlags.contains(.shift) &&
            !deviceFlags.contains(.control) &&
            !deviceFlags.contains(.option) &&
            !deviceFlags.contains(.command)
        if isShiftOnly, keyCode == 49 {
            // Shift+Space: toggle Roman (Latin bypass) mode
            inputContext.commitComposition(client: sender as? (any IMKTextInput))
            toggleRomanMode()
            sHandled = true
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
                string: string ?? "",
                keyCode: keyCode,
                modifiers: flags,
                client: textClient
            )
            currentCandidates = nil
        }

        if sShowCandidates {
            HNCandidatesController.shared?.show()
        } else {
            HNCandidatesController.shared?.hide()
        }

        HNLog("HNInputController inputText => \(sHandled ? "YES" : "NO")")
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
