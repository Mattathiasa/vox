import XCTest
@testable import VoxCore

final class LLMFallbackTests: XCTestCase {
    let config = VoxConfig.test

    private func makeEngine(llm: (any LLMFallback)? = nil, timeout: Double = 8) -> VoxEngine {
        VoxEngine(
            config: config,
            tmux: TmuxAdapter(tmuxPath: "tmux", runner: FakeTmuxRunner()),
            llm: llm,
            llmTimeoutSeconds: timeout,
            pause: { _ in }
        )
    }

    func testUnknownRoutesToLLM() async {
        let llm = FakeLLM(results: [.command("list")])
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("make me a sandwich")
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].message.contains("LLM"))
        XCTAssertTrue(events[1].message.contains("No tools running") ||
                       events[1].message.contains("Running:"))
    }

    func testLLMNoProviderGivesFeedback() async {
        let engine = makeEngine(llm: nil)
        let events = await engine.handle("make me a sandwich")
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0].message.contains("Didn't catch a command"))
    }

    func testLLMReturnsFeedback() async {
        let llm = FakeLLM(results: [.feedback("I really can't help with that.")])
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("make me a sandwich")
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].message, "I really can't help with that.")
    }

    func testLLMRoutesToUnknownTool() async {
        let llm = FakeLLM(results: [.command("run htop")])
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("check system health")
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[1].message.contains("No tool called") &&
                       events[1].message.contains("in your config"))
    }

    func testLLMErrorHandledGracefully() async {
        let llm = FakeLLM(throwError: LLMTestError.boom)
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("do something weird")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .error)
        XCTAssertTrue(events[0].message.contains("LLM fallback failed"))
    }

    func testLLMTimeoutReturnsFriendlyMessage() async {
        let slowLLM = SlowFakeLLM(delay: 5, result: .command("list"))
        let engine = makeEngine(llm: slowLLM, timeout: 0.1)
        let events = await engine.handle("something complex")
        let hasTimeout = events.contains { $0.message.contains("too long") }
        XCTAssertTrue(hasTimeout, "Expected a timeout message, got: \(events)")
    }

    func testLLMToolDefinitionsGeneratedFromConfig() {
        var router = SessionRouter(config: config)
        let actions = router.handle("something unknown")
        guard case .llmFallback(let request) = actions.first else {
            return XCTFail("expected .llmFallback")
        }
        XCTAssertEqual(request.tools.count, 2)
        XCTAssertEqual(request.tools[0].name, "freebuff")
        XCTAssertEqual(request.tools[0].spokenPhrases, ["freebuff", "free buff", "freebuf"])
        XCTAssertEqual(request.tools[1].name, "claude")
    }

     func testLLMCoversAllToolConfigPhrases() {
        let testConfig = VoxConfig(
            tools: [
                ToolConfig(name: "mytool", aliases: ["my tool", "mt"], command: "mytool")
            ], projects: [])
        var router = SessionRouter(config: testConfig)
        let actions = router.handle("unknown thing")
        guard case .llmFallback(let request) = actions.first else {
            return XCTFail("expected .llmFallback")
        }
        XCTAssertEqual(request.tools.first?.spokenPhrases, ["mytool", "my tool", "mt"])
    }

    /// Security: the LLM returning shell-like text must not execute it.
    /// The command goes through the parser, which only recognizes Vox commands.
    func testLLMSearchDoesNotProduceShell() async {
        let llm = FakeLLM(results: [.command("rm -rf /Users")])
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("delete everything")
        XCTAssertTrue(events.contains { $0.message.contains("Didn't catch a command") })
    }

    /// Security: the LLM returning a command naming an unknown tool is refused.
    func testLLMUnknownToolFromCommandIsRefused() async {
        let llm = FakeLLM(results: [.command("run htop")])
        let engine = makeEngine(llm: llm)
        let events = await engine.handle("show processes")
        XCTAssertTrue(events.contains { $0.message.contains("No tool called") && $0.message.contains("in your config") })
    }

    // MARK: LLMAdapter tests

    func testParseLLMOutputCommand() {
        XCTAssertEqual(LLMAdapter.parseLLMOutput("list"), .command("list"))
    }

    func testParseLLMOutputFeedback() {
        XCTAssertEqual(LLMAdapter.parseLLMOutput("Feedback: I don't know"),
                       .feedback("I don't know"))
    }

    func testParseLLMOutputCaseInsensitiveFeedback() {
        XCTAssertEqual(LLMAdapter.parseLLMOutput("feedback: lower case"),
                       .feedback("lower case"))
    }

    func testParseLLMOutputFirstLineOnly() {
        let output = """
        run claude in vox
        some trailing junk
        """
        XCTAssertEqual(LLMAdapter.parseLLMOutput(output), .command("run claude in vox"))
    }

    func testLLMAdapterDisabledReturnsFeedback() async throws {
        let adapter = LLMAdapter(config: LLMConfig(enabled: false), apiKey: nil)
        let request = LLMRequest(text: "test", tools: [], instruction: "")
        let result = try await adapter.plan(request: request)
        XCTAssertEqual(result, .feedback("LLM fallback is not enabled."))
    }

    func testLLMAdapterClaudeNeedsKey() async throws {
        let adapter = LLMAdapter(config: LLMConfig(enabled: true, provider: .claude), apiKey: nil)
        let request = LLMRequest(text: "test", tools: [], instruction: "")
        let result = try await adapter.plan(request: request)
        XCTAssertEqual(result, .feedback("Set your Claude API key in Keychain to enable fallback."))
    }

    func testLLMAdapterAppleFallbackOnOldMac() async throws {
        if #available(macOS 15, *) {
            throw XCTSkip("This test targets pre-macOS-15 behavior")
        }
        let adapter = LLMAdapter(config: LLMConfig(enabled: true, provider: .apple), apiKey: nil)
        let request = LLMRequest(text: "test", tools: [], instruction: "")
        let result = try await adapter.plan(request: request)
        XCTAssertEqual(result, .feedback("On-device LLM requires macOS 15 or later."))
    }
}
