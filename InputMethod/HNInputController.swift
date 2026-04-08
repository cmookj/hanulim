/*
 * Hanulim
 *
 * Original Objective-C code - https://github.com/han9kin/hanulim
 */

import Cocoa
import InputMethodKit

/// The IMK input controller. macOS instantiates one of these for every client
/// application (and may create additional instances when focus changes within
/// the same app). It receives key events from IMKit, delegates Korean composition
/// to `HNInputContext`, and manages the abbreviation candidates panel.
///
/// IMKit entry points used:
///   - `inputText(_:key:modifiers:client:)` — main key event handler
///   - `setValue(_:forTag:client:)` — notified when the input source changes
///   - `recognizedEvents(_:)` — declares which event types to receive
///   - `commitComposition(_:)` — flush pending composition on focus loss
///   - `candidateSelected(_:)` / `candidateSelectionChanged(_:)` — abbreviation UI
@objc(HNInputController)
class HNInputController: IMKInputController {

    /// Per-instance Korean composition engine. Each controller has its own state
    /// so that composition in one app window does not interfere with another.
    private let inputContext = HNInputContext()

    /// The most recent abbreviation lookup result, kept alive while the
    /// IMKCandidates panel is visible.
    private var currentCandidates: HNCandidates?

    // MARK: - Lifecycle

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        HNLog("HNInputController \(String(describing: self)) initWithServer")
        // Wire the shared preferences to this context so handleKey() can read them.
        inputContext.userDefaults = HNUserDefaults.shared
    }

    // MARK: - IMKInputController overrides

    override func annotationSelected(_ annotationString: NSAttributedString!, forCandidate candidateString: NSAttributedString!) {
        HNLog("HNInputController annotationSelected: \(annotationString.string) forCandidate: \(candidateString.string)")
    }

    /// Called as the user navigates the candidates panel; shows the annotation
    /// (description) for the currently highlighted expansion.
    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        HNLog("HNInputController candidateSelectionChanged: \(candidateString.string)")
        if let annotation = currentCandidates?.annotation(for: candidateString.string) {
            HNCandidatesController.shared?.showAnnotation(annotation)
        }
    }

    /// Called when the user confirms a candidate. Inserts the expanded string
    /// directly and clears the composition buffer.
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

    /// Returns the input method's menu (shown in the menu bar icon).
    /// Provided by `HNAppController`, which loads the menu from the nib.
    override func menu() -> NSMenu! {
        HNLog("HNInputController menu")
        return HNAppController.shared?.menu
    }
}

// MARK: - IMKStateSetting

extension HNInputController {

    /// Declares which event types this controller wants to receive.
    /// While Korean composition is in progress (composedString != nil) the
    /// controller also claims mouse-down events so it can commit the partial
    /// syllable before the cursor moves.
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

    /// Called by macOS when the active input source (keyboard layout / mode)
    /// changes. Updates the composition engine's keyboard layout so the correct
    /// key-to-jaso mapping is used.
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        HNLog("HNInputController setValue: \(String(describing: value)) forTag: \(tag)")
        if tag == kTSMDocumentInputModePropertyTag, let name = value as? String {
            inputContext.setKeyboardLayout(name: name)
        }
    }
}

// MARK: - IMKServerInput

extension HNInputController {

    /// Main key-event entry point. Returns `true` if the event was consumed by
    /// the input method (the app should not process it further), `false` if the
    /// event should be re-dispatched through the normal event chain.
    ///
    /// Dispatch order:
    ///   1. Option+Return → abbreviation candidate lookup (only when composing)
    ///   2. Everything else → `HNInputContext.handleKey()`
    override func inputText(_ string: String!, key keyCode: Int, modifiers flags: Int, client sender: Any!) -> Bool {
        HNLog("HNInputController inputText: \(String(describing: string)) key: \(keyCode) modifiers: \(flags)")

        var sHandled        = false
        var sShowCandidates = false

        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(bitPattern: flags))
        let deviceFlags   = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let firstChar     = string?.unicodeScalars.first?.value

        if deviceFlags == .option, firstChar == 0x0d {
            // Option + Return: look up the current composed string in the
            // abbreviation database and show the candidates panel.
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

    /// Called by IMKit when the client app requests that any pending composition
    /// be finalised (e.g. on focus loss or app switch). Inserts the partial
    /// syllable as-is and clears the buffer.
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

    /// Commits any in-progress composition when the user clicks in the document.
    /// Returns `false` so the click is still delivered to the app.
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
