import Foundation

/// A tool definition sent to the LLM so it knows what can be invoked.
/// The LLM should only return a command that names one of these tools;
/// it never writes shell directly.
public struct LLMToolDefinition: Equatable, Sendable {
    public var name: String
    public var spokenPhrases: [String]

    public init(name: String, spokenPhrases: [String]) {
        self.name = name
        self.spokenPhrases = spokenPhrases
    }
}

/// The request sent to the LLM fallback when the rule-based parser returns `.unknown`.
public struct LLMRequest: Equatable, Sendable {
    /// The user's original utterance, verbatim.
    public var text: String
    /// Tools available for the LLM to route to (from the user's config).
    public var tools: [LLMToolDefinition]
    /// Natural-language instruction for the LLM. Must be short and stable.
    public var instruction: String

    public init(text: String, tools: [LLMToolDefinition], instruction: String) {
        self.text = text
        self.tools = tools
        self.instruction = instruction
    }
}

/// The LLM returns either a Vox command string (re-routed through the parser)
/// or a direct feedback message.
public enum LLMResult: Equatable, Sendable {
    /// The LLM produced a command — re-feed it through the parser/safety pipeline.
    case command(String)
    /// The LLM couldn't understand either; show the user this message.
    case feedback(String)
}

    /// Protocol the app target provides; the engine calls this on `.unknown`.
    /// The LLM may **never** return shell text — only a command string or feedback.
    public protocol LLMFallback: Sendable {
        func plan(request: LLMRequest) async throws -> LLMResult
    }

    /// Runs `operation` with a timeout. Throws `LLMError.timedOut` if it doesn't finish.
    private enum _TimeoutOutcome<T> {
        case value(T)
        case timeout
    }
    public func withTimeout<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: _TimeoutOutcome<T>?.self) { group in
            group.addTask {
                do {
                    return .value(try await operation())
                } catch {
                    throw error
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .timeout
            }
            let outcome = try await group.next()
            group.cancelAll()
            if case .some(.value(let value)) = outcome {
                return value
            }
            throw LLMError.timedOut
        }
    }

/// The stable instruction given to every LLM session.
public let llmInstruction = """
You are Vox, a voice assistant for developers. The user said something that didn't \
match a known command. Translate it into a short Vox command that the parser will \
understand, or reply with feedback if you truly can't.

Available commands: "run <tool> in <project>", "tell <tool> to <message>", \
"switch to <tool>", "kill <tool>", "ask <ide> to <message>", "open <app>", \
"search for <query>", "type <text>", "create a note…", "set a timer…", etc.

Only name tools that are in the provided list. Never produce shell commands.

Respond with exactly one line: either a Vox command, or "Feedback: <message>".
"""
