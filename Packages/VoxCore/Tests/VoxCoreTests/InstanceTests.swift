import XCTest
@testable import VoxCore

/// Phase 12.4: several sessions of one tool, one per project.
final class InstanceTests: XCTestCase {
    var runner: FakeTmuxRunner!
    var engine: VoxEngine!

    override func setUp() {
        runner = FakeTmuxRunner()
        engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
    }

    func testSessionNames() {
        XCTAssertEqual(SessionNaming.sessionName(forTool: "claude@chirp"), "vox-claude--chirp")
        XCTAssertEqual(SessionNaming.sessionName(forTool: "Free Buff@My App"), "vox-free-buff--my-app")
        XCTAssertEqual(SessionNaming.sessionName(forTool: "free--buff"), "vox-free-buff", "a name can't fake the separator")
        XCTAssertEqual(SessionNaming.instance(fromSession: "vox-claude--chirp"), "claude@chirp")
        XCTAssertEqual(SessionNaming.instance(fromSession: "vox-claude"), "claude")
        XCTAssertEqual(InstanceName.spoken("claude@chirp"), "claude in chirp")
        XCTAssertEqual(InstanceName.tool("claude@chirp"), "claude")
        XCTAssertEqual(InstanceName.project("claude"), nil)
    }

    func testGrammar() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("switch to claude in chirp"), [.focus(tool: "claude@chirp")])
        XCTAssertEqual(router.handle("vox claude in the chip project"), [.focus(tool: "claude@chirp")], "alias + noun")
        XCTAssertEqual(router.handle("vox tell claude in chirp to add tests"), [.send(tool: "claude@chirp", text: "add tests")])
        XCTAssertEqual(router.handle("vox what did claude in chirp say"), [.readOutput(tool: "claude@chirp")])
        XCTAssertEqual(router.handle("vox approve claude in chirp"), [.keys(tool: "claude@chirp", keys: ["1"])])
        XCTAssertEqual(router.handle("vox press escape in claude in chirp"), [.keys(tool: "claude@chirp", keys: ["Escape"])])
        XCTAssertEqual(router.handle("vox interrupt claude in chirp"), [.interrupt(tool: "claude@chirp")])
        XCTAssertEqual(router.handle("vox tell claude in detail to explain"), [.send(tool: "claude", text: "in detail to explain")],
                       "not a project: left as text, like before")
        guard case .askConfirmation? = router.handle("vox restart claude in chirp").first else { return XCTFail() }
        XCTAssertEqual(router.handle("yes"), [.kill(tool: "claude@chirp"),
                                              .launch(tool: "claude@chirp", directory: "~/Projects/chirp", initialPrompt: nil)])
        guard case .askConfirmation? = router.handle("vox kill claude in chirp").first else { return XCTFail() }
        XCTAssertEqual(router.handle("yes"), [.kill(tool: "claude@chirp")])
    }

    func testTwoProjectsRunSideBySide() async {
        _ = await engine.handle("run claude in chirp")
        _ = await engine.handle("exit")
        let second = await engine.handle("run claude in cbs")
        XCTAssertEqual(second.first?.kind, .success, "a second session, not 'already running'")
        XCTAssertEqual(runner.sessions, ["vox-claude--chirp", "vox-claude--cbs"])
        let screens = await engine.screens()
        XCTAssertEqual(Set(screens.map(\.tool)), ["claude@chirp", "claude@cbs"])

        _ = await engine.handle("exit")
        let which = await engine.handle("switch to claude")
        XCTAssertEqual(which.first?.message, "claude is running in cbs and chirp. Say \"claude in cbs\" to pick one.")
        let idle = await engine.mode
        XCTAssertEqual(idle, .idle, "never guess")

        _ = await engine.handle("claude in cbs")
        _ = await engine.handle("fix the flaky test")
        XCTAssertEqual(runner.typed["vox-claude--cbs"], ["fix the flaky test"])
        XCTAssertNil(runner.typed["vox-claude--chirp"])
    }

    func testBareNameFindsTheOnlySession() async {
        _ = await engine.handle("run claude in chirp")
        _ = await engine.handle("exit")
        let focus = await engine.handle("switch to claude")
        XCTAssertEqual(focus.first?.message, "Talking to claude in chirp. Say \"exit\" to stop.")
        let mode = await engine.mode
        XCTAssertEqual(mode, .locked(tool: "claude@chirp"), "locked to the real session")
        _ = await engine.handle("vox tell claude to run the tests")
        XCTAssertEqual(runner.typed["vox-claude--chirp"], ["run the tests"])
        let sent = await engine.send("hello", toTool: "claude@chirp")
        XCTAssertEqual(sent.first?.message, "→ claude in chirp: hello", "the HUD/phone use the instance name")
        _ = await engine.handle("vox kill claude")
        let killed = await engine.handle("yes")
        XCTAssertEqual(killed.first?.message, "Killed claude in chirp.")
        let after = await engine.mode
        XCTAssertEqual(after, .idle)
    }

    func testDefaultSessionWinsForTheBareName() async {
        _ = await engine.handle("run claude")
        _ = await engine.handle("vox run claude in chirp")
        _ = await engine.handle("vox switch to claude")
        let mode = await engine.mode
        XCTAssertEqual(mode, .locked(tool: "claude"))
        _ = await engine.handle("hi")
        XCTAssertEqual(runner.typed["vox-claude"], ["hi"])
        let list = await engine.handle("vox what's running")
        XCTAssertEqual(list.first?.message, "Running: claude, claude in chirp")
    }

    func testAttentionUsesTheToolsPatterns() async {
        var config = VoxConfig.test
        config.tools[1].approvalPatterns = ["[y/n]"]
        let engine = VoxEngine(config: config, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        runner.sessions = ["vox-claude--chirp"]
        runner.screen = "Overwrite? [y/N]"
        let alerts = await engine.checkAttention()
        XCTAssertEqual(alerts.map(\.message), ["claude in chirp needs your approval."])
    }
}
