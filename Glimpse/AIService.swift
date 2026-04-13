import Foundation

/// Handles AI API calls to Claude, GPT, and Gemini.
/// Non-streaming: sends request, returns full response.
class AIService {
    private let session = URLSession.shared

    // MARK: - Chat

    func chatWithAI(messages: [[String: Any]], provider: String, modelId: String, apiKey: String) async -> [String: Any] {
        let systemPrompt = buildSystemPrompt(messages: messages)

        do {
            let response: String
            switch provider {
            case "anthropic":
                response = try await callClaude(messages: messages, model: modelId, apiKey: apiKey, systemPrompt: systemPrompt)
            case "openai":
                response = try await callOpenAI(messages: messages, model: modelId, apiKey: apiKey, systemPrompt: systemPrompt)
            case "gemini":
                response = try await callGemini(messages: messages, model: modelId, apiKey: apiKey, systemPrompt: systemPrompt)
            default:
                return ["success": false, "error": "Unknown provider: \(provider)"]
            }
            return ["success": true, "content": [["type": "text", "text": response]]]
        } catch {
            let msg = error.localizedDescription
            // Detect auth errors
            if msg.contains("401") || msg.contains("403") || msg.contains("Unauthorized") || msg.contains("invalid_api_key") {
                return ["success": false, "error": "auth_error"]
            }
            return ["success": false, "error": msg]
        }
    }

    // MARK: - Title Generation

    func generateTitle(messages: [[String: Any]], provider: String, modelId: String, apiKey: String) async -> [String: Any] {
        var titleMessages = messages
        titleMessages.append([
            "role": "user",
            "content": "Generate a very short title (3-6 words) for this conversation. Reply with ONLY the title, nothing else."
        ])

        do {
            let response: String
            switch provider {
            case "anthropic":
                response = try await callClaude(messages: titleMessages, model: modelId, apiKey: apiKey, systemPrompt: nil)
            case "openai":
                response = try await callOpenAI(messages: titleMessages, model: modelId, apiKey: apiKey, systemPrompt: nil)
            case "gemini":
                response = try await callGemini(messages: titleMessages, model: modelId, apiKey: apiKey, systemPrompt: nil)
            default:
                return ["success": false]
            }

            var title = response.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove surrounding quotes if present
            if title.hasPrefix("\"") && title.hasSuffix("\"") {
                title = String(title.dropFirst().dropLast())
            }
            if title.count > 40 {
                title = String(title.prefix(37)) + "..."
            }
            return ["success": true, "title": title]
        } catch {
            return ["success": false]
        }
    }

    // MARK: - Key Validation

    func validateApiKey(provider: String, key: String) async -> Bool {
        do {
            switch provider {
            case "anthropic":
                _ = try await callClaude(
                    messages: [["role": "user", "content": "hi"]],
                    model: "claude-haiku-4-5-20251001", apiKey: key, systemPrompt: nil, maxTokens: 10
                )
            case "openai":
                _ = try await callOpenAI(
                    messages: [["role": "user", "content": "hi"]],
                    model: "gpt-4o-mini", apiKey: key, systemPrompt: nil, maxTokens: 10
                )
            case "gemini":
                _ = try await callGemini(
                    messages: [["role": "user", "content": "hi"]],
                    model: "gemini-2.5-flash", apiKey: key, systemPrompt: nil
                )
            default:
                return false
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(messages: [[String: Any]]) -> String? {
        // Check if any message contains referenced text
        let hasRef = messages.contains { msg in
            if let content = msg["content"] as? String {
                return content.contains("[Referenced text:")
            }
            if let contentArr = msg["content"] as? [[String: Any]] {
                return contentArr.contains { part in
                    if let text = part["text"] as? String {
                        return text.contains("[Referenced text:")
                    }
                    return false
                }
            }
            return false
        }

        if hasRef {
            return "When the user shares referenced text for proofreading, editing, or rewriting, always put your revised/rewritten version inside a markdown blockquote (lines starting with >). Keep your explanations outside the blockquote."
        }
        return nil
    }

    // MARK: - Claude API

    private func callClaude(messages: [[String: Any]], model: String, apiKey: String, systemPrompt: String?, maxTokens: Int = 4096) async throws -> String {
        var url = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        url.httpMethod = "POST"
        url.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        url.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        url.setValue("application/json", forHTTPHeaderField: "content-type")

        // Convert messages: flatten content arrays to string for non-vision
        let apiMessages = messages.compactMap { msg -> [String: Any]? in
            var m: [String: Any] = ["role": msg["role"] ?? "user"]
            if let content = msg["content"] as? String {
                m["content"] = content
            } else if let contentArr = msg["content"] as? [[String: Any]] {
                // Skip messages with empty content (can happen when file-referenced images are stripped)
                guard !contentArr.isEmpty else {
                    NSLog("[AI] Skipping message with empty content (images stripped)")
                    return nil
                }
                m["content"] = contentArr
            }
            return m
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": apiMessages
        ]
        if let sys = systemPrompt {
            body["system"] = sys
        }

        url.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: url)
        guard let httpResp = response as? HTTPURLResponse else {
            throw APIError.httpError(0, "Invalid response")
        }

        if httpResp.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard httpResp.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(httpResp.statusCode, bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            NSLog("[AI] Claude parse fail. Body: \(bodyStr.prefix(500))")
            throw APIError.parseError("Could not parse Claude response")
        }
        return text
    }

    // MARK: - OpenAI API

    private func callOpenAI(messages: [[String: Any]], model: String, apiKey: String, systemPrompt: String?, maxTokens: Int = 4096) async throws -> String {
        var url = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        url.httpMethod = "POST"
        url.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        url.setValue("application/json", forHTTPHeaderField: "content-type")

        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            var m: [String: Any] = ["role": msg["role"] ?? "user"]
            if let content = msg["content"] as? String {
                m["content"] = content
            } else if let contentArr = msg["content"] as? [[String: Any]] {
                // Flatten content array to string for non-vision models
                let text = contentArr.compactMap { $0["text"] as? String }.joined()
                m["content"] = text
            }
            apiMessages.append(m)
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": apiMessages
        ]
        url.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: url)
        guard let httpResp = response as? HTTPURLResponse else {
            throw APIError.httpError(0, "Invalid response")
        }

        if httpResp.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard httpResp.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(httpResp.statusCode, bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw APIError.parseError("Could not parse OpenAI response")
        }
        return content
    }

    // MARK: - Gemini API

    private func callGemini(messages: [[String: Any]], model: String, apiKey: String, systemPrompt: String?) async throws -> String {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var url = URLRequest(url: URL(string: urlStr)!)
        url.httpMethod = "POST"
        url.setValue("application/json", forHTTPHeaderField: "content-type")

        // Convert messages to Gemini format: role=model (not assistant), content→parts
        var contents: [[String: Any]] = []
        for msg in messages {
            let role = (msg["role"] as? String == "assistant") ? "model" : "user"
            var parts: [[String: Any]] = []
            if let content = msg["content"] as? String {
                parts.append(["text": content])
            } else if let contentArr = msg["content"] as? [[String: Any]] {
                let text = contentArr.compactMap { $0["text"] as? String }.joined()
                parts.append(["text": text])
            }
            contents.append(["role": role, "parts": parts])
        }

        var body: [String: Any] = ["contents": contents]
        if let sys = systemPrompt {
            body["systemInstruction"] = ["parts": [["text": sys]]]
        }

        url.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: url)
        guard let httpResp = response as? HTTPURLResponse else {
            throw APIError.httpError(0, "Invalid response")
        }

        if httpResp.statusCode == 400 || httpResp.statusCode == 403 {
            throw APIError.unauthorized
        }
        guard httpResp.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(httpResp.statusCode, bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw APIError.parseError("Could not parse Gemini response")
        }
        return text
    }
}

enum APIError: LocalizedError {
    case unauthorized
    case httpError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "401 Unauthorized"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .parseError(let msg): return msg
        }
    }
}
