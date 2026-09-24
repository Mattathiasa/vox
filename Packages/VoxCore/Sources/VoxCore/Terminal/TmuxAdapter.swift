import Foundation

public enum SessionNaming {
    public static let prefix = "vox-"

    /// "Free Buff!" -> "vox-free-buff". tmux forbids "." and ":" in names.
    public static func sessionName(forTool tool: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        var slug = ""
        for ch in tool.lowercased() {
            if allowed.contains(ch) {
                slug.append(ch)
            } else if slug.last != "-" {
                slug.append("-")
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return prefix + slug
    }
}

public enum TmuxError: Error, Equatable, CustomStringConvertible {
    case tmuxNotFound
    case commandFailed(arguments: [String], stderr: String)
    case sessionNotRunning(String)
    case processExited(String)

    public var description: String {
        switch self {
        case .tmuxNotFound:
            return "tmux not found. Install it with: brew install tmux"
        case let .commandFailed(arguments, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "tmux \(arguments.first ?? "") failed: \(detail.isEmpty ? "no error output" : detail)"
        case let .sessionNotRunning(name):
            return "Session \(name) is not running."
        case let .processExited(name):
            return "The program in \(name) has exited. Say \"kill\" and run it again."
        }
    }
}

/// Controls tools running inside tmux sessions on a dedicated tmux server
/// (`tmux -L vox`), so Vox never touches your own tmux sessions.
///
/// Attach to watch a tool: `tmux -L vox attach -t vox-freebuff`
public struct TmuxAdapter: Sendable {
    public static let socketName = "vox"
    /// Includes ~/.homebrew for per-user Homebrew installs.
    public static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [home + "/.homebrew/bin/tmux", "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
    }

    public let tmuxPath: String
    public let shell: String
    private let runner: CommandRunning

    public init(tmuxPath: String, shell: String = "/bin/zsh", runner: CommandRunning = ProcessRunner()) {
        self.tmuxPath = tmuxPath
        self.shell = shell
        self.runner = runner
    }

    /// Finds tmux. Apps launched from Finder don't get your shell's PATH, so
    /// we look in the usual places instead of relying on `which`.
    public static func locate(configured: String?, fileManager: FileManager = .default) -> String? {
        if let configured, fileManager.isExecutableFile(atPath: configured) { return configured }
        return searchPaths.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Shell command to attach to a session from any terminal.
    public static func attachCommand(session: String) -> String {
        "\(defaultTmuxName) -L \(socketName) attach -t \(session)"
    }
    private static let defaultTmuxName = "tmux"

    // MARK: Session lifecycle

    public func hasSession(_ session: String) -> Bool {
        (try? tmux(["has-session", "-t", "=\(session)"]).succeeded) ?? false
    }

    /// Starts `command` in a new detached session through a login shell, so
    /// npm/brew binaries are on PATH. `remain-on-exit` keeps a crashed tool's
    /// last output visible instead of the session silently disappearing.
    public func start(session: String, command: String, directory: String?) throws {
        var args = ["new-session", "-d", "-s", session, "-x", "200", "-y", "50"]
        if let directory {
            args += ["-c", Self.expandTilde(directory)]
        }
        args += [shell, "-lc", command]
        // ";" chains a second tmux command in the same invocation, so the option
        // is set before the child can exit.
        args += [";", "set-option", "-w", "-t", "\(session):", "remain-on-exit", "on"]
        try check(args)
    }

    public func kill(session: String) throws {
        try check(["kill-session", "-t", "=\(session)"])
    }

    /// Vox's sessions. An absent tmux server just means none are running.
    public func listSessions() -> [String] {
        guard let result = try? tmux(["list-sessions", "-F", "#{session_name}"]),
              result.succeeded else { return [] }
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix(SessionNaming.prefix) }
    }

    /// True if the program in the session has exited (the pane is kept by remain-on-exit).
    public func isPaneDead(_ session: String) -> Bool {
        guard let result = try? tmux(["display-message", "-p", "-t", "\(session):", "#{pane_dead}"]),
              result.succeeded else { return false }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Working directory of the session's pane.
    public func currentPath(session: String) -> String? {
        guard let result = try? tmux(["display-message", "-p", "-t", "\(session):", "#{pane_current_path}"]),
              result.succeeded else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Resizes the session's window so the program redraws for that many
    /// columns and rows (like resizing a real terminal).
    public func resize(session: String, columns: Int, rows: Int) throws {
        try check(["resize-window", "-t", "\(session):", "-x", String(columns), "-y", String(rows)])
    }

    // MARK: Input and output

    /// Types `text` literally (`-l`: words like "Enter" or "C-c" are not key
    /// names). Does not press Enter; call `submit` for that.
    public func type(session: String, text: String) throws {
        try check(["send-keys", "-t", "\(session):", "-l", text])
    }

    public func submit(session: String) throws {
        try check(["send-keys", "-t", "\(session):", "Enter"])
    }

    /// Keys the HUD's terminal buttons may send. Anything else is refused.
    public static let allowedKeys: Set<String> = [
        "Enter", "Escape", "Up", "Down", "Left", "Right", "Tab", "BTab", "C-c", "C-d", "C-l",
        // Live typing (phone remote / Mac tiles): Backspace, forward delete, Home/End, PgUp/PgDn
        "BSpace", "DC", "Home", "End", "PPage", "NPage"
    ]

    public func sendKey(session: String, key: String) throws {
        guard Self.allowedKeys.contains(key) else {
            throw TmuxError.commandFailed(arguments: ["send-keys", key], stderr: "key not allowed")
        }
        try check(["send-keys", "-t", "\(session):", key])
    }

    public func interrupt(session: String) throws {
        try check(["send-keys", "-t", "\(session):", "C-c"])
    }

    /// The last `lines` lines of the session's screen and scrollback.
    public func capture(session: String, lines: Int = 200) throws -> String {
        let result = try tmux(["capture-pane", "-p", "-J", "-t", "\(session):", "-S", "-\(lines)"])
        guard result.succeeded else {
            throw TmuxError.commandFailed(arguments: ["capture-pane"], stderr: result.stderr)
        }
        return result.stdout
    }

    // MARK: Plumbing

    private func tmux(_ args: [String]) throws -> CommandResult {
        try runner.run(tmuxPath, ["-L", Self.socketName] + args)
    }

    private func check(_ args: [String]) throws {
        let result = try tmux(args)
        if !result.succeeded {
            throw TmuxError.commandFailed(arguments: args, stderr: result.stderr)
        }
    }

    static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst()
    }
}
