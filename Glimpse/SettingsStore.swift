import Foundation
import AppKit

/// Manages API keys and user preferences.
/// Files stored in ~/Library/Application Support/glimpse/
class SettingsStore {
    let appSupportDir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = base.appendingPathComponent("glimpse")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
    }

    // MARK: - API Keys

    private var keysURL: URL { appSupportDir.appendingPathComponent("api-keys.json") }

    func loadKeys() -> [String: String] {
        guard let data = try? Data(contentsOf: keysURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    func saveKeys(_ keys: [String: String]) {
        var existing = loadKeys()
        for (k, v) in keys { existing[k] = v }
        if let data = try? JSONSerialization.data(withJSONObject: existing, options: .prettyPrinted) {
            try? data.write(to: keysURL)
        }
    }

    func deleteKey(provider: String) {
        var keys = loadKeys()
        if provider == "invite" {
            keys.removeValue(forKey: "_invite")
            keys.removeValue(forKey: "ANTHROPIC_API_KEY")
            keys.removeValue(forKey: "OPENAI_API_KEY")
            keys.removeValue(forKey: "GEMINI_API_KEY")
        } else {
            let keyName: String
            switch provider {
            case "anthropic": keyName = "ANTHROPIC_API_KEY"
            case "openai":    keyName = "OPENAI_API_KEY"
            case "gemini":    keyName = "GEMINI_API_KEY"
            default: return
            }
            keys.removeValue(forKey: keyName)
        }
        if let data = try? JSONSerialization.data(withJSONObject: keys, options: .prettyPrinted) {
            try? data.write(to: keysURL)
        }
    }

    /// Returns masked key info for the frontend
    func getApiKeysInfo() -> [String: Any] {
        let keys = loadKeys()
        let isInvite = keys["_invite"] == "true"

        func masked(_ key: String?) -> String? {
            guard let k = key, !k.isEmpty else { return nil }
            let last4 = String(k.suffix(4))
            return "••••\(last4)"
        }

        let anthropic = masked(keys["ANTHROPIC_API_KEY"])
        let openai = masked(keys["OPENAI_API_KEY"])
        let gemini = masked(keys["GEMINI_API_KEY"])

        // Key names match SettingsApp.jsx's keyField values
        let result: [String: Any] = [
            "hasAnyKey": (anthropic != nil || openai != nil || gemini != nil),
            "isInvite": isInvite,
            "ANTHROPIC_API_KEY": anthropic as Any,
            "OPENAI_API_KEY": openai as Any,
            "GEMINI_API_KEY": gemini as Any
        ]
        return result
    }

    /// Returns available providers based on which keys are configured
    func getAvailableProviders() -> [[String: Any]] {
        let keys = loadKeys()
        var providers: [[String: Any]] = []

        if let k = keys["ANTHROPIC_API_KEY"], !k.isEmpty {
            providers.append([
                "id": "anthropic",
                "name": "Anthropic",
                "models": [
                    ["id": "claude-haiku-4-5-20251001", "name": "Claude Haiku 4.5"],
                    ["id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4"]
                ]
            ])
        }
        if let k = keys["OPENAI_API_KEY"], !k.isEmpty {
            providers.append([
                "id": "openai",
                "name": "OpenAI",
                "models": [
                    ["id": "gpt-4o-mini", "name": "GPT-4o Mini"],
                    ["id": "gpt-4o", "name": "GPT-4o"]
                ]
            ])
        }
        if let k = keys["GEMINI_API_KEY"], !k.isEmpty {
            providers.append([
                "id": "gemini",
                "name": "Google Gemini",
                "models": [
                    ["id": "gemini-2.5-flash", "name": "Gemini 2.5 Flash"],
                    ["id": "gemini-2.5-pro", "name": "Gemini 2.5 Pro"]
                ]
            ])
        }
        return providers
    }

    /// Validate invite code and populate keys.
    /// Keys are sourced from: (1) EmbeddedKeys (baked in by build.sh), (2) env vars (dev fallback).
    func validateInviteCode(_ code: String) -> [String: Any] {
        guard code == "KPIMG" else {
            return ["valid": false, "error": "Invalid invite code"]
        }

        // Prefer embedded keys (baked into binary by build.sh), fall back to env vars (dev mode)
        let env = ProcessInfo.processInfo.environment
        let anthropic = !EmbeddedKeys.anthropic.isEmpty ? EmbeddedKeys.anthropic : (env["GLIMPSE_ANTHROPIC_KEY"] ?? "")
        let openai    = !EmbeddedKeys.openai.isEmpty    ? EmbeddedKeys.openai    : (env["GLIMPSE_OPENAI_KEY"] ?? "")
        let gemini    = !EmbeddedKeys.gemini.isEmpty     ? EmbeddedKeys.gemini    : (env["GLIMPSE_GEMINI_KEY"] ?? "")

        guard !anthropic.isEmpty || !openai.isEmpty || !gemini.isEmpty else {
            return ["valid": false, "error": "No API keys configured for invite"]
        }

        var keys: [String: String] = ["_invite": "true"]
        if !anthropic.isEmpty { keys["ANTHROPIC_API_KEY"] = anthropic }
        if !openai.isEmpty { keys["OPENAI_API_KEY"] = openai }
        if !gemini.isEmpty { keys["GEMINI_API_KEY"] = gemini }
        saveKeys(keys)

        return ["valid": true]
    }

    func getKeyForProvider(_ provider: String) -> String? {
        let keys = loadKeys()
        switch provider {
        case "anthropic": return keys["ANTHROPIC_API_KEY"]
        case "openai":    return keys["OPENAI_API_KEY"]
        case "gemini":    return keys["GEMINI_API_KEY"]
        default: return nil
        }
    }

    // MARK: - Shortcuts

    /// Shortcut definitions: id → (keyCode for CGEventTap, display label, key equivalent for NSMenuItem)
    static let shortcutOptions: [(id: String, keyCode: Int, modifiers: String, label: String, keyEquiv: String, modMask: NSEvent.ModifierFlags)] = [
        ("cmd+shift+x", 7,  "cmd+shift", "Cmd+Shift+X", "x", [.command, .shift]),
        ("cmd+shift+z", 6,  "cmd+shift", "Cmd+Shift+Z", "z", [.command, .shift]),
        ("cmd+shift+a", 0,  "cmd+shift", "Cmd+Shift+A", "a", [.command, .shift]),
        ("cmd+shift+c", 8,  "cmd+shift", "Cmd+Shift+C", "c", [.command, .shift]),
        ("cmd+shift+g", 5,  "cmd+shift", "Cmd+Shift+G", "g", [.command, .shift]),
        ("cmd+shift+l", 37, "cmd+shift", "Cmd+Shift+L", "l", [.command, .shift]),
        ("cmd+shift+s", 1,  "cmd+shift", "Cmd+Shift+S", "s", [.command, .shift]),
        ("cmd+shift+2", 19, "cmd+shift", "Cmd+Shift+2", "2", [.command, .shift]),
    ]

    func getShortcuts() -> [String: String] {
        let prefs = getPreferences()
        let chat = prefs["shortcutChat"] as? String ?? "cmd+shift+x"
        let screenshot = prefs["shortcutScreenshot"] as? String ?? "cmd+shift+z"
        return ["chat": chat, "screenshot": screenshot]
    }

    func setShortcut(action: String, shortcutId: String) {
        // Validate shortcutId exists
        guard SettingsStore.shortcutOptions.contains(where: { $0.id == shortcutId }) else { return }
        let key = action == "chat" ? "shortcutChat" : "shortcutScreenshot"
        setPreference(key: key, value: shortcutId)
    }

    func shortcutOption(for id: String) -> (keyCode: Int, modifiers: String, label: String, keyEquiv: String, modMask: NSEvent.ModifierFlags)? {
        guard let opt = SettingsStore.shortcutOptions.first(where: { $0.id == id }) else { return nil }
        return (opt.keyCode, opt.modifiers, opt.label, opt.keyEquiv, opt.modMask)
    }

    // MARK: - Preferences

    private var prefsURL: URL { appSupportDir.appendingPathComponent("preferences.json") }

    func getPreferences() -> [String: Any] {
        if let data = try? Data(contentsOf: prefsURL),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict
        }
        return ["launchAtLogin": false, "saveLocation": "ask", "savePath": ""]
    }

    func setPreference(key: String, value: Any) {
        var prefs = getPreferences()
        prefs[key] = value
        if let data = try? JSONSerialization.data(withJSONObject: prefs, options: .prettyPrinted) {
            try? data.write(to: prefsURL)
        }

        // Handle launch at login
        if key == "launchAtLogin", let enabled = value as? Bool {
            setLaunchAtLogin(enabled)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let script: String
        if enabled {
            let appPath = Bundle.main.bundlePath
            script = "tell application \"System Events\" to make login item at end with properties {path:\"\(appPath)\", hidden:false}"
        } else {
            script = "tell application \"System Events\" to delete login item \"Glimpse\""
        }
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}
