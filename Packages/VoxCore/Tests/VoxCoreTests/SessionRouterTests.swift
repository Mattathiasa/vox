import XCTest
@testable import VoxCore

final class SessionRouterTests: XCTestCase {
    var router = SessionRouter(config: .test)

    override func setUp() {
        router = SessionRouter(config: .test)
    }

    func testLaunchLocksToTool() {
        let actions = router.handle("run freebuff in chirp")
        XCTAssertEqual(actions, [.launch(tool: "freebuff", directory: "~/Projects/chirp", initialPrompt: nil)])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testLaunchUsesToolDefaultDirectory() {
        XCTAssertEqual(router.handle("run freebuff"),
                       [.launch(tool: "freebuff", directory: "~/Projects", initialPrompt: nil)])
    }

    func testLockedTextPassesThroughUntouched() {
        _ = router.handle("run freebuff")
        XCTAssertEqual(router.handle("Refactor the Auth module, keep the API."),
                       [.send(tool: "freebuff", text: "Refactor the Auth module, keep the API.")])
    }

    func testCommandWordsAreNotHijackedWhileLocked() {
        _ = router.handle("run freebuff")
        // Without the prefix this is text for freebuff, not a Vox command.
        XCTAssertEqual(router.handle("switch to the new API client"),
                       [.send(tool: "freebuff", text: "switch to the new API client")])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testPrefixRunsCommandWhileLocked() {
        _ = router.handle("run freebuff")
        _ = router.handle("vox switch to claude")
        XCTAssertEqual(router.mode, .locked(tool: "claude"))
    }

    func testExitPhraseUnlocksWithoutKilling() {
        _ = router.handle("run freebuff")
        let actions = router.handle("done")
        XCTAssertEqual(router.mode, .idle)
        XCTAssertFalse(actions.contains { if case .kill = $0 { return true } else { return false } })
    }

    func testDestructivePassThroughNeedsConfirmation() {
        _ = router.handle("run freebuff")
        let asked = router.handle("commit and push to main")
        guard case .askConfirmation = asked.first else {
            return XCTFail("expected a confirmation question, got \(asked)")
        }
        XCTAssertEqual(router.handle("yes"), [.send(tool: "freebuff", text: "commit and push to main")])
    }

    func testAnythingButYesCancels() {
        _ = router.handle("run freebuff")
        _ = router.handle("delete the old migrations")
        XCTAssertEqual(router.handle("no wait"), [.feedback("Cancelled.")])
        XCTAssertNil(router.pending)
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testDestructiveInitialPromptHoldsTheLaunch() {
        let asked = router.handle("run freebuff and deploy to production")
        guard case .askConfirmation = asked.first else {
            return XCTFail("expected a confirmation question, got \(asked)")
        }
        XCTAssertEqual(router.mode, .idle, "must not lock before confirmation")
        XCTAssertEqual(router.handle("do it"),
                       [.launch(tool: "freebuff", directory: "~/Projects", initialPrompt: "deploy to production")])
        XCTAssertEqual(router.mode, .locked(tool: "freebuff"))
    }

    func testKillAlwaysConfirmsAndUnlocks() {
        _ = router.handle("run freebuff")
        let asked = router.handle("vox kill freebuff")
        guard case .askConfirmation = asked.first else {
            return XCTFail("expected a confirmation question, got \(asked)")
        }
        XCTAssertEqual(router.handle("yes"), [.kill(tool: "freebuff")])
        XCTAssertEqual(router.mode, .idle)
    }

    func testFocusLocks() {
        XCTAssertEqual(router.handle("switch to claude"), [.focus(tool: "claude")])
        XCTAssertEqual(router.mode, .locked(tool: "claude"))
    }

    func testUnknownGivesLLMFallbackAndStaysIdle() {
        let actions = router.handle("make me a sandwich")
        guard case .llmFallback(let request) = actions.first else {
            return XCTFail("expected .llmFallback, got \(actions)")
        }
        XCTAssertEqual(request.text, "make me a sandwich")
        XCTAssertEqual(router.mode, .idle)
    }

    func testEmptyInputDoesNothing() {
        XCTAssertEqual(router.handle("  \n"), [])
    }

    func testUnlockFromEngine() {
        _ = router.handle("run freebuff")
        router.unlock()
        XCTAssertEqual(router.mode, .idle)
    }
}
