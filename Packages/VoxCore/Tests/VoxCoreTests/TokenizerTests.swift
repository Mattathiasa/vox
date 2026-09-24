import XCTest
@testable import VoxCore

final class TokenizerTests: XCTestCase {
    func testNormalizesCaseAndPunctuation() {
        let tokens = Tokenizer.tokenize("Hey, What's up-to-date?")
        XCTAssertEqual(tokens.map(\.norm), ["hey", "whats", "up", "to", "date"])
    }

    func testCurlyApostrophe() {
        XCTAssertEqual(Tokenizer.words("that\u{2019}s all"), ["thats", "all"])
    }

    func testRemainderKeepsOriginalText() {
        let text = "run freebuff and rename getUser() to fetch_user"
        let tokens = Tokenizer.tokenize(text)
        // tokens: run freebuff and rename ...
        XCTAssertEqual(Tokenizer.remainder(of: text, tokens: tokens, from: 3),
                       "rename getUser() to fetch_user")
    }

    func testRemainderPastEndIsNil() {
        let tokens = Tokenizer.tokenize("run freebuff")
        XCTAssertNil(Tokenizer.remainder(of: "run freebuff", tokens: tokens, from: 2))
    }

    func testPhraseMatcherPrefersLongestPhrase() {
        let matcher = PhraseMatcher([
            (value: "claude", phrases: ["claude"]),
            (value: "claude-code", phrases: ["claude code"])
        ])
        let m = matcher.match(Tokenizer.tokenize("claude code please"), at: 0)
        XCTAssertEqual(m?.value, "claude-code")
        XCTAssertEqual(m?.length, 2)
    }

    func testMatchesWhole() {
        let matcher = PhraseMatcher(phrases: ["stop listening", "exit"])
        XCTAssertTrue(matcher.matchesWhole(Tokenizer.tokenize("Stop listening.")))
        XCTAssertFalse(matcher.matchesWhole(Tokenizer.tokenize("exit the loop early")))
    }
}
