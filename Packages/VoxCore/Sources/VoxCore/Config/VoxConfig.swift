import Foundation

/// A command-line tool Vox is allowed to launch (the allowlist).
/// `command` is the ONLY string that ever reaches a shell. It comes from the
/// user's config file, never from speech or an LLM.
public struct ToolConfig: Codable, Equatable, Sendable {
    /// Canonical name, also used for the tmux session name (`vox-<name>`).
    public var name: String
    /// Other ways speech-to-text may spell the name ("free buff", "freebuf").
    public var aliases: [String]
    /// Shell command that starts the tool, e.g. "freebuff".
    public var command: String
    /// Directory to start in when no project is named. Supports "~".
    public var defaultDirectory: String?
    /// Seconds to wait after launch before sending an initial prompt.
    public var startupDelaySeconds: Double

    public init(
        name: String,
        aliases: [String] = [],
        command: String,
        defaultDirectory: String? = nil,
        startupDelaySeconds: Double = 4
    ) {
        self.name = name
        self.aliases = aliases
        self.command = command
        self.defaultDirectory = defaultDirectory
        self.startupDelaySeconds = startupDelaySeconds
    }

    enum CodingKeys: String, CodingKey {
        case name, aliases, command, defaultDirectory, startupDelaySeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        command = try c.decode(String.self, forKey: .command)
        defaultDirectory = try c.decodeIfPresent(String.self, forKey: .defaultDirectory)
        startupDelaySeconds = try c.decodeIfPresent(Double.self, forKey: .startupDelaySeconds) ?? 4
    }

    /// Name plus aliases: every phrase that refers to this tool.
    public var phrases: [String] { [name] + aliases }
}

/// A folder you can name by voice: "run freebuff in chirp".
public struct ProjectConfig: Codable, Equatable, Sendable {
    public var name: String
    public var aliases: [String]
    public var path: String

    public init(name: String, aliases: [String] = [], path: String) {
        self.name = name
        self.aliases = aliases
        self.path = path
    }

    enum CodingKeys: String, CodingKey { case name, aliases, path }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        path = try c.decode(String.self, forKey: .path)
    }

    public var phrases: [String] { [name] + aliases }
}

/// Which LLM provider to use for unrecognized commands (Phase 6).
public enum LLMProvider: String, Codable, Equatable, Sendable {
    case apple    /// On-device Apple Foundation Model (macOS 15+)
    case claude   /// Claude API (Anthropic)
}

/// Configuration for the Phase 6 LLM fallback.
public struct LLMConfig: Codable, Equatable, Sendable {
    /// Whether LLM fallback is enabled.
    public var enabled: Bool
    /// Which provider to use.
    public var provider: LLMProvider
    /// Model name passed to the provider (e.g. "claude-3-5-haiku-20241022").
    /// nil = provider default.
    public var model: String?
    /// How long to wait for the LLM before giving up.
    public var timeoutSeconds: Double

    public init(
        enabled: Bool = false,
        provider: LLMProvider = .apple,
        model: String? = nil,
        timeoutSeconds: Double = 10
    ) {
        self.enabled = enabled
        self.provider = provider
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct VoxConfig: Codable, Equatable, Sendable {
    public var tools: [ToolConfig]
    public var projects: [ProjectConfig]
    /// Whole-utterance phrases that leave pass-through mode ("exit", "done").
    public var exitPhrases: [String]
    /// Words that mark an utterance as a Vox command while locked to a tool
    /// ("vox switch to claude").
    public var commandPrefixes: [String]
    /// Regexes (case-insensitive). Text matching any of them needs a spoken "yes".
    public var confirmPatterns: [String]
    /// Answers that confirm a pending action. Anything else cancels it.
    public var affirmativePhrases: [String]
    /// Absolute path to tmux. nil = search the usual Homebrew locations.
    public var tmuxPath: String?
    /// Login shell used to start tools, so your PATH (npm, brew) is loaded.
    public var shell: String
    /// "Balcha, open safari": continuous listening for a wake word.
    public var wakeWord: WakeWordConfig
    /// Speak confirmations, warnings and errors for voice commands.
    public var speakFeedback: Bool
    /// LLM fallback config (Phase 6). nil = no fallback; .disabled = explicit off.
    public var llm: LLMConfig?

    public init(
        tools: [ToolConfig],
        projects: [ProjectConfig] = [],
        exitPhrases: [String] = VoxConfig.defaultExitPhrases,
        commandPrefixes: [String] = VoxConfig.defaultCommandPrefixes,
        confirmPatterns: [String] = VoxConfig.defaultConfirmPatterns,
        affirmativePhrases: [String] = VoxConfig.defaultAffirmativePhrases,
        tmuxPath: String? = nil,
        shell: String = "/bin/zsh",
        wakeWord: WakeWordConfig = WakeWordConfig(),
        speakFeedback: Bool = true,
        llm: LLMConfig? = nil
    ) {
        self.tools = tools
        self.projects = projects
        self.exitPhrases = exitPhrases
        self.commandPrefixes = commandPrefixes
        self.confirmPatterns = confirmPatterns
        self.affirmativePhrases = affirmativePhrases
        self.tmuxPath = tmuxPath
        self.shell = shell
        self.wakeWord = wakeWord
        self.speakFeedback = speakFeedback
        self.llm = llm
    }

    enum CodingKeys: String, CodingKey {
        case tools, projects, exitPhrases, commandPrefixes, confirmPatterns
        case affirmativePhrases, tmuxPath, shell, wakeWord, speakFeedback, llm
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tools = try c.decodeIfPresent([ToolConfig].self, forKey: .tools) ?? []
        projects = try c.decodeIfPresent([ProjectConfig].self, forKey: .projects) ?? []
        exitPhrases = try c.decodeIfPresent([String].self, forKey: .exitPhrases) ?? VoxConfig.defaultExitPhrases
        commandPrefixes = try c.decodeIfPresent([String].self, forKey: .commandPrefixes) ?? VoxConfig.defaultCommandPrefixes
        confirmPatterns = try c.decodeIfPresent([String].self, forKey: .confirmPatterns) ?? VoxConfig.defaultConfirmPatterns
        affirmativePhrases = try c.decodeIfPresent([String].self, forKey: .affirmativePhrases) ?? VoxConfig.defaultAffirmativePhrases
        tmuxPath = try c.decodeIfPresent(String.self, forKey: .tmuxPath)
        shell = try c.decodeIfPresent(String.self, forKey: .shell) ?? "/bin/zsh"
        wakeWord = try c.decodeIfPresent(WakeWordConfig.self, forKey: .wakeWord) ?? WakeWordConfig()
        speakFeedback = try c.decodeIfPresent(Bool.self, forKey: .speakFeedback) ?? true
        llm = try c.decodeIfPresent(LLMConfig.self, forKey: .llm)
    }

    public func tool(named name: String) -> ToolConfig? {
        tools.first { $0.name == name }
    }

    public func project(named name: String) -> ProjectConfig? {
        projects.first { $0.name == name }
    }

    // MARK: Defaults

    public static let defaultExitPhrases = [
        "exit", "done", "unlock", "stop listening", "back to vox", "that's all"
    ]

    public static let defaultCommandPrefixes = ["vox", "hey vox", "computer"]

    public static let defaultConfirmPatterns = [
        #"\bpush\b"#,
        #"\bdeploy"#,
        #"\b(delete|remove|drop|wipe|erase|destroy|truncate)\b"#,
        #"\brm\b"#,
        #"\breset\b.*\bhard\b"#,
        #"\bforce\b"#,
        #"\b(publish|release)\b"#
    ]

    public static let defaultAffirmativePhrases = [
        "yes", "yeah", "yep", "confirm", "do it", "go ahead", "affirmative", "yes please"
    ]

    /// Starting config written on first launch. Edit the JSON file, not this.
    public static let starter = VoxConfig(
        tools: [
            ToolConfig(name: "freebuff", aliases: ["free buff", "freebuf", "free buf", "free bath"],
                       command: "freebuff", defaultDirectory: "~/Projects"),
            ToolConfig(name: "claude", aliases: ["claude code", "cloud code", "clod"],
                       command: "claude", defaultDirectory: "~/Projects"),
            ToolConfig(name: "codex", aliases: ["codecs", "code x"],
                       command: "codex", defaultDirectory: "~/Projects"),
            ToolConfig(name: "gemini", aliases: ["gemini cli", "jiminy"],
                       command: "gemini", defaultDirectory: "~/Projects"),
            ToolConfig(name: "opencode", aliases: ["open code"],
                       command: "opencode", defaultDirectory: "~/Projects")
        ],
        projects: [
            ProjectConfig(name: "vox", aliases: ["box", "this project"], path: "~/Projects/vox"),
            ProjectConfig(name: "chirp", aliases: ["chip"], path: "~/Projects/chirp"),
            ProjectConfig(name: "decrypt", aliases: ["bulls and cows"], path: "~/Projects/decrypt"),
            ProjectConfig(name: "cbs", aliases: ["c b s", "bible study", "cbs study sessions"],
                          path: "~/Projects/cbs-study-sessions")
        ],
        llm: LLMConfig(enabled: true, provider: .apple)
    )
}
