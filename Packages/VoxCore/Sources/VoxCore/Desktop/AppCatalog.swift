import Foundation

public struct AppEntry: Equatable, Sendable {
    /// Display name, e.g. "Visual Studio Code".
    public let name: String
    public let url: URL
    /// Normalized for matching, e.g. "visual studio code".
    let key: String

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
        self.key = Tokenizer.normalizedPhrase(name)
    }
}

/// Installed apps, and spoken-name lookup ("text edit" -> TextEdit.app).
public struct AppCatalog: Sendable {
    public let entries: [AppEntry]

    public init(entries: [AppEntry]) {
        self.entries = entries
    }

    public static var standardDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/Applications", "/Applications/Utilities",
            "/System/Applications", "/System/Applications/Utilities",
            home.appendingPathComponent("Applications").path
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Finder lives outside the usual folders.
    static let extraApps = [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]

    public static func scan(
        directories: [URL] = standardDirectories,
        fileManager: FileManager = .default
    ) -> AppCatalog {
        var entries: [AppEntry] = []
        var seen = Set<String>()
        let candidates = directories.flatMap { dir -> [URL] in
            (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        } + extraApps.filter { fileManager.fileExists(atPath: $0.path) }

        for url in candidates where url.pathExtension == "app" {
            let name = url.deletingPathExtension().lastPathComponent
            let entry = AppEntry(name: name, url: url)
            if !entry.key.isEmpty, seen.insert(entry.key).inserted {
                entries.append(entry)
            }
        }
        return AppCatalog(entries: entries.sorted { $0.name < $1.name })
    }

    /// Common spoken names that don't match the app's real name.
    static let spokenAliases: [String: String] = [
        "vs code": "visual studio code", "vscode": "visual studio code", "code": "visual studio code",
        "chrome": "google chrome",
        "settings": "system settings", "system preferences": "system settings", "preferences": "system settings",
        "app store": "app store", "mail": "mail", "calendar": "calendar",
        "claude desktop": "claude", "whatsapp": "whatsapp"
    ]

    public func find(_ spoken: String) -> AppEntry? {
        var words = Tokenizer.words(spoken)
        while let first = words.first, ["the", "my"].contains(first) { words.removeFirst() }
        while let last = words.last, ["app", "application", "ide", "editor"].contains(last) { words.removeLast() }
        guard !words.isEmpty else { return nil }
        var key = words.joined(separator: " ")
        if let alias = Self.spokenAliases[key] { key = alias }
        let squashed = key.replacingOccurrences(of: " ", with: "")

        if let exact = entries.first(where: { $0.key == key }) { return exact }
        if let joined = entries.first(where: { $0.key.replacingOccurrences(of: " ", with: "") == squashed }) {
            return joined
        }
        // Prefix match ("xcode" -> "Xcode", "visual studio" -> "Visual Studio Code"),
        // shortest name wins. Requires 3+ characters to avoid silly matches.
        guard squashed.count >= 3 else { return nil }
        return entries
            .filter { $0.key.hasPrefix(key) || $0.key.replacingOccurrences(of: " ", with: "").hasPrefix(squashed) }
            .min { $0.name.count < $1.name.count }
    }

    /// Names to prime speech recognition with.
    public var names: [String] { entries.map(\.name) }
}
