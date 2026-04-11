import AppKit
import Carbon.HIToolbox

/// Grabs selected text from any app using CGEvent Cmd+C simulation + clipboard sentinel.
/// CGEvent approach: ~10ms keystroke vs osascript ~200ms. Safe on background threads.
/// Requires Accessibility permission.
class TextGrabber {

    /// Grab selected text synchronously. Call from DispatchQueue.global(), NOT main thread.
    func grabSelectedTextSync() -> String? {
        guard AXIsProcessTrusted() else {
            NSLog("[TextGrab] No Accessibility permission")
            return nil
        }

        let pasteboard = NSPasteboard.general

        // Save original string content (text quoting only cares about strings)
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        // Write sentinel so we can detect clipboard change
        let sentinel = "__glimpse_\(ProcessInfo.processInfo.systemUptime)"
        DispatchQueue.main.sync {
            pasteboard.clearContents()
            pasteboard.setString(sentinel, forType: .string)
        }

        // Simulate Cmd+C via CGEvent — targets the currently focused app (~10ms)
        simulateCmdC()

        // Poll for clipboard change (max ~200ms)
        var grabbed: String?
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.025)  // 25ms × 8 = 200ms max
            if pasteboard.changeCount != originalChangeCount {
                let current = pasteboard.string(forType: .string)
                if let current, current != sentinel {
                    grabbed = current
                    break
                }
            }
        }

        // Restore original clipboard
        DispatchQueue.main.sync {
            pasteboard.clearContents()
            if let original = originalString {
                pasteboard.setString(original, forType: .string)
            }
        }

        if let text = grabbed {
            NSLog("[TextGrab] Grabbed \(text.count) chars")
        } else {
            NSLog("[TextGrab] Nothing selected")
        }
        return grabbed
    }

    /// Simulate Cmd+C via CGEvent at HID level — no osascript, no subprocess (~10ms).
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
