import XCTest
@testable import VoxCore

final class SafetyPolicyTests: XCTestCase {
    let policy = SafetyPolicy(patterns: VoxConfig.defaultConfirmPatterns)

    func testFlagsDestructiveRequests() {
        for text in [
            "git push", "Push it to main", "deploy the app", "delete the build folder",
            "rm -rf node_modules", "git reset --hard", "force the update", "publish to npm"
        ] {
            XCTAssertTrue(policy.needsConfirmation(text), text)
        }
    }

    func testAllowsOrdinaryRequests() {
        for text in [
            "add tests for the login form", "rename getUser to fetchUser",
            "explain this function", "pushover notifications are broken"
        ] {
            XCTAssertFalse(policy.needsConfirmation(text), text)
        }
    }
}

final class ConfigTests: XCTestCase {
    func testStarterConfigIsValid() {
        XCTAssertEqual(ConfigValidator.problems(in: .starter), [])
    }

    func testRoundTripThroughJSON() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let loaded = try ConfigStore.loadOrCreate(at: url)
        XCTAssertEqual(loaded, .starter)
        XCTAssertEqual(try ConfigStore.load(from: url), .starter)
    }

    func testMissingOptionalKeysGetDefaults() throws {
        let json = #"{ "tools": [ { "name": "freebuff", "command": "freebuff" } ] }"#
        let config = try JSONDecoder().decode(VoxConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.tools.first?.aliases, [])
        XCTAssertEqual(config.tools.first?.startupDelaySeconds, 4)
        XCTAssertEqual(config.exitPhrases, VoxConfig.defaultExitPhrases)
        XCTAssertEqual(config.shell, "/bin/zsh")
    }

    func testValidatorCatchesProblems() {
        let config = VoxConfig(
            tools: [
                ToolConfig(name: "a", aliases: ["shared"], command: "a"),
                ToolConfig(name: "b", aliases: ["shared"], command: ""),
                ToolConfig(name: "A", command: "x")
            ],
            confirmPatterns: ["(unclosed"]
        )
        let problems = ConfigValidator.problems(in: config)
        XCTAssertTrue(problems.contains { $0.contains("empty command") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("used twice") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("refers to both") }, "\(problems)")
        XCTAssertTrue(problems.contains { $0.contains("not a valid regex") }, "\(problems)")
    }
}
