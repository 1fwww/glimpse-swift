import WebKit

/// Bridges JS window.electronAPI calls to Swift handlers.
/// JS sends: window.webkit.messageHandlers.glimpse.postMessage({command, args, callbackId})
/// Swift responds: webView.evaluateJavaScript("window._glimpseResolve(callbackId, result)")
class IPCBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var settingsStore: SettingsStore!
    var threadStore: ThreadStore!
    var aiService: AIService!

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let command = body["command"] as? String else { return }

        let args = body["args"] as? [String: Any] ?? [:]
        let callbackId = body["callbackId"] as? Int

        // Window drag — CGEventTap tracks mouseDragged at HID level
        if command == "_start_drag" {
            DispatchQueue.main.async { [weak self] in
                if let window = self?.webView?.window {
                    ShortcutManager.shared?.startDrag(window: window)
                }
            }
            return
        }

        // Async commands (AI calls, key validation, permission prompts, folder picker)
        let asyncCommands = ["chat_with_ai", "generate_title", "save_api_keys", "validate_invite_code", "copy_image", "save_image",
                             "request_screen_permission", "request_accessibility_permission", "select_folder"]
        if asyncCommands.contains(command) {
            Task {
                let result = await self.handleAsyncCommand(command, args: args)
                DispatchQueue.main.async { [weak self] in
                    self?.resolveCallback(callbackId, result: result)
                }
            }
            return
        }

        // Sync commands
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let result = self.handleCommandSync(command, args: args)
            self.resolveCallback(callbackId, result: result)
        }
    }

    // MARK: - Async Commands

    private func handleAsyncCommand(_ command: String, args: [String: Any]) async -> Any? {
        switch command {
        case "chat_with_ai":
            guard let messages = args["messages"] as? [[String: Any]],
                  let provider = args["provider"] as? String,
                  let modelId = args["modelId"] as? String else {
                return ["success": false, "error": "Missing parameters"]
            }
            guard let apiKey = settingsStore.getKeyForProvider(provider) else {
                return ["success": false, "error": "No API key configured", "code": "auth_error"]
            }
            return await aiService.chatWithAI(messages: messages, provider: provider, modelId: modelId, apiKey: apiKey)

        case "generate_title":
            guard let messages = args["messages"] as? [[String: Any]],
                  let provider = args["provider"] as? String,
                  let modelId = args["modelId"] as? String else {
                return ["success": false]
            }
            guard let apiKey = settingsStore.getKeyForProvider(provider) else {
                return ["success": false]
            }
            return await aiService.generateTitle(messages: messages, provider: provider, modelId: modelId, apiKey: apiKey)

        case "save_api_keys":
            return await saveApiKeysAsync(args)

        case "validate_invite_code":
            guard let code = args["code"] as? String else {
                return ["valid": false, "error": "Missing code"]
            }
            return settingsStore.validateInviteCode(code)

        case "copy_image":
            guard let dataUrl = args["dataUrl"] as? String else {
                return ["success": false, "error": "Missing dataUrl"]
            }
            return await copyImageToClipboard(dataUrl)

        case "save_image":
            guard let dataUrl = args["dataUrl"] as? String else {
                return ["success": false, "error": "Missing dataUrl"]
            }
            return await saveImageToFile(dataUrl)

        case "request_screen_permission":
            // Triggers system permission prompt if not yet determined; returns current status
            let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
            return ["granted": granted]

        case "request_accessibility_permission":
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = await MainActor.run { AXIsProcessTrustedWithOptions(options) }
            // If just granted, install the event tap now
            if trusted {
                await MainActor.run { ShortcutManager.shared?.installEventTap() }
            }
            return ["granted": trusted]

        case "select_folder":
            return await MainActor.run {
                NotificationCenter.default.post(name: .lowerOverlay, object: nil)
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Select"
                let response = panel.runModal()
                NotificationCenter.default.post(name: .restoreOverlay, object: nil)
                if response == .OK, let url = panel.url {
                    return url.path as Any
                }
                return nil as Any?
            }

        default:
            return nil
        }
    }

    private func decodeDataUrl(_ dataUrl: String) -> Data? {
        // Strip "data:image/png;base64," or "data:image/jpeg;base64," prefix
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return nil }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        return Data(base64Encoded: base64)
    }

    private func copyImageToClipboard(_ dataUrl: String) async -> [String: Any] {
        guard let imageData = decodeDataUrl(dataUrl) else {
            return ["success": false, "error": "Invalid image data"]
        }
        return await MainActor.run {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(imageData, forType: .png)
            // Also set TIFF for broader compatibility
            if let image = NSImage(data: imageData), let tiff = image.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
            NSLog("[IPC] Image copied to clipboard (\(imageData.count / 1024)KB)")
            return ["success": true]
        }
    }

    private func saveImageToFile(_ dataUrl: String) async -> [String: Any] {
        guard let imageData = decodeDataUrl(dataUrl) else {
            return ["success": false, "error": "Invalid image data"]
        }

        return await MainActor.run {
            // Lower overlay so save panel appears on top
            NotificationCenter.default.post(name: .lowerOverlay, object: nil)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "glimpse-\(Self.timestampString()).png"
            panel.canCreateDirectories = true

            // Set default save location from preferences
            if let savePath = self.settingsStore?.getPreferences()["savePath"] as? String, !savePath.isEmpty {
                panel.directoryURL = URL(fileURLWithPath: savePath)
            }

            let response = panel.runModal()

            // Restore overlay
            NotificationCenter.default.post(name: .restoreOverlay, object: nil)
            NotificationCenter.default.post(name: .inputFocus, object: nil)

            if response == .OK, let url = panel.url {
                do {
                    try imageData.write(to: url)
                    NSLog("[IPC] Image saved to \(url.path)")
                    return ["success": true, "filePath": url.path]
                } catch {
                    NSLog("[IPC] Save failed: \(error)")
                    return ["success": false, "error": error.localizedDescription]
                }
            }
            return ["success": false, "error": "Cancelled"]
        }
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private func saveApiKeysAsync(_ args: [String: Any]) async -> [String: Any] {
        guard let keys = args["keys"] as? [String: String] else {
            return ["success": false, "error": "Invalid keys format"]
        }

        // Validate each key before saving
        var errors: [String] = []
        for (keyName, keyValue) in keys {
            guard !keyValue.isEmpty else { continue }
            let provider: String
            switch keyName {
            case "ANTHROPIC_API_KEY": provider = "anthropic"
            case "OPENAI_API_KEY":    provider = "openai"
            case "GEMINI_API_KEY":    provider = "gemini"
            default: continue
            }
            let valid = await aiService.validateApiKey(provider: provider, key: keyValue)
            if !valid {
                errors.append("\(provider) key is invalid")
            }
        }

        if !errors.isEmpty {
            return ["success": false, "error": errors.joined(separator: "; ")]
        }

        settingsStore.saveKeys(keys)
        return ["success": true]
    }

    // MARK: - Sync Commands

    func handleCommandSync(_ command: String, args: [String: Any]) -> Any? {
        switch command {
        // ── Thread management ──
        case "get_threads":
            return threadStore.getThreads()

        case "save_thread":
            if let thread = args["thread"] as? [String: Any] {
                return threadStore.saveThread(thread)
            }
            return ["success": false, "error": "Missing thread data"]

        case "delete_thread":
            if let id = args["id"] as? String {
                return threadStore.deleteThread(id: id)
            }
            return ["success": false]

        // ── API keys ──
        case "get_api_keys":
            return settingsStore.getApiKeysInfo()

        case "delete_api_key":
            if let provider = args["provider"] as? String {
                settingsStore.deleteKey(provider: provider)
            }
            return ["success": true]

        case "get_available_providers":
            return settingsStore.getAvailableProviders()

        // ── Preferences ──
        case "get_preferences":
            return settingsStore.getPreferences()

        case "set_preference":
            if let key = args["key"] as? String {
                let value = args["value"] ?? false
                settingsStore.setPreference(key: key, value: value)
            }
            return true

        // ── Window management ──
        case "close_chat_window":
            NotificationCenter.default.post(name: .closeChatWindow, object: nil)
            return true

        case "chat_ready":
            NotificationCenter.default.post(name: .chatReady, object: nil)
            return true

        case "overlay_ready":
            NotificationCenter.default.post(name: .overlayReady, object: nil)
            return true

        case "close_overlay":
            NotificationCenter.default.post(name: .closeOverlay, object: nil)
            return true

        case "toggle_pin":
            NotificationCenter.default.post(name: .togglePin, object: nil)
            return true

        case "pin_chat":
            let threadData = args["threadData"] as? [String: Any]
            let bounds = args["bounds"] as? [String: Any]
            NotificationCenter.default.post(name: .pinChat, object: nil, userInfo: [
                "threadData": threadData as Any,
                "bounds": bounds as Any
            ])
            return true

        case "resize_chat_window":
            if let size = args["size"] as? [String: Any] {
                NotificationCenter.default.post(name: .resizeChatWindow, object: nil, userInfo: size)
            }
            return true

        // ── Permissions ──
        case "check_permissions":
            let screen = CGPreflightScreenCaptureAccess()
            let accessibility = AXIsProcessTrusted()
            // Install event tap if accessibility was granted externally (user toggled in System Settings)
            if accessibility { ShortcutManager.shared?.installEventTap() }
            return ["screen": screen, "accessibility": accessibility]

        // ── Utilities ──
        case "open_external":
            if let url = args["url"] as? String, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
            return true

        case "lower_overlay":
            NotificationCenter.default.post(name: .lowerOverlay, object: nil)
            return true

        case "restore_overlay":
            NotificationCenter.default.post(name: .restoreOverlay, object: nil)
            return true

        case "input_focus":
            NotificationCenter.default.post(name: .inputFocus, object: nil)
            return true

        case "show_toast":
            if let message = args["message"] as? String {
                ToastManager.shared.show(message)
            }
            return true

        case "notify_providers_changed":
            NotificationCenter.default.post(name: .providersChanged, object: nil)
            return true

        // ── Welcome / Settings windows ──
        case "close_welcome":
            NotificationCenter.default.post(name: .closeWelcome, object: nil)
            return true

        case "welcome_done":
            NotificationCenter.default.post(name: .welcomeDone, object: nil)
            return true

        case "toggle_settings":
            let panelBounds = args["panelBounds"] as? [String: Any]
            NotificationCenter.default.post(name: .toggleSettings, object: nil,
                userInfo: panelBounds.map { ["panelBounds": $0] })
            return true

        case "close_settings":
            NotificationCenter.default.post(name: .closeSettings, object: nil)
            return true

        case "open_permission_settings":
            let permType = args["type"] as? String ?? "screen"
            let urlString: String
            if permType == "accessibility" {
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            }
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            return true

        case "refresh_tray_menu":
            NotificationCenter.default.post(name: .refreshTrayMenu, object: nil)
            return true

        case "open_thread_in_chat":
            if let threadId = args["threadId"] as? String {
                NotificationCenter.default.post(name: .openThreadInChat, object: nil, userInfo: ["threadId": threadId])
            }
            return true

        default:
            NSLog("[IPC] unhandled command: \(command)")
            return nil
        }
    }

    // MARK: - Callback Resolution

    private func resolveCallback(_ callbackId: Int?, result: Any?) {
        guard let cbId = callbackId, let wv = webView else { return }
        let json = jsonString(result)
        wv.evaluateJavaScript("window._glimpseResolve(\(cbId), \(json))") { _, error in
            if let error { NSLog("[IPC] callback error: \(error)") }
        }
    }

    /// Emit event from Swift to JS (backend → frontend)
    func emit(_ event: String, data: Any? = nil) {
        guard let wv = webView else { return }
        let json = data != nil ? jsonString(data) : "null"
        let js = "window.dispatchEvent(new CustomEvent('glimpse:\(event)', {detail: \(json)}))"
        DispatchQueue.main.async {
            wv.evaluateJavaScript(js) { _, error in
                if let error { NSLog("[IPC] emit error: \(error)") }
            }
        }
    }

    func jsonString(_ value: Any?) -> String {
        guard let value else { return "null" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let n = value as? Int { return "\(n)" }
        if let n = value as? Double { return "\(n)" }
        if let s = value as? String {
            if let data = try? JSONSerialization.data(withJSONObject: [s]),
               let str = String(data: data, encoding: .utf8) {
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
    static let resizeChatWindow = Notification.Name("resizeChatWindow")
    static let togglePin = Notification.Name("togglePin")
    static let closeOverlay = Notification.Name("closeOverlay")
    static let overlayReady = Notification.Name("overlayReady")
    static let pinChat = Notification.Name("pinChat")
    static let lowerOverlay = Notification.Name("lowerOverlay")
    static let restoreOverlay = Notification.Name("restoreOverlay")
    static let inputFocus = Notification.Name("inputFocus")
    static let refreshTrayMenu = Notification.Name("refreshTrayMenu")
    static let openThreadInChat = Notification.Name("openThreadInChat")
    static let closeWelcome = Notification.Name("closeWelcome")
    static let welcomeDone = Notification.Name("welcomeDone")
    static let toggleSettings = Notification.Name("toggleSettings")
    static let closeSettings = Notification.Name("closeSettings")
    static let providersChanged = Notification.Name("providersChanged")
}
