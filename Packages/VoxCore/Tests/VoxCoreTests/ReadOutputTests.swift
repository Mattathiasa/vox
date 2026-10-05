import XCTest
@testable import VoxCore

/// Phase 12.3: "what did claude say".
final class ReadOutputTests: XCTestCase {
    let parser = CommandParser(config: .test)

    static let claudeScreen = """
    > add a test for the tokenizer
    ⏺ I'll look at the tokenizer first.
    ⏺ Read(Sources/VoxCore/Parsing/Tokenizer.swift)
      ⎿  Read 98 lines
    ⏺ Update(Tests/TokenizerTests.swift)
      ⎿  Updated with 12 additions
    ⏺ Added **testApostrophes** to `TokenizerTests`.
      It checks that "what's" becomes whats.
    ╭──────────────────────────────────────────────────╮
    │ >                                                │
    ╰──────────────────────────────────────────────────╯
      ? for shortcuts                       ⧉ In Tokenizer.swift
    """

    func testReadsClaudesLastAnswer() {
        XCTAssertEqual(ScreenReader.lastAnswer(Self.claudeScreen),
                       "Added testApostrophes to TokenizerTests. It checks that \"what's\" becomes whats.")
    }

    func testOtherTools() {
        let gemini = "✦ The build passed.\n  All 12 tests are green.\n\n > Type your message\n"
        XCTAssertEqual(ScreenReader.lastAnswer(gemini), "The build passed. All 12 tests are green.")
        let codex = "• Ran npm test\n• Tests pass. I also fixed a typo in README.\n▌ \n"
        XCTAssertEqual(ScreenReader.lastAnswer(codex), "Tests pass. I also fixed a typo in README.")
        let plain = "$ ls\nfoo bar\n$ echo hi\nhi\n"
        XCTAssertEqual(ScreenReader.lastAnswer(plain), "$ ls foo bar $ echo hi hi", "no markers: the last lines")
        XCTAssertEqual(ScreenReader.lastAnswer(""), "")
    }

    func testLongAnswersAreCutAtASentence() {
        let long = "⏺ " + String(repeating: "This is a sentence. ", count: 100)
        let text = ScreenReader.lastAnswer(long, maxCharacters: 100)
        XCTAssertTrue(text.hasSuffix("sentence. …"), text)
        XCTAssertLessThanOrEqual(text.count, 102)
    }

    func testPhrases() {
        XCTAssertEqual(parser.readRequest("what did it say"), ReadRequest(tool: nil))
        XCTAssertEqual(parser.readRequest("read the last answer"), ReadRequest(tool: nil))
        XCTAssertEqual(parser.readRequest("what did claude say")?.tool, "claude")
        XCTAssertEqual(parser.readRequest("what's free buff saying")?.tool, "freebuff")
        XCTAssertEqual(parser.readRequest("read claude")?.tool, "claude")
        XCTAssertEqual(parser.readRequest("read the last answer from claude code")?.tool, "claude")
        XCTAssertEqual(parser.readRequest("read claude's answer")?.tool, nil, "possessive isn't a tool name")
        XCTAssertNil(parser.readRequest("read the readme"))
        XCTAssertNil(parser.readRequest("what did we change in the router"))
        XCTAssertNil(parser.readRequest("read claude the docs"))
    }

    func testRouting() {
        var router = SessionRouter(config: .test)
        XCTAssertEqual(router.handle("what did claude say"), [.readOutput(tool: "claude")])
        guard case let .feedback(message)? = router.handle("what did it say").first else { return XCTFail() }
        XCTAssertTrue(message.hasPrefix("Not talking to any tool"))
        XCTAssertEqual(router.handle("read clipboard"), [.desktop(.answer(.clipboard))], "unchanged")
        _ = router.handle("run claude")
        XCTAssertEqual(router.handle("what did it say"), [.readOutput(tool: "claude")], "not sent to claude as a prompt")
        XCTAssertEqual(router.handle("read the readme"), [.send(tool: "claude", text: "read the readme")])
    }

    func testEngineReadsTheScreen() async {
        let runner = FakeTmuxRunner()
        runner.sessions = ["vox-claude"]
        runner.screen = Self.claudeScreen
        let engine = VoxEngine(config: .test, tmux: TmuxAdapter(tmuxPath: "tmux", runner: runner), pause: { _ in })
        let events = await engine.handle("what did claude say")
        XCTAssertEqual(events.first?.message, "claude says: Added testApostrophes to TokenizerTests. It checks that \"what's\" becomes whats.")
        XCTAssertEqual(events.first?.readAloud, true)
        XCTAssertEqual(events.first?.remoteJSON["readAloud"], "true", "the phone reads it out in full too")
        runner.screen = ""
        let empty = await engine.handle("read claude")
        XCTAssertEqual(empty.first?.message, "claude hasn't said anything yet.")
        let missing = await engine.handle("what did freebuff say")
        XCTAssertEqual(missing.first?.kind, .warning)
    }
}
