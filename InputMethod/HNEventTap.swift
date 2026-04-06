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

/// System-level CGEventTap that intercepts key events before any application
/// sees them. Responsibilities:
///
/// - Shift+Space: toggles Roman/Korean mode. The event is *consumed* when a
///   consuming tap is active (Accessibility granted) so that apps like Ghostty
///   which process raw keys before calling the IME cannot pre-insert a space.
///
/// - ESC (when switchesToRomanOnEsc preference is on): switches to Roman mode
///   without consuming the event, so vi/vim still receives ESC normally.
///
/// Requires Accessibility permission for the consuming tap
/// (System Settings → Privacy & Security → Accessibility).
final class HNEventTap: @unchecked Sendable {

    static let shared = HNEventTap()

    private static let romanModeID       = "org.cocomelo.inputmethod.Hanulim.Roman"
    private static let defaultKoreanModeID = "org.cocomelo.inputmethod.Hanulim.2standard"

    /// Updated by HNInputController.setValue(_:forTag:client:) each time the
    /// system switches to a Korean input source, so we know where to return.
    var lastKoreanModeID: String = HNEventTap.defaultKoreanModeID

    /// True only when a consuming (non-listen-only) tap is installed.
    /// When false the handle(_:client:) fallback in HNInputController is active.
    private(set) var isConsuming = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Lifecycle

    /// Install the event tap. Call once from main.swift before the run loop
    /// starts. If the consuming tap cannot be created (Accessibility not yet
    /// granted), prompts for permission — the tap activates on the next launch.
    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The callback must be a C-compatible function pointer (no captures).
        // Access the singleton directly via HNEventTap.shared.
        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            guard type == .keyDown else { return Unmanaged.passRetained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags   = event.flags

            // ── Shift+Space (keyCode 49) ──────────────────────────────────
            let shiftOnly = flags.contains(.maskShift)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand)

            if shiftOnly && keyCode == 49 {
                if HNEventTap.shared.isConsuming {
                    HNLog("HNEventTap: Shift+Space consumed by tap")
                    DispatchQueue.main.async { HNEventTap.shared.toggleRomanMode() }
                    return nil                          // consume — app never sees it
                } else {
                    HNLog("HNEventTap: Shift+Space seen (listen-only, passing through)")
                    return Unmanaged.passRetained(event)
                }
            }

            // ── ESC (keyCode 53, no modifiers) ────────────────────────────
            // Always pass through; only trigger a mode switch as a side effect.
            let noModifiers = !flags.contains(.maskShift)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand)

            if keyCode == 53 && noModifiers
                && HNUserDefaults.shared.switchesToRomanOnEsc {
                DispatchQueue.main.async {
                    if HNEventTap.shared.isCurrentlyKoreanHanulimMode() {
                        HNLog("HNEventTap: ESC → switching to Roman mode")
                        HNEventTap.shared.selectInputSource(id: HNEventTap.romanModeID)
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

    func toggleRomanMode() {
        let targetID = isCurrentlyRomanMode() ? lastKoreanModeID : HNEventTap.romanModeID
        selectInputSource(id: targetID)
    }

    // MARK: - Helpers

    private func isCurrentlyRomanMode() -> Bool {
        currentInputSourceID() == HNEventTap.romanModeID
    }

    /// True when a Hanulim Korean mode (not Roman) is the active input source.
    func isCurrentlyKoreanHanulimMode() -> Bool {
        let id = currentInputSourceID()
        return id.hasPrefix("org.cocomelo.inputmethod.Hanulim.")
            && id != HNEventTap.romanModeID
    }

    private func currentInputSourceID() -> String {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else {
            return ""
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    func selectInputSource(id: String) {
        let filterDict = [kTISPropertyInputSourceID: id as CFString] as CFDictionary
        guard let list = TISCreateInputSourceList(filterDict, true)?.takeRetainedValue(),
              CFArrayGetCount(list) > 0,
              let rawPtr = CFArrayGetValueAtIndex(list, 0) else {
            HNLog("HNEventTap: selectInputSource not found: \(id)")
            return
        }
        let source = Unmanaged<TISInputSource>.fromOpaque(rawPtr).takeUnretainedValue()
        let err = TISSelectInputSource(source)
        HNLog("HNEventTap: selectInputSource \(id) → OSStatus \(err)")
    }
}
