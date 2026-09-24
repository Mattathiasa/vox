import XCTest
@testable import VoxCore

final class RemoteTests: XCTestCase {
    private func request(_ method: String, _ path: String, body: String = "", headers: [String] = []) -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\nHost: vox\r\n"
        for h in headers { head += h + "\r\n" }
        head += "Content-Length: \(body.utf8.count)\r\n\r\n"
        return Data((head + body).utf8)
    }

    private func parsed(_ data: Data) -> HTTPRequest? {
        if case let .complete(r) = HTTPRequest.parse(data) { return r }
        return nil
    }

    func testParsesRequestsIncrementally() throws {
        let full = request("POST", "/api/command", body: #"{"text":"open safari"}"#, headers: ["Authorization: Bearer abc"])
        XCTAssertEqual(HTTPRequest.parse(full.prefix(10)), .incomplete)
        XCTAssertEqual(HTTPRequest.parse(full.dropLast(3)), .incomplete, "body not complete yet")
        let r = try XCTUnwrap(parsed(full))
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/api/command")
        XCTAssertEqual(r.bearerToken, "abc")
        XCTAssertEqual(r.json()["text"] as? String, "open safari")
        let big = Data("POST /x HTTP/1.1\r\nContent-Length: 999999\r\n\r\n".utf8)
        XCTAssertEqual(HTTPRequest.parse(big), .invalid("Body too large"))
    }

    func testRoutes() throws {
        func route(_ method: String, _ path: String, _ body: String = "") -> RemoteRoute? {
            RemoteRoute.parse(parsed(request(method, path, body: body))!)
        }
        XCTAssertEqual(route("GET", "/"), .asset("index.html"))
        XCTAssertEqual(route("GET", "/app.js"), .asset("app.js"))
        XCTAssertNil(route("GET", "/../secret"))
        XCTAssertEqual(route("GET", "/api/state?lines=5000"), .state(lines: 400))
        XCTAssertEqual(route("POST", "/api/command", #"{"text":"run claude","spoken":true,"source":"phone"}"#),
                       .command(text: "run claude", spoken: true, fromPhone: true))
        XCTAssertEqual(route("POST", "/api/tools/claude%20code/send", #"{"text":"fix it"}"#), .send(tool: "claude code", text: "fix it"))
        XCTAssertEqual(route("POST", "/api/tools/kilo/key", #"{"key":"C-c"}"#), .key(tool: "kilo", key: "C-c"))
        XCTAssertEqual(route("POST", "/api/tools/kilo/type", #"{"text":"ls"}"#), .type(tool: "kilo", text: "ls"))
        XCTAssertEqual(route("POST", "/api/confirm", #"{"yes":true}"#), .confirm(yes: true))
        XCTAssertNil(route("GET", "/api/command"), "commands must be POST")
        XCTAssertNil(route("POST", "/api/tools/kilo/format-disk"))
        XCTAssertFalse(RemoteRoute.ping.needsAuth)
        XCTAssertTrue(RemoteRoute.state(lines: 60).needsAuth)
    }

    func testPairingCodes() {
        let code = RemotePairing.newCode()
        XCTAssertEqual(code.count, 20)
        XCTAssertNotEqual(code, RemotePairing.newCode())
        XCTAssertTrue(RemotePairing.matches(code, code))
        XCTAssertFalse(RemotePairing.matches(String(code.dropLast()), code))
        XCTAssertFalse(RemotePairing.matches(nil, code))
        XCTAssertFalse(RemotePairing.matches("", ""), "an empty code never matches")
    }

    func testLockout() {
        var lockout = RemoteLockout(limit: 3, window: 60, ban: 30)
        let t0 = Date(timeIntervalSince1970: 1000)
        lockout.fail("1.2.3.4", now: t0)
        lockout.fail("1.2.3.4", now: t0)
        XCTAssertFalse(lockout.isBlocked("1.2.3.4", now: t0))
        lockout.fail("1.2.3.4", now: t0)
        XCTAssertTrue(lockout.isBlocked("1.2.3.4", now: t0.addingTimeInterval(10)))
        XCTAssertFalse(lockout.isBlocked("5.6.7.8", now: t0))
        XCTAssertFalse(lockout.isBlocked("1.2.3.4", now: t0.addingTimeInterval(31)))
    }

    func testResponsesAndAssets() throws {
        let text = String(decoding: HTTPResponse.json(200, ["ok": true]).serialized(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Security-Policy: default-src 'self'"))
        XCTAssertTrue(text.hasSuffix(#"{"ok":true}"#))
        let index = RemoteAssets.response(for: "index.html")
        XCTAssertEqual(index.status, 200)
        XCTAssertTrue(String(decoding: index.body, as: UTF8.self).contains("Vox Remote"))
        XCTAssertEqual(RemoteAssets.response(for: "app.js").contentType, "text/javascript; charset=utf-8")
        XCTAssertEqual(RemoteAssets.response(for: "nope.txt").status, 404)
    }

    func testStateJSONShape() throws {
        let state = RemoteState(host: "mac", lockedTool: nil, pendingQuestion: "Kill?", busy: false,
                                wake: .init(enabled: true, name: "Balcha"), tools: ["claude"],
                                screens: [.init(tool: "claude", text: "hi", exited: false)], history: [], log: [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertTrue(object["lockedTool"] is NSNull, "nil is sent as null")
        XCTAssertEqual(object["platform"] as? String, "mac")
        XCTAssertEqual(object["pendingQuestion"] as? String, "Kill?")
        XCTAssertEqual((object["screens"] as? [[String: Any]])?.first?["tool"] as? String, "claude")
    }

    func testLiveTypingInEngine() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let events = await engine.type("git st", inTool: "claude")
        XCTAssertEqual(events, [])
        XCTAssertEqual(runner.typed["vox-claude"], ["git st"])
        XCTAssertFalse(runner.calls.contains { $0 == ["send-keys", "-t", "vox-claude:", "Enter"] }, "no Enter")
        _ = await engine.press("BSpace", inTool: "claude")
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-claude:", "BSpace"])
        let missing = await engine.type("x", inTool: "kilo")
        XCTAssertEqual(missing.first?.kind, .warning)
    }
}
