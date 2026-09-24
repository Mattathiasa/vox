import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Which Vox terminal in the IDE: "terminal 2" / "the second one", or any unused one.
public enum IDETerminalTarget: Equatable, Sendable {
    case number(Int)
    case any
}

/// Something to do in a VS Code–based IDE through the Vox Bridge extension.
public enum IDECommand: Equatable, Sendable {
    case openTerminals(count: Int, commands: [String])
    case send(IDETerminalTarget, text: String, submit: Bool)
    case closeTerminals
    /// Send a prompt to the IDE's AI chat and (optionally) submit it.
    case chat(message: String, submit: Bool)
    /// Open a file by path (workspace-relative or absolute). Vox normalizes the spoken path.
    case openFile(path: String)
    /// Open a folder by path (workspace-relative or absolute).
    case openFolder(path: String)
    /// Run a named task (matched against tasks defined in the IDE's tasks.json).
    case runTask(name: String)
}

public struct IDEReply: Decodable, Equatable, Sendable {
    public var ok: Bool
    public var message: String?
    public var ide: String?

    public init(ok: Bool, message: String? = nil, ide: String? = nil) {
        self.ok = ok
        self.message = message
        self.ide = ide
    }
}

public enum IDEBridgeError: Error, Equatable, CustomStringConvertible {
    case notRunning(ide: String?)
    case badResponse(String)

    public var description: String {
        switch self {
        case let .notRunning(ide):
            let name = ide ?? "an IDE"
            return "Couldn't reach the Vox Bridge in \(name). Install it with scripts/Install-IDE-Bridge.command, then reload the IDE window."
        case let .badResponse(detail):
            return "The IDE bridge answered strangely: \(detail)"
        }
    }
}

/// Sends IDE commands. Faked in tests.
public protocol IDEBridging: Sendable {
    /// `preferring`: the IDE the user just opened ("Antigravity"); waits up to
    /// `waitSeconds` for its bridge to come up.
    func perform(_ command: IDECommand, preferring ide: String?, waitSeconds: Double) async throws -> IDEReply
}

/// What the extension writes to ~/Library/Application Support/Vox/bridges/<ide>-<pid>.json.
public struct BridgeInfo: Decodable, Equatable, Sendable {
    public var ide: String
    public var port: Int
    public var token: String
    public var pid: Int32
    public var workspace: String?
    public var focusedAt: Double
}

/// Finds running bridges from their info files and talks to them over
/// localhost HTTP.
public struct HTTPIDEBridge: IDEBridging {
    public let directory: URL

    public init(directory: URL = HTTPIDEBridge.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vox/bridges", isDirectory: true)
    }

    // MARK: Discovery

    /// Live bridges, most recently focused first.
    public func candidates() -> [BridgeInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(BridgeInfo.self, from: $0) } }
            .filter { Self.isAlive(pid: $0.pid) }
            .sorted { $0.focusedAt > $1.focusedAt }
    }

    /// The bridge for `preferred` ("Antigravity"), or the most recently focused
    /// one when no preference was given.
    public static func choose(from infos: [BridgeInfo], preferring preferred: String?) -> BridgeInfo? {
        guard let preferred else { return infos.first }
        let want = Tokenizer.normalizedPhrase(preferred)
        return infos.first { info in
            let have = Tokenizer.normalizedPhrase(info.ide)
            return have == want || have.hasPrefix(want) || want.hasPrefix(have)
        }
    }

    static func isAlive(pid: Int32) -> Bool {
        pid > 0 && kill(pid, 0) == 0
    }

    // MARK: Requests

    public func perform(_ command: IDECommand, preferring ide: String?, waitSeconds: Double) async throws -> IDEReply {
        let deadline = Date().addingTimeInterval(waitSeconds)
        var lastError: Error = IDEBridgeError.notRunning(ide: ide)
        repeat {
            if let bridge = Self.choose(from: candidates(), preferring: ide) {
                do {
                    return try await send(command, to: bridge)
                } catch {
                    lastError = error // stale file or IDE still starting: retry until the deadline
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        } while Date() < deadline
        throw lastError
    }

    static func body(for command: IDECommand, token: String) -> [String: Any] {
        var body: [String: Any] = ["token": token]
        switch command {
        case let .openTerminals(count, commands):
            body["action"] = "openTerminals"
            body["count"] = count
            body["commands"] = commands
        case let .send(target, text, submit):
            body["action"] = "send"
            if case let .number(n) = target { body["terminal"] = n } else { body["terminal"] = NSNull() }
            body["text"] = text
            body["submit"] = submit
        case .closeTerminals:
            body["action"] = "closeTerminals"
        case let .chat(message, submit):
            body["action"] = "chat"
            body["message"] = message
            body["submit"] = submit
        case let .openFile(path):
            body["action"] = "openFile"
            body["path"] = path
        case let .openFolder(path):
            body["action"] = "openFolder"
            body["path"] = path
        case let .runTask(name):
            body["action"] = "runTask"
            body["name"] = name
        }
        return body
    }

    private func send(_ command: IDECommand, to bridge: BridgeInfo) async throws -> IDEReply {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(bridge.port)/command")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: command, token: bridge.token))

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: data ?? Data()) }
            }.resume()
        }
        do {
            return try JSONDecoder().decode(IDEReply.self, from: data)
        } catch {
            throw IDEBridgeError.badResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
    }
}

/// Cleans up spoken shell commands: "Npm run dev." -> "npm run dev",
/// "git commit dash m fix" -> "git commit -m fix", "cd dot dot slash src" -> "cd ../src".
public enum ShellText {
    public static func normalize(_ text: String) -> String {
        var words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
        // Speech-to-text ends sentences with a period.
        if var last = words.last {
            while last.hasSuffix("."), !last.hasSuffix("..") { last.removeLast() }
            if last.isEmpty { words.removeLast() } else { words[words.count - 1] = last }
        }

        var out: [String] = []
        var glueNext = false
        func append(_ piece: String, left: Bool, right: Bool) {
            if left, let last = out.popLast() { out.append(last + piece) } else { out.append(piece) }
            glueNext = right
        }

        var i = 0
        while i < words.count {
            let w = words[i].lowercased()
            let next = i + 1 < words.count ? words[i + 1].lowercased() : ""
            switch (w, next) {
            case ("dash", "dash"), ("double", "dash"):
                append("--", left: glueNext, right: true); i += 2; continue
            case ("and", "and"), ("ampersand", "ampersand"):
                append("&&", left: false, right: false); i += 2; continue
            case ("dot", "dot"):
                append("..", left: glueNext, right: true); i += 2; continue
            case ("at", "sign"):
                append("@", left: true, right: true); i += 2; continue
            default:
                break
            }
            switch w {
            case "dash", "hyphen": append("-", left: glueNext, right: true)
            case "dot": append(".", left: true, right: true)
            // "cd slash users" -> "cd /users", but "src slash app" -> "src/app"
            case "slash": append("/", left: glueNext || out.count >= 2, right: true)
            case "underscore": append("_", left: true, right: true)
            case "equals": append("=", left: true, right: true)
            case "colon": append(":", left: true, right: true)
            case "tilde": append("~", left: glueNext, right: true)
            case "pipe": append("|", left: false, right: false)
            default: append(words[i], left: glueNext, right: false)
            }
            i += 1
        }

        guard let first = out.first else { return "" }
        out[0] = first.lowercased()
        return out.joined(separator: " ")
    }
}
