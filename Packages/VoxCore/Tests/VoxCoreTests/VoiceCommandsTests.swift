import Foundation
import XCTest
@testable import VoxCore

/// Data-driven test: loads real voice-to-text transcripts from
/// `Tests/Fixtures/commands.json` and verifies that the parser/router
/// produce the expected Intent (idle) or RouterAction (locked mode).
///
/// This is the Phase 3 "voice test set." Add misheard phrasings here as you
/// discover them; this test catches parser regressions.
final class VoiceCommandsTests: XCTestCase {
    private static let cases: [VoiceCase] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("commands.json")
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Envelope.self, from: data).cases
    }()

    // MARK: Idle mode — CommandParser.parse → Intent

    func testIdleIntents() {
        let parser = CommandParser(config: .test)
        for c in Self.cases where c.mode == "idle" {
            let intent = parser.parse(c.voice)
            XCTAssertEqual(String(describing: intent), c.expect, "voice: “\(c.voice)”")
        }
    }

    // MARK: Locked mode — SessionRouter.handle → RouterAction

    func testLockedModeActions() {
        for c in Self.cases where c.mode != "idle" {
            let tool = c.mode
                .replacingOccurrences(of: "locked(", with: "")
                .replacingOccurrences(of: ")", with: "")
            var router = SessionRouter(config: .test)
            // Enter locked(tool) mode by launching the tool.
            _ = router.handle("run \(tool)")

            let actions = router.handle(c.voice)
            XCTAssertEqual(String(describing: actions), c.expect,
                           "voice: “\(c.voice)” in locked(\(tool))")
        }
    }

    // MARK: Fixtures

    private struct Envelope: Decodable {
        let cases: [VoiceCase]
    }

    private struct VoiceCase: Decodable {
        let voice: String
        let mode: String
        let expect: String
    }
}
