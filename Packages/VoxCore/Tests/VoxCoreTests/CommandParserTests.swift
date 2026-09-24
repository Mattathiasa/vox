import XCTest
@testable import VoxCore

final class CommandParserTests: XCTestCase {
    let parser = CommandParser(config: .test)

    func testLaunchPlain() {
        XCTAssertEqual(parser.parse("run freebuff"), .launch(tool: "freebuff", project: nil, prompt: nil))
    }

    func testLaunchByAlias() {
        XCTAssertEqual(parser.parse("Start free buff."), .launch(tool: "freebuff", project: nil, prompt: nil))
    }

    func testLaunchWithProjectAndPrompt() {
        XCTAssertEqual(
            parser.parse("run freebuff in the chirp project and add tests for the daemon"),
            .launch(tool: "freebuff", project: "chirp", prompt: "add tests for the daemon"))
    }

    func testLaunchPromptKeepsOriginalCasing() {
        XCTAssertEqual(
            parser.parse("open claude code and tell it to rename getUser to fetchUser"),
            .launch(tool: "claude", project: nil, prompt: "rename getUser to fetchUser"))
    }

    func testLaunchWithMultiWordProjectAlias() {
        XCTAssertEqual(
            parser.parse("launch claude on bible study"),
            .launch(tool: "claude", project: "cbs", prompt: nil))
    }

    func testUnknownProjectIsRefused() {
        XCTAssertEqual(parser.parse("run freebuff in lehulu"), .unknownProject(spoken: "lehulu"))
    }

    func testPrefixAndFillersAreSkipped() {
        XCTAssertEqual(parser.parse("hey vox, please run freebuff"),
                       .launch(tool: "freebuff", project: nil, prompt: nil))
    }

    func testFocus() {
        XCTAssertEqual(parser.parse("switch to claude"), .focus(tool: "claude"))
        XCTAssertEqual(parser.parse("claude code"), .focus(tool: "claude"))
    }

    func testKill() {
        XCTAssertEqual(parser.parse("kill the freebuff"), .kill(tool: "freebuff"))
        XCTAssertEqual(parser.parse("shut down claude"), .kill(tool: "claude"))
    }

    func testUnknownTool() {
        XCTAssertEqual(parser.parse("run htop"), .unknownTool(spoken: "htop"))
    }

    func testList() {
        XCTAssertEqual(parser.parse("What's running?"), .listSessions)
        XCTAssertEqual(parser.parse("list sessions"), .listSessions)
    }

    func testExitIsWholeUtteranceOnly() {
        XCTAssertTrue(parser.isExit("Exit."))
        XCTAssertTrue(parser.isExit("that's all"))
        XCTAssertFalse(parser.isExit("exit early if the list is empty"))
    }

    func testStopListeningIsExitNotKill() {
        XCTAssertEqual(parser.parse("stop listening"), .exit)
    }

    func testAffirmative() {
        XCTAssertTrue(parser.isAffirmative("Yes."))
        XCTAssertTrue(parser.isAffirmative("go ahead"))
        XCTAssertFalse(parser.isAffirmative("yes but only on staging"))
        XCTAssertFalse(parser.isAffirmative("no"))
    }

    func testStrippingPrefix() {
        XCTAssertEqual(parser.strippingPrefix("Vox, switch to claude"), "switch to claude")
        XCTAssertEqual(parser.strippingPrefix("hey vox"), "")
        XCTAssertNil(parser.strippingPrefix("fix the voxel renderer"))
    }

    func testGibberishIsUnknown() {
        XCTAssertEqual(parser.parse("the weather is nice"), .unknown)
        XCTAssertEqual(parser.parse("   "), .unknown)
    }
}
