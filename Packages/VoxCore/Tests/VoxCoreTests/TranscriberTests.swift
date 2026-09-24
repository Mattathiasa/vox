import XCTest
@testable import VoxCore

/// The `Transcriber` contract is a pure Swift protocol with no Speech-framework
/// dependency, so it is fully testable here in VoxCore.
final class TranscriberTests: XCTestCase {

    func testFakeTranscriberLifecycle() async throws {
        let transcriber = FakeTranscriber(finalText: "hello world")

        // No permissions by default.
        try await transcriber.ensurePermissions()
        transcriber.contextualStrings = ["freebuff", "vox"]
        try transcriber.start()
        XCTAssertTrue(transcriber.isListening)
        XCTAssertEqual(transcriber.calls, [.ensurePermissions, .start])

        let text = await transcriber.stop()
        XCTAssertEqual(text, "hello world")
        XCTAssertFalse(transcriber.isListening)
        XCTAssertEqual(transcriber.calls, [.ensurePermissions, .start, .stop])
    }

    func testFakeTranscriberPermissionDeniedThrows() async throws {
        let transcriber = FakeTranscriber(permissionDenied: true)
        do {
            try await transcriber.ensurePermissions()
            XCTFail("expected permission error")
        } catch {
            XCTAssertNotNil(transcriber.lastError)
        }
        XCTAssertEqual(transcriber.calls, [.ensurePermissions])
    }

    func testCancelThrowsAwayResult_andIsNotRecordedAsAStop() async throws {
        let transcriber = FakeTranscriber(finalText: "should be discarded")
        try transcriber.start()
        transcriber.cancel()
        XCTAssertFalse(transcriber.isListening)
        XCTAssertEqual(transcriber.calls, [.start, .cancel])
    }

    func testSlowTranscriberSuspendsStop() async throws {
        let transcriber = SlowFakeTranscriber(delay: 0.05, finalText: "slow")
        try transcriber.start()
        let text = await transcriber.stop()
        XCTAssertEqual(text, "slow")
    }
}
