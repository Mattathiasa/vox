import XCTest
@testable import VoxCore

final class VoxEngineTests: XCTestCase {
    var runner: FakeTmuxRunner!
    var engine: VoxEngine!

    override func setUp() {
        runner = FakeTmuxRunner()
        let tmux = TmuxAdapter(tmuxPath: "tmux", runner: runner)
        engine = VoxEngine(config: .test, tmux: tmux, pause: { _ in })
    }

    func testLaunchThenPassThrough() async {
        let started = await engine.handle("run freebuff in chirp")
        XCTAssertEqual(started.first?.kind, .success)
        XCTAssertTrue(runner.sessions.contains("vox-freebuff"))
        let mode = await engine.mode
        XCTAssertEqual(mode, .locked(tool: "freebuff"))

        _ = await engine.handle("add a retry to the websocket client")
        XCTAssertEqual(runner.typed["vox-freebuff"], ["add a retry to the websocket client"])
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-freebuff:", "Enter"])
    }

    func testLaunchWithInitialPromptSendsIt() async {
        _ = await engine.handle("run freebuff and add dark mode")
        XCTAssertEqual(runner.typed["vox-freebuff"], ["add dark mode"])
    }

    func testRunningToolIsReusedNotRestarted() async {
        runner.sessions = ["vox-freebuff"]
        let events = await engine.handle("run freebuff")
        XCTAssertEqual(events.first?.kind, .info)
        XCTAssertFalse(runner.commands().contains("new-session"))
    }

    func testDeadPaneIsReplacedOnLaunch() async {
        runner.sessions = ["vox-freebuff"]
        runner.deadPanes = ["vox-freebuff"]
        _ = await engine.handle("run freebuff")
        XCTAssertTrue(runner.commands().contains("kill-session"))
        XCTAssertTrue(runner.commands().contains("new-session"))
    }

    func testFailedLaunchUnlocks() async {
        runner.failNewSession = true
        let events = await engine.handle("run freebuff")
        XCTAssertEqual(events.first?.kind, .error)
        let mode = await engine.mode
        XCTAssertEqual(mode, .idle)
    }

    func testSendingToExitedToolUnlocks() async {
        _ = await engine.handle("run freebuff")
        runner.deadPanes = ["vox-freebuff"]
        let events = await engine.handle("hello?")
        XCTAssertEqual(events.first?.kind, .error)
        let mode = await engine.mode
        XCTAssertEqual(mode, .idle)
    }

    func testFocusOnStoppedToolWarnsAndUnlocks() async {
        let events = await engine.handle("switch to claude")
        XCTAssertEqual(events.first?.kind, .warning)
        let mode = await engine.mode
        XCTAssertEqual(mode, .idle)
    }

    func testConfirmationFlow() async {
        _ = await engine.handle("run freebuff")
        let asked = await engine.handle("push to main")
        XCTAssertEqual(asked.first?.kind, .confirm)
        XCTAssertNil(runner.typed["vox-freebuff"], "nothing typed before confirmation")
        _ = await engine.handle("yes")
        XCTAssertEqual(runner.typed["vox-freebuff"], ["push to main"])
    }

    func testListSessions() async {
        runner.sessions = ["vox-claude", "vox-freebuff"]
        let events = await engine.handle("what's running")
        XCTAssertEqual(events.first?.message, "Running: claude, freebuff")
    }
}

final class SessionScreenTests: XCTestCase {
    func testTidy() {
        XCTAssertEqual(VoxEngine.tidy("hello   \nworld  \n   \n\n"), "hello\nworld")
    }

    func testScreensListsEveryToolButNotSelfTest() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude", "vox-freebuff", "vox-selftest-shell"]
        runner.deadPanes = ["vox-freebuff"]
        runner.screen = "ready   \n\n"
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let screens = await engine.screens()
        XCTAssertEqual(screens, [
            SessionScreen(tool: "claude", text: "ready", exited: false),
            SessionScreen(tool: "freebuff", text: "ready", exited: true)
        ])
    }
}

final class TerminalFitTests: XCTestCase {
    func testSizeFromPointsAndClamping() {
        XCTAssertEqual(TerminalSize(width: 602, height: 250, cellWidth: 6.02, cellHeight: 12.5),
                       TerminalSize(columns: 100, rows: 20))
        XCTAssertEqual(TerminalSize(columns: 5, rows: 2).clamped, TerminalSize(columns: 40, rows: 10))
        XCTAssertEqual(TerminalSize(columns: 999, rows: 999).clamped, TerminalSize(columns: 300, rows: 120))
    }

    func testFitResizesOnlyOnChangeAndSkipsSelfTest() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude", "vox-kilo", "vox-selftest-shell"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let first = await engine.fitTerminals(to: TerminalSize(columns: 90, rows: 30))
        XCTAssertEqual(first, 2)
        let again = await engine.fitTerminals(to: TerminalSize(columns: 90, rows: 30))
        XCTAssertEqual(again, 0)
        let resized = runner.calls.filter { $0.first == "resize-window" }
        XCTAssertEqual(resized.count, 2)
        XCTAssertEqual(resized.first, ["resize-window", "-t", "vox-claude:", "-x", "90", "-y", "30"])
    }
}
