import AppKit
import Carbon.HIToolbox

/// Grabs selected text from any app via Accessibility API (preferred) or
/// CGEvent Cmd+C simulation (fallback).
///
/// Strategy: AX API first (instant, no beep, no clipboard side effects).
/// Falls back to Cmd+C only when AX can't reach the app (e.g., Chrome fullscreen).
///
/// AXResult distinguishes three outcomes:
/// - `.success(text)`: AX reached the focused element and read selectedText
/// - `.noSelection`: AX reached the element but it has no selectedText attribute
///   (user hasn't selected anything) — do NOT fall back to Cmd+C (would beep)
/// - `.appFailed`: AX couldn't get the focused element at all (app-level failure,
///   e.g., Chrome returns -25212) — fall back to Cmd+C
///
/// Requires Accessibility permission.
class TextGrabber {

    enum AXResult {
        case success(String)
        case noSelection
        case appFailed
    }

    // MARK: - Public API

    /// Try AX API on main thread (instant). If AX fails at app level,
    /// caller should fall back to grabViaCmdC() on a background thread.
    func grabViaAccessibility() -> AXResult {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[TextGrab] No frontmost app")
            return .appFailed
        }
        NSLog("[TextGrab] frontmost = \(frontApp.localizedName ?? "?") (pid \(frontApp.processIdentifier))")

        let appRef = AXUIElementCreateApplication(frontApp.processIdentifier)

        let t0 = CACurrentMediaTime()
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        let axMs = (CACurrentMediaTime() - t0) * 1000
        guard focusResult == .success, let element = focusedElement else {
            NSLog("[TextGrab] focusedElement failed (\(focusResult.rawValue)) [%.1fms]", axMs)
            return .appFailed
        }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard textResult == .success, let text = selectedText as? String else {
            NSLog("[TextGrab] selectedText failed (\(textResult.rawValue))")
            return .noSelection
        }

        NSLog("[TextGrab] AX success, text length=\(text.count)")
        return .success(text)
    }

    /// Cmd+C simulation fallback. Must be called from a background thread.
    /// All clipboard ops run on the background thread (NSPasteboard is thread-safe
    /// for these operations) to avoid blocking the main thread's run loop, which
    /// would cause Core Animation frame drops on the subsequent fade-in.
    func grabViaCmdC() -> String? {
        let t0 = CACurrentMediaTime()
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        // Write sentinel to detect clipboard change
        let sentinel = "__glimpse_\(ProcessInfo.processInfo.systemUptime)"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)

        simulateCmdC()

        // Poll for clipboard change (max ~200ms)
        var grabbed: String?
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.025)
            if pasteboard.changeCount != originalChangeCount {
                let current = pasteboard.string(forType: .string)
                if let current, current != sentinel {
                    grabbed = current
                    break
                }
            }
        }

        // Restore original clipboard
        pasteboard.clearContents()
        if let original = originalString {
            pasteboard.setString(original, forType: .string)
        }

        let cmdCMs = (CACurrentMediaTime() - t0) * 1000
        if let text = grabbed {
            NSLog("[TextGrab] Cmd+C grabbed \(text.count) chars [%.1fms]", cmdCMs)
        } else {
            NSLog("[TextGrab] Cmd+C: nothing selected [%.1fms]", cmdCMs)
        }
        return grabbed
    }

    // MARK: - Private

    private func simulateCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
