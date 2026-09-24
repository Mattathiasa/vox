import Foundation

/// A word from an utterance: its normalized form for matching, and where it
/// sits in the original text so prompts can be passed on exactly as spoken.
public struct Token: Equatable, Sendable {
    public let norm: String
    public let range: Range<String.Index>
}

public enum Tokenizer {
    /// Splits on anything that is not a letter, digit or apostrophe, then
    /// lowercases and drops apostrophes: "What's up-to-date?" -> whats, up, to, date.
    public static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var index = text.startIndex

        func flush(until end: String.Index) {
            guard let s = start else { return }
            let norm = String(text[s..<end].lowercased().filter { $0 != "'" && $0 != "\u{2019}" })
            if !norm.isEmpty {
                tokens.append(Token(norm: norm, range: s..<end))
            }
            start = nil
        }

        while index < text.endIndex {
            let ch = text[index]
            let isWordChar = ch.isLetter || ch.isNumber || ch == "'" || ch == "\u{2019}"
            if isWordChar {
                if start == nil { start = index }
            } else {
                flush(until: index)
            }
            index = text.index(after: index)
        }
        flush(until: text.endIndex)
        return tokens
    }

    /// Normalized words of a phrase, for matching against tokens.
    public static func words(_ phrase: String) -> [String] {
        tokenize(phrase).map(\.norm)
    }

    /// Single-string form of a phrase ("Free-Buff" -> "free buff").
    public static func normalizedPhrase(_ phrase: String) -> String {
        words(phrase).joined(separator: " ")
    }

    /// Original text from token `index` to the end, trimmed. nil if nothing left.
    public static func remainder(of text: String, tokens: [Token], from index: Int) -> String? {
        guard index < tokens.count else { return nil }
        let rest = text[tokens[index].range.lowerBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}

/// Matches multi-word phrases against a token list.
public struct PhraseMatcher: Sendable {
    /// (words, value) pairs, longest phrases first so "claude code" beats "claude".
    private let entries: [(words: [String], value: String)]

    public init(_ phrasesByValue: [(value: String, phrases: [String])]) {
        var entries: [(words: [String], value: String)] = []
        for item in phrasesByValue {
            for phrase in item.phrases {
                let w = Tokenizer.words(phrase)
                if !w.isEmpty { entries.append((w, item.value)) }
            }
        }
        self.entries = entries.sorted { $0.words.count > $1.words.count }
    }

    /// Convenience for plain phrase lists where the value is the phrase itself.
    public init(phrases: [String]) {
        self.init(phrases.map { (value: $0, phrases: [$0]) })
    }

    /// Longest phrase starting at `index`: its value and how many tokens it used.
    public func match(_ tokens: [Token], at index: Int) -> (value: String, length: Int)? {
        for entry in entries {
            let end = index + entry.words.count
            guard end <= tokens.count else { continue }
            if zip(tokens[index..<end], entry.words).allSatisfy({ pair in pair.0.norm == pair.1 }) {
                return (entry.value, entry.words.count)
            }
        }
        return nil
    }

    /// True if the whole token list is exactly one of the phrases.
    public func matchesWhole(_ tokens: [Token]) -> Bool {
        guard let m = match(tokens, at: 0) else { return false }
        return m.length == tokens.count
    }
}
