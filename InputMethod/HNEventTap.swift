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

// MARK: - HNEventTap

/// System-level CGEventTap that intercepts ESC key events before any
/// application sees them.
///
/// When `switchesToRomanOnEsc` is on and a Hanulim Korean mode is active,
/// pressing ESC commits any in-progress syllable and switches the system
/// to its current ASCII-capable keyboard layout (e.g. ABC).
///
/// **Why TISSelectInputSource is safe here**
///
/// The session-destruction bug that prevents using `TISSelectInputSource` for
/// internal Hanulim mode switches does *not* apply here.  Switching FROM a
/// Hanulim mode TO a completely different input source (ABC) is a normal full
/// source switch: the Hanulim IMK session is intentionally terminated, and ABC
/// requires no IMK controller initialisation.  The next time the user returns
/// to Hanulim the system creates a fresh IMK session correctly.
///
/// **ESC handling strategy**
///
/// | State | Action |
/// |---|---|
/// | Composing | Consume original ESC; commit composition; switch to ASCII; post synthetic ESC so terminal emulators forward it to the PTY |
/// | Not composing | Pass original ESC through; switch to ASCII asynchronously |
///
/// Requires Accessibility permission for the consuming tap
/// (System Settings → Privacy & Security → Accessibility).
final class HNEventTap: @unchecked Sendable {

    static let shared = HNEventTap()

    private static let bundleID = "org.cocomelo.inputmethod.Hanulim"

    /// True only when a consuming (non-listen-only) tap is installed.
    /// When false the `handle(_:client:)` fallback in `HNInputController` is
    /// the only active interception mechanism.
    private(set) var isConsuming = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Lifecycle

    /// Install the event tap.  Call once from main.swift before the run loop
    /// starts.  If the consuming tap cannot be created (Accessibility not yet
    /// granted), prompts for permission — the tap activates on the next launch.
    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The callback must be a C-compatible function pointer (no captures).
        // Access the singleton directly via HNEventTap.shared.
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags   = event.flags

            // ── ESC (keyCode 53, no modifiers) ────────────────────────────
            let noModifiers = !flags.contains(.maskShift)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand)

            if keyCode == 53 && noModifiers
                && HNUserDefaults.shared.switchesToRomanOnEsc
                && HNEventTap.shared.isCurrentlyHanulimMode() {

                if HNInputContext.isComposing {
                    // A syllable is being composed.  Terminal emulators decide
                    // at event-arrival time whether to forward ESC to the PTY
                    // or treat it as "dismiss preedit".  When preedit text is
                    // active they always choose the latter — even if the IME's
                    // handle() later returns false.  The only reliable fix is:
                    //   1. Consume the original ESC here (before any app sees it).
                    //   2. Commit the composition on the main thread.
                    //   3. Switch to the ASCII layout.
                    //   4. Post a synthetic ESC — it arrives with no preedit, so
                    //      the terminal forwards it to the PTY normally.
                    HNLog("HNEventTap: ESC during composition — consuming and will synthesize")
                    DispatchQueue.main.async {
                        HNInputController.active?.commitForEsc()
                        HNEventTap.shared.switchToASCII()
                        let src = CGEventSource(stateID: .hidSystemState)
                        let dn  = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true)
                        let up  = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false)
                        dn?.post(tap: .cgAnnotatedSessionEventTap)
                        up?.post(tap: .cgAnnotatedSessionEventTap)
                        HNLog("HNEventTap: posted synthetic ESC after composition commit")
                    }
                    return nil  // consume original; synthetic follows on next run loop
                } else {
                    // No composition in progress: pass the original ESC through
                    // so the app receives it immediately, and switch mode
                    // asynchronously as a side effect.
                    HNLog("HNEventTap: ESC (no composition) — passing through, switching to ASCII")
                    DispatchQueue.main.async {
                        if HNEventTap.shared.isCurrentlyHanulimMode() {
                            HNEventTap.shared.switchToASCII()
                        }
                    }
                }
            }

            return Unmanaged.passRetained(event)
        }

        // Attempt to create a consuming tap (requires Accessibility).
        if let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) {
            installTap(port, consuming: true)
            return
        }

        // Consuming tap failed — request Accessibility if not granted.
        let axTrusted = AXIsProcessTrusted()
        HNLog("HNEventTap: consuming tap failed (AXTrusted=\(axTrusted))")
        if !axTrusted {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            HNLog("HNEventTap: opened Accessibility pane — add Hanulim and restart")
        }

        // Listen-only taps require Input Monitoring — request if missing.
        let listenOK = CGPreflightListenEventAccess()
        HNLog("HNEventTap: CGPreflightListenEventAccess=\(listenOK)")
        if !listenOK {
            CGRequestListenEventAccess()
            HNLog("HNEventTap: opened Input Monitoring pane — add Hanulim and restart")
        }

        if let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) {
            installTap(port, consuming: false)
            HNLog("HNEventTap: listen-only tap installed")
        } else {
            HNLog("HNEventTap: listen-only tap failed — grant Input Monitoring and restart")
        }
    }

    private func installTap(_ port: CFMachPort, consuming: Bool) {
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isConsuming = consuming
        HNLog("HNEventTap: tap installed (consuming=\(consuming))")
    }

    // MARK: - Mode switching

    /// Switch to the system's current ASCII-capable keyboard layout.
    ///
    /// Uses `TISCopyCurrentASCIICapableKeyboardLayoutInputSource()` to find the
    /// target dynamically — no hardcoded layout ID (works with ABC, US, Dvorak,
    /// etc.).  `TISSelectInputSource` is safe here because this is a full input
    /// source switch away from Hanulim, not an internal component mode switch.
    func switchToASCII() {
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                            .takeRetainedValue() else {
            HNLog("HNEventTap: switchToASCII — no ASCII-capable layout found")
            return
        }
        let status = TISSelectInputSource(src)
        HNLog("HNEventTap: switchToASCII → TISSelectInputSource status=\(status)")
    }

    // MARK: - Helpers

    /// Returns true when the currently active input source is any Hanulim mode.
    ///
    /// Reads TIS (read-only — safe) to get the ground-truth active source.
    /// Called from the event tap callback (background thread); TIS reads are
    /// thread-safe.
    func isCurrentlyHanulimMode() -> Bool {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID)
        else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.hasPrefix(HNEventTap.bundleID + ".")
    }
}
