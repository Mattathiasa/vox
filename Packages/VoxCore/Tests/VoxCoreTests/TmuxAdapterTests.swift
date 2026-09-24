import XCTest
@testable import VoxCore

final class TmuxAdapterTests: XCTestCase {
    func testSessionNaming() {
        XCTAssertEqual(SessionNaming.sessionName(forTool: "freebuff"), "vox-freebuff")
        XCTAssertEqual(SessionNaming.sessionName(forTool: "Claude Code"), "vox-claude-code")
        XCTAssertEqual(SessionNaming.sessionName(forTool: "a.b:c"), "vox-a-b-c")
    }

    func testStartUsesLoginShellDirectoryAndRemainOnExit() throws {
        let runner = FakeTmuxRunner()
        let tmux = TmuxAdapter(tmuxPath: "/opt/homebrew/bin/tmux", runner: runner)
        try tmux.start(session: "vox-freebuff", command: "freebuff", directory: "/tmp/proj")

        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertEqual(call.first, "new-session")
        XCTAssertTrue(call.contains("-d"))
        XCTAssertEqual(call[call.firstIndex(of: "-c")! + 1], "/tmp/proj")
        let shellIndex = try XCTUnwrap(call.firstIndex(of: "/bin/zsh"))
        XCTAssertEqual(Array(call[shellIndex...shellIndex + 2]), ["/bin/zsh", "-lc", "freebuff"])
        XCTAssertTrue(call.contains(";"))
        XCTAssertTrue(call.contains("remain-on-exit"))
    }

    func testTildeIsExpanded() {
        let expanded = TmuxAdapter.expandTilde("~/Projects/chirp")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/Projects/chirp"))
        XCTAssertEqual(TmuxAdapter.expandTilde("/abs/path"), "/abs/path")
    }

    func testTypeIsLiteral() throws {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-freebuff"]
        let tmux = TmuxAdapter(tmuxPath: "tmux", runner: runner)
        try tmux.type(session: "vox-freebuff", text: "press Enter then C-c")
        XCTAssertEqual(runner.calls.last, ["send-keys", "-t", "vox-freebuff:", "-l", "press Enter then C-c"])
    }

    func testListSessionsOnlyReturnsVoxSessionsAndToleratesNoServer() {
        let runner = FakeTmuxRunner()
        let tmux = TmuxAdapter(tmuxPath: "tmux", runner: runner)
        XCTAssertEqual(tmux.listSessions(), [])
        runner.sessions = ["vox-claude", "vox-freebuff", "scratch"]
        XCTAssertEqual(tmux.listSessions(), ["vox-claude", "vox-freebuff"])
    }

    func testFailureSurfacesStderr() {
        let runner = FakeTmuxRunner()
        runner.failNewSession = true
        let tmux = TmuxAdapter(tmuxPath: "tmux", runner: runner)
        XCTAssertThrowsError(try tmux.start(session: "vox-x", command: "x", directory: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("boom"))
        }
    }
}
