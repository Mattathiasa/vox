import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A concrete LLM adapter that implements the `LLMFallback` protocol.
///
/// Tries on-device Apple Foundation Models first (macOS 15+), then falls
/// back to the Claude API. The API key is passed in from the app (which
/// reads it from Keychain) — it never lives in VoxConfig.
public struct LLMAdapter: LLMFallback, @unchecked Sendable {
    public let config: LLMConfig
    public let apiKey: String?

    public init(config: LLMConfig, apiKey: String? = nil) {
        self.config = config
        self.apiKey = apiKey
    }

    public func plan(request: LLMRequest) async throws -> LLMResult {
        guard config.enabled else {
            return .feedback("LLM fallback is not enabled.")
        }
        switch config.provider {
        case .apple:
            return try await planWithApple(request)
        case .claude:
            return try await planWithClaude(request)
        }
    }

    // MARK: Claude API

    private func planWithClaude(_ request: LLMRequest) async throws -> LLMResult {
        guard let apiKey else {
            return .feedback("Set your Claude API key in Keychain to enable fallback.")
        }
        let model = config.model ?? "claude-3-5-haiku-20241022"
        let prompt = buildPrompt(request: request)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.httpBody = jsonData
        urlRequest.timeoutInterval = config.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw LLMError.badResponse(data, response)
        }
        let text = try Self.extractText(from: data)
        return LLMAdapter.parseLLMOutput(text)
    }

    // MARK: Apple (on-device, macOS 15+)

    private func planWithApple(_ request: LLMRequest) async throws -> LLMResult {
        if #available(macOS 15.0, *) {
            return try await planWithAppleFoundation(request)
        } else {
            return .feedback("On-device LLM requires macOS 15 or later.")
        }
    }

    @available(macOS 15.0, *)
    private func planWithAppleFoundation(_ request: LLMRequest) async throws -> LLMResult {
        #if canImport(MLF)
        guard let model = try? await MLGenerativeModel.instantiate() else {
            return .feedback("On-device model isn't available on this machine.")
        }
        let prompt = buildPrompt(request: request)
        guard let resp = try? await model.generate(prompts: [.user(prompt)]) else {
            throw LLMError.noResponse
        }
        let text = resp.compactMap { $0.content }.joined(separator: "\n")
        return parseLLMOutput(text)
        #else
        return .feedback("On-device LLM framework not linked.")
        #endif
    }

    // MARK: Prompt + output parsing

    private func buildPrompt(request: LLMRequest) -> String {
        let toolList = request.tools.map { "\($0.spokenPhrases.joined(separator: ", ")) → \($0.name)" }.joined(separator: "\n")
        return """
        \(request.instruction)

        Available tools:
        \(toolList)

        User said: "\(request.text)"

        Respond with exactly one line: either a Vox command, or "Feedback: <message>".
        """
    }

    /// Parse LLM output — either "Feedback: <msg>" or a Vox command string.
    static func parseLLMOutput(_ text: String) -> LLMResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Take only the first non-empty line.
        let firstLine = trimmed.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? ""
        let trimmedLine = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.lowercased().hasPrefix("feedback:") {
            let message = String(trimmedLine.dropFirst("Feedback:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .feedback(message)
        }
        return .command(trimmedLine)
    }

    // MARK: Response parsing (Claude)

    private static func extractText(from data: Data) throws -> String {
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = dict?["content"] as? [[String: Any]] else {
            throw LLMError.badResponse(data, nil)
        }
        return content.compactMap { $0["text"] as? String }.joined()
    }
}

public enum LLMError: Error, Equatable, CustomStringConvertible {
    case badResponse(Data, URLResponse?)
    case noResponse
    case timedOut
    case notEnabled

    public var description: String {
        switch self {
        case .badResponse: return "The LLM provider returned an error."
        case .noResponse: return "The LLM returned no response."
        case .timedOut: return "The LLM took too long."
        case .notEnabled: return "LLM fallback is not enabled."
        }
    }
}
