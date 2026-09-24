import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// The Remote protocol (docs/ARCHITECTURE.md "Remote protocol"): the phone web app
// (web/remote) + a small JSON API behind a bearer pairing code. Same protocol as
// the Windows agent (windows/src/server.js). Everything here is pure and tested;
// the socket lives in RemoteServer.swift.

// MARK: - HTTP

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    /// Path without the query, e.g. "/api/state".
    public var path: String
    public var query: [String: String]
    /// Header names lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    public enum ParseResult: Equatable {
        case incomplete
        case invalid(String)
        case complete(HTTPRequest)
    }

    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 64 * 1024

    /// Parses one HTTP/1.1 request from the bytes received so far.
    public static func parse(_ data: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid("Headers too large") : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid("Headers aren't UTF-8")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid("Bad request line") }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBodyBytes else { return .invalid("Body too large") }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))

        let target = String(requestLine[1])
        var components = URLComponents(string: "http://vox.local" + (target.hasPrefix("/") ? target : "/" + target))
        if components == nil { components = URLComponents() }
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let path = components?.percentEncodedPath ?? "/"
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path.isEmpty ? "/" : path,
                                     query: query, headers: headers, body: body))
    }

    /// The bearer token from `Authorization: Bearer …`, if any.
    public var bearerToken: String? {
        guard let auth = headers["authorization"], auth.hasPrefix("Bearer ") else { return nil }
        let token = auth.dropFirst("Bearer ".count).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    public func json() -> [String: Any] {
        guard !body.isEmpty, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var contentType: String
    public var body: Data
    public var cacheable: Bool

    public init(status: Int, contentType: String, body: Data, cacheable: Bool = false) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.cacheable = cacheable
    }

    public static func json(_ status: Int, _ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: status, contentType: "application/json", body: data)
    }

    public static func encoded<T: Encodable>(_ value: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, contentType: "application/json", body: data)
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(status, ["error": message])
    }

    static let reasons: [Int: String] = [
        200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
        413: "Payload Too Large", 429: "Too Many Requests", 500: "Internal Server Error"
    ]

    /// Same security headers as the Windows agent: no framing, no inline script, same-origin only.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "OK")\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: \(cacheable ? "no-cache" : "no-store")\r\n"
        head += "Content-Security-Policy: default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'\r\n"
        head += "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

// MARK: - Routes

/// What a request asks for. Parsing is separate from doing, so it's testable.
public enum RemoteRoute: Equatable, Sendable {
    case asset(String)
    case ping
    case state(lines: Int)
    case command(text: String, spoken: Bool, fromPhone: Bool)
    case confirm(yes: Bool)
    case exitTool
    case launch(tool: String)
    case kill(tool: String)
    case focus(tool: String)
    case send(tool: String, text: String)
    case type(tool: String, text: String)
    case key(tool: String, key: String)

    /// nil = 404. Text is capped at 4000 characters.
    public static func parse(_ request: HTTPRequest) -> RemoteRoute? {
        let path = request.path
        guard path.hasPrefix("/api/") else {
            guard request.method == "GET" else { return nil }
            let name = path == "/" ? "index.html" : String(path.dropFirst()).removingPercentEncoding ?? ""
            return name.contains("/") || name.contains("..") ? nil : .asset(name)
        }
        let route = String(path.dropFirst("/api/".count))
        if route == "ping" { return .ping }
        if request.method == "GET", route == "state" {
            let lines = Int(request.query["lines"] ?? "") ?? 60
            return .state(lines: max(10, min(400, lines)))
        }
        guard request.method == "POST" else { return nil }
        let body = request.json()
        let text = String((body["text"] as? String ?? "").prefix(4000))
        switch route {
        case "command":
            return .command(text: text, spoken: body["spoken"] as? Bool ?? false, fromPhone: (body["source"] as? String) == "phone")
        case "confirm": return .confirm(yes: body["yes"] as? Bool ?? false)
        case "exit": return .exitTool
        default: break
        }
        let parts = route.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "tools",
              let tool = String(parts[1]).removingPercentEncoding, !tool.isEmpty else { return nil }
        switch parts[2] {
        case "launch": return .launch(tool: tool)
        case "kill": return .kill(tool: tool)
        case "focus": return .focus(tool: tool)
        case "send": return .send(tool: tool, text: text)
        case "type": return .type(tool: tool, text: text)
        case "key": return .key(tool: tool, key: body["key"] as? String ?? "")
        default: return nil
        }
    }

    /// Everything except the web app files and ping needs the pairing code.
    public var needsAuth: Bool {
        switch self {
        case .asset, .ping: return false
        default: return true
        }
    }
}

// MARK: - Pairing

public enum RemotePairing {
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// 20 characters from an unambiguous alphabet (~100 bits).
    public static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<20).map { _ in alphabet[Int(generator.next(upperBound: UInt32(alphabet.count)))] })
    }

    /// Constant-time comparison. Both sides are hashed first so the length doesn't leak.
    public static func matches(_ given: String?, _ expected: String) -> Bool {
        guard let given, !expected.isEmpty else { return false }
        let a = digest(given), b = digest(expected)
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0 && a.count == b.count
    }

    static func digest(_ text: String) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(text.utf8)))
        #else
        // Linux test builds: FNV-1a spread over 32 bytes (still constant-time to compare).
        var out = [UInt8](repeating: 0, count: 32)
        for round in 0..<4 {
            var hash: UInt64 = 0xcbf29ce484222325 &+ UInt64(round)
            for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
            for i in 0..<8 { out[round * 8 + i] = UInt8((hash >> (UInt64(i) * 8)) & 0xff) }
        }
        return out
        #endif
    }
}

/// Too many wrong codes from one address -> 429 for a while. Clock injected for tests.
public struct RemoteLockout: Sendable {
    public var limit: Int
    public var window: TimeInterval
    public var ban: TimeInterval
    private var failures: [String: [Date]] = [:]
    private var bannedUntil: [String: Date] = [:]

    public init(limit: Int = 10, window: TimeInterval = 300, ban: TimeInterval = 60) {
        self.limit = limit
        self.window = window
        self.ban = ban
    }

    public func isBlocked(_ address: String, now: Date = Date()) -> Bool {
        (bannedUntil[address] ?? .distantPast) > now
    }

    public mutating func fail(_ address: String, now: Date = Date()) {
        var times = (failures[address] ?? []).filter { now.timeIntervalSince($0) < window }
        times.append(now)
        if times.count >= limit {
            bannedUntil[address] = now.addingTimeInterval(ban)
            times = []
        }
        failures[address] = times
    }

    public mutating func succeed(_ address: String) {
        failures[address] = nil
        bannedUntil[address] = nil
    }
}

// MARK: - State

/// What GET /api/state returns. Field names are the protocol; keep in sync with windows/src/agent.js.
public struct RemoteState: Codable, Equatable, Sendable {
    public struct Screen: Codable, Equatable, Sendable {
        public var tool: String
        public var text: String
        public var exited: Bool
        public init(tool: String, text: String, exited: Bool) { self.tool = tool; self.text = text; self.exited = exited }
    }
    public struct Item: Codable, Equatable, Sendable {
        public var command: String
        public var kind: String
        public var reply: String
        public var spoken: Bool
        public var source: String
        public init(command: String, kind: String, reply: String, spoken: Bool, source: String) {
            self.command = command; self.kind = kind; self.reply = reply; self.spoken = spoken; self.source = source
        }
    }
    public struct Line: Codable, Equatable, Sendable {
        public var kind: String
        public var text: String
        public var time: String
        public init(kind: String, text: String, time: String) { self.kind = kind; self.text = text; self.time = time }
    }
    public struct Wake: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var name: String
        public init(enabled: Bool, name: String) { self.enabled = enabled; self.name = name }
    }

    public var name = "Vox"
    public var host: String
    public var platform = "mac"
    public var version = 1
    public var lockedTool: String?
    public var pendingQuestion: String?
    public var busy: Bool
    public var wake: Wake
    public var tools: [String]
    public var screens: [Screen]
    public var history: [Item]
    public var log: [Line]

    public init(host: String, lockedTool: String?, pendingQuestion: String?, busy: Bool, wake: Wake,
                tools: [String], screens: [Screen], history: [Item], log: [Line]) {
        self.host = host
        self.lockedTool = lockedTool
        self.pendingQuestion = pendingQuestion
        self.busy = busy
        self.wake = wake
        self.tools = tools
        self.screens = screens
        self.history = history
        self.log = log
    }

    enum CodingKeys: String, CodingKey {
        case name, host, platform, version, lockedTool, pendingQuestion, busy, wake, tools, screens, history, log
    }

    /// Encodes nil as JSON null (the web app checks `state.lockedTool` either way, but keep the shape stable).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host)
        try c.encode(platform, forKey: .platform)
        try c.encode(version, forKey: .version)
        try c.encode(lockedTool, forKey: .lockedTool)
        try c.encode(pendingQuestion, forKey: .pendingQuestion)
        try c.encode(busy, forKey: .busy)
        try c.encode(wake, forKey: .wake)
        try c.encode(tools, forKey: .tools)
        try c.encode(screens, forKey: .screens)
        try c.encode(history, forKey: .history)
        try c.encode(log, forKey: .log)
    }
}

public extension EngineEvent {
    var remoteJSON: [String: String] { ["kind": kind.rawValue, "message": message] }
}

// MARK: - Assets

public enum RemoteAssets {
    static let types: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
        "svg": "image/svg+xml", "webmanifest": "application/manifest+json", "json": "application/json"
    ]

    public static func response(for name: String) -> HTTPResponse {
        guard let base64 = RemoteWebAssets.files[name], let data = Data(base64Encoded: base64) else {
            return .error(404, "Not found")
        }
        let ext = name.split(separator: ".").last.map(String.init) ?? ""
        return HTTPResponse(status: 200, contentType: types[ext] ?? "application/octet-stream", body: data, cacheable: true)
    }
}
