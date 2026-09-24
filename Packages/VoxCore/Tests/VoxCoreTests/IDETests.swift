import XCTest
@testable import VoxCore

final class FakeIDEBridge: IDEBridging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [(IDECommand, String?)] = []
    var reply = IDEReply(ok: true, message: "ok", ide: "Antigravity")

    func perform(_ command: IDECommand, preferring ide: String?, waitSeconds: Double) async throws -> IDEReply {
        record(command, ide)
    }

    private func record(_ command: IDECommand, _ ide: String?) -> IDEReply {
        lock.lock(); defer { lock.unlock() }
        calls.append((command, ide))
        return reply
    }
}

final class IDEParsingTests: XCTestCase {
    let parser = CommandParser(config: .test)

    private func desktop(_ text: String) -> [DesktopCommand]? {
        if case let .desktop(commands, nil) = parser.parse(text) { return commands }
        return nil
    }

    func testTheOwnersExample() {
        XCTAssertEqual(desktop("open Antigravity IDE and open 3 terminals and run claude on one of the terminals"), [
            .openApp("Antigravity IDE"),
            .ide(.openTerminals(count: 3, commands: [])),
            .ide(.send(.any, text: "claude", submit: true))
        ])
    }

    func testOpenTerminals() {
        XCTAssertEqual(desktop("open 3 terminals side by side"), [.ide(.openTerminals(count: 3, commands: []))])
        XCTAssertEqual(desktop("open a new terminal"), [.ide(.openTerminals(count: 1, commands: []))])
        XCTAssertEqual(desktop("create two terminals"), [.ide(.openTerminals(count: 2, commands: []))])
        XCTAssertEqual(desktop("split the terminal into 3"), [.ide(.openTerminals(count: 3, commands: []))])
        XCTAssertEqual(desktop("open 3 terminals running claude, freebuff and npm run dev"),
                       [.ide(.openTerminals(count: 3, commands: ["claude", "freebuff", "npm run dev"]))])
        XCTAssertEqual(desktop("open terminal"), [.openApp("terminal")], "Terminal.app, not an IDE terminal")
    }

    func testOpenAppWithTerminals() {
        XCTAssertEqual(desktop("open antigravity with 3 terminals"), [
            .openApp("antigravity"), .ide(.openTerminals(count: 3, commands: []))
        ])
    }

    func testRunInSpecificTerminals() {
        XCTAssertEqual(desktop("run npm run dev in terminal 2"), [.ide(.send(.number(2), text: "npm run dev", submit: true))])
        XCTAssertEqual(desktop("run freebuff in the second terminal"), [.ide(.send(.number(2), text: "freebuff", submit: true))])
        XCTAssertEqual(desktop("in terminal 3 run npm test"), [.ide(.send(.number(3), text: "npm test", submit: true))])
        XCTAssertEqual(desktop("type hello in terminal two"), [.ide(.send(.number(2), text: "hello", submit: false))])
        XCTAssertEqual(desktop("tell terminal 1 to fix the login bug"),
                       [.ide(.send(.number(1), text: "fix the login bug", submit: true))])
    }

    func testListsWithAndWithoutCommas() {
        let expected: [DesktopCommand] = [
            .ide(.send(.number(1), text: "claude", submit: true)),
            .ide(.send(.number(2), text: "freebuff", submit: true)),
            .ide(.send(.number(3), text: "npm run dev", submit: true))
        ]
        XCTAssertEqual(desktop("run claude in the first, freebuff in the second and npm run dev in the third"), expected)
        XCTAssertEqual(desktop("run claude in the first freebuff in the second and npm run dev in the third"), expected)
    }

    func testFullWorkflowInOneBreath() {
        XCTAssertEqual(
            desktop("open antigravity and open 3 terminals and run claude in the first and freebuff in the second"), [
                .openApp("antigravity"),
                .ide(.openTerminals(count: 3, commands: [])),
                .ide(.send(.number(1), text: "claude", submit: true)),
                .ide(.send(.number(2), text: "freebuff", submit: true))
            ])
    }

    func testThingsThatAreNotIDECommands() {
        XCTAssertEqual(parser.parse("run freebuff in chirp"), .launch(tool: "freebuff", project: "chirp", prompt: nil))
        XCTAssertEqual(parser.parse("run freebuff"), .launch(tool: "freebuff", project: nil, prompt: nil))
        XCTAssertEqual(desktop("type hello world"), [.typeText("hello world")])
        XCTAssertEqual(desktop("start a timer for 5 minutes"), [.timer(seconds: 300)])
        XCTAssertEqual(desktop("close the terminals"), [.ide(.closeTerminals)])
    }

    func testDestructiveTerminalTextNeedsConfirmation() {
        var router = SessionRouter(config: .test)
        guard case .askConfirmation = router.handle("run git push in terminal 2").first else {
            return XCTFail("should ask first")
        }
        XCTAssertEqual(router.handle("yes"), [.desktop(.ide(.send(.number(2), text: "git push", submit: true)))])
    }

    func testIDEChat() {
        XCTAssertEqual(parser.parse("ask antigravity to explain this file"),
                       .desktop([.ide(.chat(message: "explain this file", submit: true))], unparsed: nil))
        XCTAssertEqual(parser.parse("ask kiro to add tests for the daemon"),
                       .desktop([.ide(.chat(message: "add tests for the daemon", submit: true))], unparsed: nil))
        XCTAssertEqual(parser.parse("tell kiro to fix the login bug"),
                       .desktop([.ide(.chat(message: "fix the login bug", submit: true))], unparsed: nil))
        XCTAssertEqual(parser.parse("ask visual studio code to add type hints"),
                       .desktop([.ide(.chat(message: "add type hints", submit: true))], unparsed: nil))
    }

    func testIDEChatIsNotTriggeredForTools() {
        // "claude" is a tool, not an IDE — goes to tell, not chat.
        XCTAssertEqual(parser.parse("ask claude to fix the login bug"),
                       .tell(tool: "claude", text: "fix the login bug"))
        XCTAssertEqual(parser.parse("ask freebuff what this file does"),
                       .tell(tool: "freebuff", text: "what this file does"))
    }

    func testIDEChatBody() {
        let body = HTTPIDEBridge.body(for: .chat(message: "explain this", submit: true), token: "t")
        XCTAssertEqual(body["action"] as? String, "chat")
        XCTAssertEqual(body["message"] as? String, "explain this")
        XCTAssertEqual(body["submit"] as? Bool, true)
    }

    func testIDEResolvedCommands() {
        let body1 = HTTPIDEBridge.body(for: .openFile(path: "src/parser/Tokenizer.swift"), token: "t")
        XCTAssertEqual(body1["action"] as? String, "openFile")
        XCTAssertEqual(body1["path"] as? String, "src/parser/Tokenizer.swift")

        let body2 = HTTPIDEBridge.body(for: .openFolder(path: "chirp"), token: "t")
        XCTAssertEqual(body2["action"] as? String, "openFolder")
        XCTAssertEqual(body2["path"] as? String, "chirp")

        let body3 = HTTPIDEBridge.body(for: .runTask(name: "build"), token: "t")
        XCTAssertEqual(body3["action"] as? String, "runTask")
        XCTAssertEqual(body3["name"] as? String, "build")
    }

    func testIDEResolvedBodySerialization() {
        let body = HTTPIDEBridge.body(for: .chat(message: "hi", submit: false), token: "t")
        XCTAssertEqual(body["action"] as? String, "chat")
        XCTAssertEqual(body["message"] as? String, "hi")
        XCTAssertEqual(body["submit"] as? Bool, false)
    }

    func testPhase5Commands() {
        XCTAssertEqual(parser.parse("read safari tab"),
                       .desktop([.safariReadTab], unparsed: nil))
        XCTAssertEqual(parser.parse("tell claude desktop to explain this file"),
                       .desktop([.sendMessageToApp(app: "claude", text: "explain this file")], unparsed: nil))
        XCTAssertEqual(parser.parse("ask claude desktop what's new in swift 6"),
                       .desktop([.sendMessageToApp(app: "claude", text: "what's new in swift 6")], unparsed: nil))
    }
}

final class ShellTextTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(ShellText.normalize("Npm run dev."), "npm run dev")
        XCTAssertEqual(ShellText.normalize("git commit dash m fix"), "git commit -m fix")
        XCTAssertEqual(ShellText.normalize("npm dash dash version"), "npm --version")
        XCTAssertEqual(ShellText.normalize("cd dot dot slash src"), "cd ../src")
        XCTAssertEqual(ShellText.normalize("cd slash users"), "cd /users")
        XCTAssertEqual(ShellText.normalize("ls src slash app"), "ls src/app")
        XCTAssertEqual(ShellText.normalize("open github dot com"), "open github.com")
        XCTAssertEqual(ShellText.normalize("Flutter run"), "flutter run")
    }
}

final class BridgeDiscoveryTests: XCTestCase {
    func info(_ ide: String, focused: Double, pid: Int32 = ProcessInfo.processInfo.processIdentifier) -> BridgeInfo {
        BridgeInfo(ide: ide, port: 1, token: "t", pid: pid, workspace: nil, focusedAt: focused)
    }

    func testChoose() {
        let bridges = [info("Kiro", focused: 20), info("Antigravity", focused: 10)]
        XCTAssertEqual(HTTPIDEBridge.choose(from: bridges, preferring: nil)?.ide, "Kiro")
        XCTAssertEqual(HTTPIDEBridge.choose(from: bridges, preferring: "Antigravity")?.ide, "Antigravity")
        XCTAssertEqual(HTTPIDEBridge.choose(from: [info("Visual Studio Code", focused: 1)],
                                            preferring: "Visual Studio Code")?.ide, "Visual Studio Code")
        XCTAssertNil(HTTPIDEBridge.choose(from: bridges, preferring: "Cursor"))
    }

    func testCandidatesSkipDeadProcesses() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let me = ProcessInfo.processInfo.processIdentifier
        let alive = #"{"ide":"Antigravity","port":5000,"token":"a","pid":\#(me),"workspace":null,"focusedAt":5}"#
        let dead = #"{"ide":"Kiro","port":5001,"token":"b","pid":999999,"workspace":null,"focusedAt":9}"#
        try alive.write(to: dir.appendingPathComponent("antigravity-1.json"), atomically: true, encoding: .utf8)
        try dead.write(to: dir.appendingPathComponent("kiro-2.json"), atomically: true, encoding: .utf8)
        let found = HTTPIDEBridge(directory: dir).candidates()
        XCTAssertEqual(found.map(\.ide), ["Antigravity"])
    }

    func testRequestBodies() {
        let send = HTTPIDEBridge.body(for: .send(.number(2), text: "ls", submit: true), token: "x")
        XCTAssertEqual(send["action"] as? String, "send")
        XCTAssertEqual(send["terminal"] as? Int, 2)
        XCTAssertEqual(send["token"] as? String, "x")
        let any = HTTPIDEBridge.body(for: .send(.any, text: "ls", submit: false), token: "x")
        XCTAssertTrue(any["terminal"] is NSNull)
        let open = HTTPIDEBridge.body(for: .openTerminals(count: 3, commands: ["claude"]), token: "x")
        XCTAssertEqual(open["count"] as? Int, 3)
    }
}

final class IDEEngineTests: XCTestCase {
    @MainActor
    func testWorkflowPrefersTheIDEJustOpenedAndResolvesToolNames() async {
        let desktop = FakeDesktop()
        let bridge = FakeIDEBridge()
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: desktop, ideBridge: bridge, pause: { _ in })
        let events = await engine.handle("open antigravity and open 3 terminals and run free buff on one of the terminals")
        XCTAssertEqual(events.map(\.kind), [.success, .success, .success])
        XCTAssertEqual(bridge.calls.map { $0.0 }, [
            .openTerminals(count: 3, commands: []),
            .send(.any, text: "freebuff", submit: true)
        ])
        XCTAssertEqual(bridge.calls.map { $0.1 }, ["Antigravity", "Antigravity"])
    }

    @MainActor
    func testShellTextIsCleanedAndErrorsSurface() async {
        let bridge = FakeIDEBridge()
        bridge.reply = IDEReply(ok: false, message: "There is no terminal 9.")
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
                               apps: .test, desktop: FakeDesktop(), ideBridge: bridge, pause: { _ in })
        let events = await engine.handle("run Npm run dev in terminal 9")
        XCTAssertEqual(bridge.calls.first?.0, .send(.number(9), text: "npm run dev", submit: true))
        XCTAssertEqual(events.first?.kind, .warning)
        XCTAssertEqual(events.first?.message, "There is no terminal 9.")
    }
}
