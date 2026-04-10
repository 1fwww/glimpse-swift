import WebKit

/// Bridges JS window.electronAPI calls to Swift handlers.
/// JS sends: window.webkit.messageHandlers.glimpse.postMessage({command, args, callbackId})
/// Swift responds: webView.evaluateJavaScript("window._glimpseResolve(callbackId, result)")
class IPCBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }

        let args = body["args"] as? [String: Any] ?? [:]
        let callbackId = body["callbackId"] as? Int

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = self.handleCommandSync(command, args: args)
            if let cbId = callbackId, let wv = self.webView {
                let json = self.jsonString(result)
                wv.evaluateJavaScript("window._glimpseResolve(\(cbId), \(json))") { _, error in
                    if let error { print("[IPC] callback error: \(error)") }
                }
            }
        }
    }

    func handleCommandSync(_ command: String, args: [String: Any]) -> Any? {
        switch command {
        // ── Thread management ──
        case "get_threads":
            return [] // TODO: Phase 1
        case "save_thread":
            return ["success": true] // TODO
        case "delete_thread":
            return ["success": true] // TODO

        // ── AI ──
        case "chat_with_ai":
            return ["success": false, "error": "Not implemented yet"] // TODO: Phase 1
        case "generate_title":
            return ["success": false] // TODO

        // ── API keys ──
        case "get_api_keys":
            return ["hasAnyKey": false, "isInvite": false]
        case "save_api_keys":
            return ["success": true] // TODO
        case "delete_api_key":
            return ["success": true] // TODO
        case "get_available_providers":
            return [] // TODO
        case "validate_invite_code":
            return ["valid": false] // TODO

        // ── Preferences ──
        case "get_preferences":
            return ["launchAtLogin": false, "saveLocation": "ask", "savePath": ""]
        case "set_preference":
            return true // TODO

        // ── Window management ──
        case "close_chat_window":
            NotificationCenter.default.post(name: .closeChatWindow, object: nil)
            return true
        case "chat_ready":
            NotificationCenter.default.post(name: .chatReady, object: nil)
            return true
        case "resize_chat_window":
            // TODO: Phase 1
            return true

        // ── Permissions ──
        case "check_permissions":
            let screen = CGPreflightScreenCaptureAccess()
            let accessibility = AXIsProcessTrusted()
            return ["screen": screen, "accessibility": accessibility]

        // ── Utilities ──
        case "open_external":
            if let url = args["url"] as? String, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
            return true
        case "show_toast":
            return true // TODO
        case "notify_providers_changed":
            return true // TODO
        case "refresh_tray_menu":
            return true // TODO

        default:
            print("[IPC] unhandled command: \(command)")
            return nil
        }
    }

    /// Emit event from Swift to JS (backend → frontend)
    func emit(_ event: String, data: Any? = nil) {
        guard let wv = webView else { return }
        let json = data != nil ? jsonString(data) : "null"
        let js = "window.dispatchEvent(new CustomEvent('glimpse:\(event)', {detail: \(json)}))"
        DispatchQueue.main.async {
            wv.evaluateJavaScript(js) { _, error in
                if let error { print("[IPC] emit error: \(error)") }
            }
        }
    }

    private func jsonString(_ value: Any?) -> String {
        guard let value else { return "null" }
        // Handle primitives that JSONSerialization doesn't accept as top-level
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? Int { return "\(n)" }
        if let n = value as? Double { return "\(n)" }
        if let s = value as? String {
            if let data = try? JSONSerialization.data(withJSONObject: [s]),
               let str = String(data: data, encoding: .utf8) {
                // Strip array brackets: ["hello"] -> "hello"
                return String(str.dropFirst().dropLast())
            }
            return "\"\(s)\""
        }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "null"
    }
}

// Notification names
extension Notification.Name {
    static let closeChatWindow = Notification.Name("closeChatWindow")
    static let chatReady = Notification.Name("chatReady")
}
