import XCTest
@testable import VoxCore

/// Phase 12.1: knowing when a tool needs you.
final class AttentionTests: XCTestCase {
    // Trimmed from real screens.
    static let claudeApproval = """
    ⏺ Bash(rm -rf build)
    ╭──────────────────────────────────────────╮
    │ Bash command                             │
    │   rm -rf build                           │
    │ Do you want to proceed?                  │
    │ ❯ 1. Yes                                 │
    │   2. Yes, and don't ask again            │
    │   3. No, and tell Claude what to do (esc)│
    ╰──────────────────────────────────────────╯
    """
    static let claudeWorking = """
    > add tests for the parser
    ✻ Pondering… (12s · ↑ 1.2k tokens · esc to interrupt)
    ╭──────────────────────────────────────────╮
    │ >                                        │
    ╰──────────────────────────────────────────╯
    """
    static let claudeIdle = """
    ⏺ Added 4 tests. All pass.
    ╭──────────────────────────────────────────╮
    │ >                                        │
    ╰──────────────────────────────────────────╯
      ? for shortcuts
    """

    func testClassifiesScreens() {
        XCTAssertEqual(ActivityDetector.classify(screen: Self.claudeApproval, exited: false), .needsApproval)
        XCTAssertEqual(ActivityDetector.classify(screen: Self.claudeWorking, exited: false), .working)
        XCTAssertEqual(ActivityDetector.classify(screen: Self.claudeIdle, exited: false), .idle)
        XCTAssertEqual(ActivityDetector.classify(screen: Self.claudeWorking, exited: true), .exited)
        XCTAssertEqual(ActivityDetector.classify(screen: "Would you like to run the following command?\n$ npm test", exited: false),
                       .needsApproval, "Codex")
        XCTAssertEqual(ActivityDetector.classify(screen: "⠋ Thinking (esc to cancel, 3s)", exited: false), .working, "Gemini")
    }

    func testOnlyTheBottomOfTheScreenCounts() {
        let old = "Do you want to proceed?\n" + String(repeating: "output line\n", count: 40)
        XCTAssertEqual(ActivityDetector.classify(screen: old, exited: false), .idle, "an answered prompt that scrolled up")
    }

    func testCustomPatterns() {
        let patterns = AttentionPatterns(approval: ["[y/n]"], busy: ["spinning"])
        XCTAssertEqual(ActivityDetector.classify(screen: "Overwrite? [Y/n]", exited: false, patterns: patterns), .needsApproval)
        XCTAssertEqual(ActivityDetector.classify(screen: "spinning...", exited: false, patterns: patterns), .working)
        XCTAssertEqual(ActivityDetector.classify(screen: "Do you want to proceed?", exited: false, patterns: patterns), .idle)
    }

    func testTrackerAlertsOncePerChange() {
        var tracker = AttentionTracker()
        XCTAssertNil(tracker.update(tool: "claude", activity: .idle), "just started")
        XCTAssertNil(tracker.update(tool: "claude", activity: .working))
        XCTAssertEqual(tracker.update(tool: "claude", activity: .needsApproval)?.message, "claude needs your approval.")
        XCTAssertNil(tracker.update(tool: "claude", activity: .needsApproval), "no repeat while it waits")
        XCTAssertNil(tracker.update(tool: "claude", activity: .working))
        XCTAssertNil(tracker.update(tool: "claude", activity: .idle), "the busy line flickers between steps")
        XCTAssertEqual(tracker.update(tool: "claude", activity: .idle)?.message, "claude is done.")
        XCTAssertNil(tracker.update(tool: "claude", activity: .idle), "said once")
        XCTAssertEqual(tracker.update(tool: "claude", activity: .exited)?.message, "claude exited.")
        XCTAssertNil(tracker.update(tool: "claude", activity: .exited))
    }

    func testTrackerFlickerAndFirstSight() {
        var tracker = AttentionTracker()
        XCTAssertEqual(tracker.update(tool: "codex", activity: .needsApproval)?.activity, .needsApproval,
                       "already waiting when Vox started: still worth saying")
        XCTAssertNil(tracker.update(tool: "gemini", activity: .exited), "found dead: nothing changed")
        _ = tracker.update(tool: "claude", activity: .working)
        XCTAssertNil(tracker.update(tool: "claude", activity: .idle))
        XCTAssertNil(tracker.update(tool: "claude", activity: .working), "flicker resets the count")
        XCTAssertNil(tracker.update(tool: "claude", activity: .idle))
        XCTAssertNotNil(tracker.update(tool: "claude", activity: .idle))
        XCTAssertEqual(tracker.update(tool: "claude@chirp", activity: .needsApproval)?.message,
                       "claude in chirp needs your approval.")
    }

    func testTrackerForgetsStoppedTools() {
        var tracker = AttentionTracker()
        _ = tracker.update(tool: "claude", activity: .needsApproval)
        tracker.keep(only: [])
        XCTAssertNil(tracker.activity(of: "claude"))
        XCTAssertNotNil(tracker.update(tool: "claude", activity: .needsApproval), "a new session asking again")
    }

    func testEngineChecksRunningTools() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude"]
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        runner.screen = Self.claudeWorking
        let first = await engine.checkAttention()
        XCTAssertEqual(first, [])
        runner.screen = Self.claudeApproval
        let approval = await engine.checkAttention()
        XCTAssertEqual(approval.map(\.message), ["claude needs your approval."])
        let screens = await engine.screens()
        XCTAssertEqual(screens.first?.activity, .needsApproval, "the HUD and the phone see it too")

        var quiet = VoxConfig.test
        quiet.attentionAlerts = false
        let silent = VoxEngine(config: quiet, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let none = await silent.checkAttention()
        XCTAssertEqual(none, [])
    }

    func testConfigFields() throws {
        let json = #"{"tools":[{"name":"aider","command":"aider","approvalPatterns":["(Y)es/(N)o"]}],"attentionAlerts":false}"#
        let config = try JSONDecoder().decode(VoxConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.tools.first?.approvalPatterns, ["(Y)es/(N)o"])
        XCTAssertNil(config.tools.first?.busyPatterns)
        XCTAssertFalse(config.attentionAlerts)
        let old = try JSONDecoder().decode(VoxConfig.self, from: Data(#"{"tools":[]}"#.utf8))
        XCTAssertTrue(old.attentionAlerts, "on by default for existing configs")
        let patterns = AttentionPatterns.forTool(config.tools.first)
        XCTAssertEqual(patterns.approval, ["(Y)es/(N)o"])
        XCTAssertEqual(patterns.busy, AttentionPatterns.defaultBusy)
    }
}
