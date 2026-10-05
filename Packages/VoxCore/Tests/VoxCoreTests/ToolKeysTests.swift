import XCTest
@testable import VoxCore

/// Phase 12.2: keys for a running tool by voice.
final class ToolKeysTests: XCTestCase {
    let parser = CommandParser(config: .test)

    func keys(_ text: String) -> [String]? { parser.toolKeys(text)?.keys }

    func testKeyPhrases() {
        XCTAssertEqual(keys("press escape"), ["Escape"])
        XCTAssertEqual(keys("escape"), ["Escape"])
        XCTAssertEqual(keys("hit enter"), ["Enter"])
        XCTAssertEqual(keys("shift tab"), ["BTab"])
        XCTAssertEqual(keys("press tab"), ["Tab"])
        XCTAssertEqual(keys("arrow down"), ["Down"])
        XCTAssertEqual(keys("down arrow twice"), ["Down", "Down"])
        XCTAssertEqual(keys("go up 3 times"), ["Up", "Up", "Up"])
        XCTAssertEqual(keys("move down three times"), ["Down", "Down", "Down"])
        XCTAssertEqual(keys("press down"), ["Down"])
        XCTAssertEqual(keys("press backspace"), ["BSpace"])
        XCTAssertEqual(keys("page up"), ["PPage"])
        XCTAssertEqual(keys("press 3"), ["3"])
    }

    func testAnswers() {
        XCTAssertEqual(parser.toolKeys("approve"), ToolKeyRequest(keys: ["1"], tool: nil, isAnswer: true))
        XCTAssertEqual(keys("allow it"), ["1"])
        XCTAssertEqual(keys("yes, don't ask again"), ["2"])
        XCTAssertEqual(keys("always allow"), ["2"])
        XCTAssertEqual(keys("deny"), ["Escape"])
        XCTAssertEqual(keys("choose option 2"), ["2"])
        XCTAssertEqual(keys("option two"), ["2"])
        XCTAssertEqual(keys("option to"), ["2"], "misheard two")
        XCTAssertEqual(keys("select 3"), ["3"])
        XCTAssertEqual(keys("number one"), ["1"])
    }

    func testNamedTool() {
        XCTAssertEqual(parser.toolKeys("press escape in claude"), ToolKeyRequest(keys: ["Escape"], tool: "claude", isAnswer: false))
        XCTAssertEqual(parser.toolKeys("approve claude")?.tool, "claude")
        XCTAssertEqual(parser.toolKeys("deny for free buff")?.tool, "freebuff")
        XCTAssertEqual(parser.toolKeys("option 2 in claude code")?.tool, "claude")
    }

    func testNotKeys() {
        XCTAssertNil(parser.toolKeys("allow it to use npm"), "a prompt that starts like an answer")
        XCTAssertNil(parser.toolKeys("go back"))
        XCTAssertNil(parser.toolKeys("press command s"))
        XCTAssertNil(parser.toolKeys("escape the html in the template"))
        XCTAssertNil(parser.toolKeys("select all"))
        XCTAssertNil(parser.toolKeys("delete"), "text for the tool, not Backspace")
        XCTAssertNil(parser.toolKeys("press escape in kilo"), "kilo is not in the test config")
    }

    func testWhileTalkingToATool() {
        var router = SessionRouter(config: .test)
        _ = router.handle("run claude")
        XCTAssertEqual(router.handle("press escape"), [.keys(tool: "claude", keys: ["Escape"])])
        XCTAssertEqual(router.handle("approve"), [.keys(tool: "claude", keys: ["1"])])
        XCTAssertEqual(router.handle("shift tab"), [.keys(tool: "claude", keys: ["BTab"])])
        XCTAssertEqual(router.handle("deny in free buff"), [.keys(tool: "freebuff", keys: ["Escape"])])
        XCTAssertEqual(router.handle("fix the login bug"), [.send(tool: "claude", text: "fix the login bug")], "text still goes through")
        XCTAssertEqual(router.handle("vox press escape"), [.desktop(.pressKey(KeyCombo.parse("escape")!))],
                       "the vox prefix means the front app")
        XCTAssertEqual(router.mode, .locked(tool: "claude"), "keys don't change who you're talking to")
    }

    func testWhenIdle() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("approve claude"), [.keys(tool: "claude", keys: ["1"])])
        XCTAssertEqual(router.handle("press escape in claude"), [.keys(tool: "claude", keys: ["Escape"])])
        XCTAssertEqual(router.handle("press escape"), [.desktop(.pressKey(KeyCombo.parse("escape")!))], "front app, as before")
        XCTAssertEqual(router.handle("press 2"), [.desktop(.pressKey(KeyCombo.parse("2")!))], "front app, as before")
        guard case let .feedback(message)? = router.handle("approve").first else { return XCTFail() }
        XCTAssertTrue(message.hasPrefix("Not talking to any tool"))
        XCTAssertEqual(router.mode, .idle)
    }

    func testEngineSendsKeys() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let events = await engine.handle("arrow down twice in claude")
        XCTAssertEqual(events, [EngineEvent(.success, "Pressed Down ×2 in claude.")])
        XCTAssertEqual(runner.calls.suffix(2), [["send-keys", "-t", "vox-claude:", "Down"], ["send-keys", "-t", "vox-claude:", "Down"]])
        _ = await engine.handle("approve claude")
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-claude:", "1"])
        let missing = await engine.handle("deny freebuff")
        XCTAssertEqual(missing.first?.kind, .warning)
    }
}
