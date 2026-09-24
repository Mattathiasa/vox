import XCTest
@testable import VoxCore

/// The Windows agent (windows/src, JavaScript) ports this grammar. Both sides must
/// produce the same actions for every case in shared/grammar-cases.json.
final class GrammarParityTests: XCTestCase {
    struct Step: Decodable { let say: String; let expect: [String] }
    struct Case: Decodable { let steps: [Step] }
    struct File: Decodable { let cases: [Case] }

    static var sharedDir: URL {
        // Tests/VoxCoreTests/GrammarParityTests.swift -> repo root /shared
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared")
    }

    func testSharedGrammarCases() throws {
        let config = try JSONDecoder().decode(VoxConfig.self,
            from: Data(contentsOf: Self.sharedDir.appendingPathComponent("grammar-config.json")))
        let file = try JSONDecoder().decode(File.self,
            from: Data(contentsOf: Self.sharedDir.appendingPathComponent("grammar-cases.json")))
        XCTAssertGreaterThan(file.cases.count, 50)
        var failures: [String] = []
        for testCase in file.cases {
            var router = SessionRouter(config: config)
            for step in testCase.steps {
                let got = router.handle(step.say).map(GrammarCanonical.line)
                if got != step.expect {
                    failures.append("\"\(step.say)\"\n   expected \(step.expect)\n   got      \(got)")
                }
            }
        }
        XCTAssert(failures.isEmpty, "Swift and shared/grammar-cases.json disagree:\n" + failures.joined(separator: "\n"))
    }
}
