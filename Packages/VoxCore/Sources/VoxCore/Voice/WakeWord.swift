import Foundation

/// Wake word settings in config.json under "wakeWord".
public struct WakeWordConfig: Codable, Equatable, Sendable {
    /// Listen continuously for the wake word.
    public var enabled: Bool
    /// The wake word plus the ways speech-to-text mishears it. Add what the
    /// "Last heard" line in the menu shows when it misses you.
    public var phrases: [String]
    /// Silence after the command that means "I'm done talking".
    public var silenceSeconds: Double
    /// How long to wait for a command after hearing only the wake word.
    public var commandTimeoutSeconds: Double

    public init(
        enabled: Bool = true,
        phrases: [String] = WakeWordConfig.defaultPhrases,
        silenceSeconds: Double = 1.3,
        commandTimeoutSeconds: Double = 6
    ) {
        self.enabled = enabled
        self.phrases = phrases
        self.silenceSeconds = silenceSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds
    }

    public static let defaultPhrases = [
        "balcha", "bal cha", "balch", "belcha", "bulcha", "balcher", "baltcha", "ball cha"
    ]

    enum CodingKeys: String, CodingKey { case enabled, phrases, silenceSeconds, commandTimeoutSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        phrases = try c.decodeIfPresent([String].self, forKey: .phrases) ?? Self.defaultPhrases
        silenceSeconds = try c.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? 1.3
        commandTimeoutSeconds = try c.decodeIfPresent(Double.self, forKey: .commandTimeoutSeconds) ?? 6
    }
}

/// Finds "<wake word> <command>" in a running transcript.
public struct WakeWordDetector: Sendable {
    private let matcher: PhraseMatcher

    public init(phrases: [String]) {
        matcher = PhraseMatcher(phrases: phrases)
    }

    /// Text after the LAST wake word: nil if no wake word, "" if nothing follows yet.
    public func command(in transcript: String) -> String? {
        let tokens = Tokenizer.tokenize(transcript)
        var index = tokens.count - 1
        while index >= 0 {
            if let m = matcher.match(tokens, at: index) {
                let rest = Tokenizer.remainder(of: transcript, tokens: tokens, from: index + m.length) ?? ""
                return rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            }
            index -= 1
        }
        return nil
    }
}

/// Decides when a wake-word command is complete. Pure and clock-injected, so
/// the timing rules are unit-tested; the app feeds it transcripts and ticks.
public struct WakeWordTracker: Sendable {
    public enum Event: Equatable, Sendable {
        case none
        /// Wake word heard; the command so far (may be empty).
        case awake(String)
        /// The finished command.
        case fire(String)
        /// Wake word heard but no command followed.
        case timedOut
    }

    private let detector: WakeWordDetector
    private let silence: Double
    private let timeout: Double
    /// A command that keeps growing is still fired after this long.
    private let maxCommandSeconds: Double = 15

    private var lastText = ""
    private var lastChange: Double = 0
    private var wokeAt: Double?

    public init(config: WakeWordConfig) {
        detector = WakeWordDetector(phrases: config.phrases)
        silence = config.silenceSeconds
        timeout = config.commandTimeoutSeconds
    }

    public var isAwake: Bool { wokeAt != nil }

    public mutating func update(transcript: String, at now: Double) -> Event {
        if transcript != lastText {
            lastText = transcript
            lastChange = now
        }
        guard let command = detector.command(in: transcript) else { return .none }
        if wokeAt == nil { wokeAt = now }
        return .awake(command)
    }

    public mutating func tick(at now: Double) -> Event {
        guard let woke = wokeAt else { return .none }
        let command = detector.command(in: lastText) ?? ""
        if !command.isEmpty, now - lastChange >= silence || now - woke >= maxCommandSeconds {
            reset()
            return .fire(command)
        }
        if command.isEmpty, now - woke >= timeout {
            reset()
            return .timedOut
        }
        return .none
    }

    public mutating func reset() {
        lastText = ""
        wokeAt = nil
    }
}
