import XCTest
@testable import VoxCore

final class TerminalInputTests: XCTestCase {
    func testTellParsing() {
        let parser = CommandParser(config: .test)
        XCTAssertEqual(parser.parse("tell claude to fix the login bug"), .tell(tool: "claude", text: "fix the login bug"))
        XCTAssertEqual(parser.parse("ask free buff what this repo does"), .tell(tool: "freebuff", text: "what this repo does"))
        XCTAssertEqual(parser.parse("tell terminal 1 to run tests"),
                       .desktop([.ide(.send(.number(1), text: "run tests", submit: true))], unparsed: nil))
    }

    func testTellDoesNotSwitchTools() {
        var router = SessionRouter(config: .test)
        _ = router.handle("run freebuff")
        XCTAssertEqual(router.handle("vox tell claude to add tests"), [.send(tool: "claude", text: "add tests")])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testSendToChecksSafetyAndConfig() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.sendTo(tool: "claude", text: "  explain main.swift "), [.send(tool: "claude", text: "explain main.swift")])
        XCTAssertEqual(router.sendTo(tool: "claude", text: "   "), [])
        XCTAssertEqual(router.sendTo(tool: "nano", text: "hi"), [.feedback("nano is not in your config.")])
        guard case .askConfirmation = router.sendTo(tool: "claude", text: "git push").first else { return XCTFail() }
        XCTAssertEqual(router.handle("yes"), [.send(tool: "claude", text: "git push")])
    }

    func testEngineSendAndKeys() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        _ = await engine.send("add tests", toTool: "claude")
        XCTAssertEqual(runner.typed["vox-claude"], ["add tests"])
        let mode = await engine.mode
        XCTAssertEqual(mode, .idle, "sending from a tile doesn't lock")

        _ = await engine.press("C-c", inTool: "claude")
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-claude:", "C-c"])
        let refused = await engine.press("rm -rf", inTool: "claude")
        XCTAssertEqual(refused.first?.kind, .error)
        let missing = await engine.press("Enter", inTool: "kilo")
        XCTAssertEqual(missing.first?.kind, .warning)
    }
}
