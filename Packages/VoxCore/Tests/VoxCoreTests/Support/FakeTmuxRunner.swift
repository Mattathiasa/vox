import Foundation
@testable import VoxCore

/// Simulates just enough of a tmux server to test the adapter and engine.
final class FakeTmuxRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    var sessions: Set<String> = []
    var deadPanes: Set<String> = []
    var failNewSession = false
    var screen = "fake screen"

    /// Text typed with `send-keys -l`, per session, in order.
    var typed: [String: [String]] {
        var result: [String: [String]] = [:]
        for call in calls where call.first == "send-keys" && call.contains("-l") {
            let session = Self.session(fromPane: call[2])
            result[session, default: []].append(call.last ?? "")
        }
        return result
    }

    func commands() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return calls.compactMap(\.first)
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        precondition(Array(arguments.prefix(2)) == ["-L", "vox"], "must use the vox socket")
        let args = Array(arguments.dropFirst(2))
        calls.append(args)

        switch args.first {
        case "has-session":
            let name = String(args[2].dropFirst()) // "=vox-x"
            return CommandResult(status: sessions.contains(name) ? 0 : 1)
        case "new-session":
            if failNewSession { return CommandResult(status: 1, stderr: "boom") }
            if let i = args.firstIndex(of: "-s") { sessions.insert(args[i + 1]) }
            return CommandResult(status: 0)
        case "kill-session":
            let name = String(args[2].dropFirst())
            sessions.remove(name)
            deadPanes.remove(name)
            return CommandResult(status: 0)
        case "list-sessions":
            if sessions.isEmpty { return CommandResult(status: 1, stderr: "no server running") }
            return CommandResult(status: 0, stdout: sessions.sorted().joined(separator: "\n") + "\n")
        case "display-message":
            let name = Self.session(fromPane: args[3])
            return CommandResult(status: 0, stdout: deadPanes.contains(name) ? "1\n" : "0\n")
        case "send-keys":
            return CommandResult(status: sessions.contains(Self.session(fromPane: args[2])) ? 0 : 1)
        case "resize-window":
            return CommandResult(status: sessions.contains(Self.session(fromPane: args[2])) ? 0 : 1)
        case "capture-pane":
            return CommandResult(status: 0, stdout: screen)
        default:
            return CommandResult(status: 1, stderr: "unexpected command \(args)")
        }
    }

    /// "vox-x:" -> "vox-x"
    static func session(fromPane target: String) -> String {
        target.hasSuffix(":") ? String(target.dropLast()) : target
    }
}

extension VoxConfig {
    /// Small, stable config for tests (independent of the starter config).
    static let test = VoxConfig(
        tools: [
            ToolConfig(name: "freebuff", aliases: ["free buff", "freebuf"], command: "freebuff",
                       defaultDirectory: "~/Projects", startupDelaySeconds: 2),
             ToolConfig(name: "claude", aliases: ["claude code", "cloud code"], command: "claude")
        ],
        projects: [
            ProjectConfig(name: "chirp", aliases: ["chip"], path: "~/Projects/chirp"),
            ProjectConfig(name: "cbs", aliases: ["bible study"], path: "~/Projects/cbs-study-sessions")
        ],
        llm: LLMConfig(enabled: false)
    )
}
