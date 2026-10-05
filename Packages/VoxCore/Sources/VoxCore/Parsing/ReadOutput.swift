import Foundation

/// "what did claude say", "read the last answer": speak a tool's latest answer (Phase 12.3).
public struct ReadRequest: Equatable, Sendable {
    /// nil = the tool you're talking to.
    public let tool: String?
}

extension CommandParser {
    /// Whole utterances about the tool you're talking to.
    static let readItPhrases = PhraseMatcher(phrases: [
        "what did it say", "what did it answer", "what does it say", "whats it saying", "what is it saying",
        "read the output", "read the last answer", "read the answer", "read the response", "read the last response",
        "read it back", "read that back", "read back", "read the last message", "read the reply", "read the last reply"
    ])
    /// "<question> claude <ending>": the ending is required ("what did claude say").
    static let readQuestions = PhraseMatcher(phrases: ["what did", "what does", "whats", "what is"])
    static let readQuestionEndings = PhraseMatcher(phrases: ["say", "saying", "said", "answer", "reply", "write", "just say"])
    /// "read <from> claude": the tool ends the utterance ("read claude", "read the last answer from claude").
    static let readFromPrefixes = PhraseMatcher(phrases: [
        "read the output of", "read the output from", "read the last answer from", "read the answer from",
        "read the response from", "read the last response from", "read the last message from", "read back", "read"
    ])
    static let readEndings = PhraseMatcher(phrases: ["output", "answer", "response", "reply", "back"])

    /// The whole utterance as a read-back request, or nil if it isn't one.
    public func readRequest(_ text: String) -> ReadRequest? {
        let tokens = Tokenizer.tokenize(text)
        var i = 0
        while i < tokens.count, Self.fillers.contains(tokens[i].norm) { i += 1 }
        return parseReadRequest(tokens, from: i)
    }

    func parseReadRequest(_ tokens: [Token], from i: Int) -> ReadRequest? {
        guard i < tokens.count else { return nil }
        if Self.readItPhrases.matchesWhole(Array(tokens[i...])) { return ReadRequest(tool: nil) }

        if let question = Self.readQuestions.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + question.length)
            if let tool = tools.match(tokens, at: j),
               let ending = Self.readQuestionEndings.match(tokens, at: j + tool.length),
               j + tool.length + ending.length == tokens.count {
                return ReadRequest(tool: tool.value)
            }
        }
        if let prefix = Self.readFromPrefixes.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + prefix.length)
            if let tool = tools.match(tokens, at: j) {
                var end = j + tool.length
                if let ending = Self.readEndings.match(tokens, at: end) { end += ending.length }
                if end == tokens.count { return ReadRequest(tool: tool.value) }
            }
        }
        return nil
    }
}
