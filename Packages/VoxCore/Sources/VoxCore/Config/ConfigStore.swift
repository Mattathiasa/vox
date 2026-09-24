import Foundation

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case unreadable(path: String, reason: String)
    case invalid([String])

    public var description: String {
        switch self {
        case let .unreadable(path, reason):
            return "Could not read config at \(path): \(reason)"
        case let .invalid(problems):
            return "Config has problems:\n- " + problems.joined(separator: "\n- ")
        }
    }
}

/// Loads and saves `config.json` in ~/Library/Application Support/Vox/.
public enum ConfigStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vox", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func load(from url: URL) throws -> VoxConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.unreadable(path: url.path, reason: error.localizedDescription)
        }
        let config: VoxConfig
        do {
            config = try JSONDecoder().decode(VoxConfig.self, from: data)
        } catch {
            throw ConfigError.unreadable(path: url.path, reason: String(describing: error))
        }
        let problems = ConfigValidator.problems(in: config)
        if !problems.isEmpty { throw ConfigError.invalid(problems) }
        return config
    }

    /// Loads the config, writing the starter config first if none exists.
    public static func loadOrCreate(at url: URL = defaultURL) throws -> VoxConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            try save(VoxConfig.starter, to: url)
        }
        return try load(from: url)
    }

    public static func save(_ config: VoxConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

public enum ConfigValidator {
    public static func problems(in config: VoxConfig) -> [String] {
        var problems: [String] = []

        if config.tools.isEmpty {
            problems.append("No tools configured. Add at least one entry to \"tools\".")
        }

        var seenNames = Set<String>()
        for tool in config.tools {
            if tool.name.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("A tool has an empty name.")
            }
            if tool.command.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append("Tool \"\(tool.name)\" has an empty command.")
            }
            if !seenNames.insert(tool.name.lowercased()).inserted {
                problems.append("Tool name \"\(tool.name)\" is used twice.")
            }
            if SessionNaming.sessionName(forTool: tool.name) == SessionNaming.prefix {
                problems.append("Tool name \"\(tool.name)\" has no letters or digits.")
            }
        }

        // Two different tools must not share a spoken phrase.
        var phraseOwner: [String: String] = [:]
        for tool in config.tools {
            for phrase in tool.phrases {
                let key = Tokenizer.normalizedPhrase(phrase)
                guard !key.isEmpty else { continue }
                if let owner = phraseOwner[key], owner != tool.name {
                    problems.append("Phrase \"\(phrase)\" refers to both \"\(owner)\" and \"\(tool.name)\".")
                } else {
                    phraseOwner[key] = tool.name
                }
            }
        }

        for pattern in config.confirmPatterns {
            if (try? NSRegularExpression(pattern: pattern)) == nil {
                problems.append("Confirm pattern is not a valid regex: \(pattern)")
            }
        }

        if config.affirmativePhrases.isEmpty {
            problems.append("affirmativePhrases is empty, so nothing could ever be confirmed.")
        }

        return problems
    }
}
