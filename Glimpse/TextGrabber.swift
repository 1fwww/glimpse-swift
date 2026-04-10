import AppKit

/// Grabs selected text from any app using Cmd+C simulation + clipboard sentinel.
/// Requires Accessibility permission for keystroke simulation.
class TextGrabber {

    /// Synchronous version — call from DispatchQueue.global(), NOT main thread.
    func grabSelectedTextSync() -> String? {
        guard AXIsProcessTrusted() else {
            NSLog("[TextGrab] No Accessibility permission — skipping")
            return nil
        }

        let originalClipboard = getClipboard()
        let sentinel = "__glimpse_sentinel_\(ProcessInfo.processInfo.systemUptime)"
        setClipboard(sentinel)
        Thread.sleep(forTimeInterval: 0.02) // 20ms

        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments = ["-e", "tell application \"System Events\" to keystroke \"c\" using command down"]
        do { try proc.run() } catch {
            NSLog("[TextGrab] osascript failed: \(error)")
            restoreClipboard(originalClipboard)
            return nil
        }
        // Wait max 200ms for osascript
        let osDeadline = Date().addingTimeInterval(0.2)
        while proc.isRunning && Date() < osDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if proc.isRunning { proc.terminate() }

        // Poll clipboard for change
        var selectedText: String?
        for _ in 0..<8 {
            Thread.sleep(forTimeInterval: 0.025)
            if let current = getClipboard(), current != sentinel {
                selectedText = current
                break
            }
        }

        restoreClipboard(originalClipboard)
        return selectedText
    }

    /// Async version.
    func grabSelectedText() async -> String? {
        // Check Accessibility permission first
        guard AXIsProcessTrusted() else {
            NSLog("[TextGrab] No Accessibility permission — skipping")
            return nil
        }

        // Save current clipboard
        let originalClipboard = getClipboard()

        // Write sentinel to clipboard
        let sentinel = "__glimpse_sentinel_\(ProcessInfo.processInfo.systemUptime)"
        setClipboard(sentinel)

        // Wait for clipboard to settle
        try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Simulate Cmd+C via osascript (with timeout)
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments = ["-e", "tell application \"System Events\" to keystroke \"c\" using command down"]

        do {
            try proc.run()
        } catch {
            NSLog("[TextGrab] osascript failed to launch: \(error)")
            restoreClipboard(originalClipboard)
            return nil
        }

        // Wait for osascript with timeout (200ms max)
        let deadline = Date().addingTimeInterval(0.2)
        while proc.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        if proc.isRunning {
            proc.terminate()
            NSLog("[TextGrab] osascript timed out — terminated")
            restoreClipboard(originalClipboard)
            return nil
        }

        // Poll clipboard for change (8 attempts × 25ms = 200ms max)
        var selectedText: String?
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 25_000_000) // 25ms
            let current = getClipboard()
            if let current, current != sentinel {
                selectedText = current
                break
            }
        }

        // Restore original clipboard
        restoreClipboard(originalClipboard)

        return selectedText
    }

    private func getClipboard() -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.launchPath = "/usr/bin/pbpaste"
        proc.arguments = ["-Prefer", "txt"]
        proc.standardOutput = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func restoreClipboard(_ original: String?) {
        if let original {
            setClipboard(original)
        }
    }
}
