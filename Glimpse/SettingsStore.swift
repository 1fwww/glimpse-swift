import Foundation

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

        var result: [String: Any] = [
            "hasAnyKey": false,
            "isInvite": isInvite
        ]

        let anthropic = masked(keys["ANTHROPIC_API_KEY"])
        let openai = masked(keys["OPENAI_API_KEY"])
        let gemini = masked(keys["GEMINI_API_KEY"])

        if anthropic != nil { result["anthropicKey"] = anthropic! }
        if openai != nil { result["openaiKey"] = openai! }
        if gemini != nil { result["geminiKey"] = gemini! }

        result["hasAnyKey"] = (anthropic != nil || openai != nil || gemini != nil)
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

    /// Validate invite code and populate keys from env vars
    func validateInviteCode(_ code: String) -> [String: Any] {
        guard code == "KPIMG" else {
            return ["valid": false, "error": "Invalid invite code"]
        }
        let env = ProcessInfo.processInfo.environment
        let anthropic = env["GLIMPSE_ANTHROPIC_KEY"] ?? ""
        let openai = env["GLIMPSE_OPENAI_KEY"] ?? ""
        let gemini = env["GLIMPSE_GEMINI_KEY"] ?? ""

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
