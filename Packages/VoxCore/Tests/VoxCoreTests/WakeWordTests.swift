import XCTest
@testable import VoxCore

final class WakeWordDetectorTests: XCTestCase {
    let detector = WakeWordDetector(phrases: WakeWordConfig.defaultPhrases)

    func testFindsCommandAfterWakeWord() {
        XCTAssertEqual(detector.command(in: "Balcha, open Safari"), "open Safari")
        XCTAssertEqual(detector.command(in: "um bal cha open notes and create a note"),
                       "open notes and create a note")
    }

    func testWakeWordAloneIsEmptyCommand() {
        XCTAssertEqual(detector.command(in: "Balcha."), "")
    }

    func testNoWakeWord() {
        XCTAssertNil(detector.command(in: "open safari"))
        XCTAssertNil(detector.command(in: ""))
    }

    func testUsesLastWakeWord() {
        XCTAssertEqual(detector.command(in: "balcha open notes balcha open safari"), "open safari")
    }
}

final class WakeWordTrackerTests: XCTestCase {
    var tracker = WakeWordTracker(config: WakeWordConfig(silenceSeconds: 1.0, commandTimeoutSeconds: 5))

    override func setUp() {
        tracker = WakeWordTracker(config: WakeWordConfig(silenceSeconds: 1.0, commandTimeoutSeconds: 5))
    }

    func testIgnoresSpeechWithoutWakeWord() {
        XCTAssertEqual(tracker.update(transcript: "just talking", at: 0), .none)
        XCTAssertEqual(tracker.tick(at: 10), .none)
        XCTAssertFalse(tracker.isAwake)
    }

    func testFiresAfterSilence() {
        XCTAssertEqual(tracker.update(transcript: "balcha", at: 0), .awake(""))
        XCTAssertEqual(tracker.update(transcript: "balcha open", at: 0.5), .awake("open"))
        XCTAssertEqual(tracker.update(transcript: "balcha open safari", at: 1.0), .awake("open safari"))
        XCTAssertEqual(tracker.tick(at: 1.5), .none, "still inside the silence window")
        XCTAssertEqual(tracker.tick(at: 2.1), .fire("open safari"))
        XCTAssertFalse(tracker.isAwake)
    }

    func testRepeatedIdenticalPartialsDontResetSilence() {
        _ = tracker.update(transcript: "balcha open safari", at: 0)
        _ = tracker.update(transcript: "balcha open safari", at: 0.9)
        XCTAssertEqual(tracker.tick(at: 1.05), .fire("open safari"))
    }

    func testTimesOutWithoutCommand() {
        _ = tracker.update(transcript: "balcha", at: 0)
        XCTAssertEqual(tracker.tick(at: 4), .none)
        XCTAssertEqual(tracker.tick(at: 5.1), .timedOut)
    }

    func testLongCommandStillFires() {
        var t = 0.0
        _ = tracker.update(transcript: "balcha type", at: t)
        var text = "balcha type"
        var fired: WakeWordTracker.Event = .none
        while t < 20, fired == .none {
            t += 0.5
            text += " word"
            _ = tracker.update(transcript: text, at: t)
            fired = tracker.tick(at: t)
        }
        guard case .fire = fired else { return XCTFail("never fired") }
        XCTAssertLessThanOrEqual(t, 15.5)
    }

    func testOldConfigWithoutWakeWordDecodes() throws {
        let json = #"{ "tools": [ { "name": "freebuff", "command": "freebuff" } ] }"#
        let config = try JSONDecoder().decode(VoxConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.wakeWord, WakeWordConfig())
        XCTAssertTrue(config.wakeWord.enabled)
    }
}
