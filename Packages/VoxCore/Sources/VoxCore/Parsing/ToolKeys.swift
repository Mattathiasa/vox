import Foundation

/// Keys for a running tool, by voice (Phase 12.2): "press escape", "shift tab", "arrow down twice",
/// "choose option 2", "approve", "deny", optionally "… in claude".
public struct ToolKeyRequest: Equatable, Sendable {
    /// tmux key names (`TmuxAdapter.allowedKeys`).
    public let keys: [String]
    /// "in claude"; nil = the tool you're talking to.
    public let tool: String?
    /// Approve / deny / choose option N: only ever meant for a tool, so these work without "press"
    /// and without naming a tool. Plain keys without a tool stay desktop key presses when idle.
    public let isAnswer: Bool
}

extension CommandParser {
    /// Coding agents' permission menus: 1 = yes, 2 = yes and don't ask again, Esc = no
    /// (Claude Code, Codex and Gemini CLI all use this order).
    static let answerPhrases: [(phrases: [String], keys: [String])] = [
        (["approve", "approve it", "approve that", "accept", "accept it", "allow", "allow it", "allow once",
          "yes approve", "approve once"], ["1"]),
        (["always allow", "allow always", "approve always", "always approve", "dont ask again",
          "yes dont ask again", "yes and dont ask again"], ["2"]),
        (["deny", "deny it", "deny that", "reject", "reject it", "decline", "dont allow", "dont allow it"], ["Escape"])
    ]
    static let answerMatcher = PhraseMatcher(answerPhrases.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let optionWords = PhraseMatcher(phrases: [
        "choose option", "select option", "pick option", "choose number", "select number", "pick number",
        "choose", "select", "pick", "option", "number"
    ])
    /// Digits as spoken (after an option word "to"/"too" is a misheard "two").
    static let optionNumbers: [String: Int] = [
        "one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3, "four": 4, "for": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9
    ]

    static let toolKeyNames: [(phrases: [String], key: String)] = [
        (["escape", "esc", "the escape key", "escape key"], "Escape"),
        (["enter", "return", "the enter key", "enter key", "the return key", "return key"], "Enter"),
        (["shift tab", "back tab", "shift plus tab"], "BTab"),
        (["tab", "the tab key", "tab key"], "Tab"),
        (["arrow up", "up arrow", "the up arrow", "up key"], "Up"),
        (["arrow down", "down arrow", "the down arrow", "down key"], "Down"),
        (["arrow left", "left arrow", "the left arrow", "left key"], "Left"),
        (["arrow right", "right arrow", "the right arrow", "right key"], "Right"),
        (["backspace", "back space"], "BSpace"),
        (["page up"], "PPage"),
        (["page down"], "NPage")
    ]
    static let toolKeyMatcher = PhraseMatcher(toolKeyNames.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let keyPressVerbs = PhraseMatcher(phrases: ["press", "hit", "push", "tap", "send"])
    /// "go down", "move up twice": arrows only.
    static let arrowVerbs = PhraseMatcher(phrases: ["go", "move"])
    static let arrowDirections: [String: String] = ["up": "Up", "down": "Down", "left": "Left", "right": "Right"]

    /// The whole utterance as keys for a tool, or nil. Used while talking to a tool,
    /// where "press escape" means the tool, not the front app.
    public func toolKeys(_ text: String) -> ToolKeyRequest? {
        let tokens = Tokenizer.tokenize(text)
        var i = 0
        while i < tokens.count, Self.fillers.contains(tokens[i].norm) { i += 1 }
        return parseToolKeys(tokens, from: i)
    }

    func parseToolKeys(_ tokens: [Token], from i: Int) -> ToolKeyRequest? {
        guard i < tokens.count else { return nil }
        var j = i
        var keys: [String]
        var isAnswer = false

        if let answer = Self.answerMatcher.match(tokens, at: j) {
            keys = Self.answerPhrases[Int(answer.value)!].keys
            j += answer.length
            isAnswer = true
        } else if let option = Self.optionWords.match(tokens, at: j), j + option.length < tokens.count,
                  let n = optionNumber(tokens[j + option.length].norm) {
            keys = [String(n)]
            j += option.length + 1
            isAnswer = true
        } else {
            let pressed = Self.keyPressVerbs.match(tokens, at: j)
            if let pressed { j += pressed.length }
            if let name = Self.toolKeyMatcher.match(tokens, at: j) {
                keys = [Self.toolKeyNames[Int(name.value)!].key]
                j += name.length
            } else if pressed == nil, let verb = Self.arrowVerbs.match(tokens, at: j), j + verb.length < tokens.count,
                      let arrow = Self.arrowDirections[tokens[j + verb.length].norm] {
                keys = [arrow]
                j += verb.length + 1
            } else if pressed != nil, j < tokens.count, let arrow = Self.arrowDirections[tokens[j].norm] {
                keys = [arrow]  // "press down"
                j += 1
            } else if pressed != nil, j < tokens.count, let n = Int(tokens[j].norm), (1...9).contains(n) {
                keys = [String(n)]  // "press 2": a plain key (the front app's, unless you're talking to a tool)
                j += 1
            } else {
                return nil
            }
            // "twice", "3 times", "three times"
            if j < tokens.count, tokens[j].norm == "twice" {
                keys += keys
                j += 1
            } else if j + 1 < tokens.count, tokens[j + 1].norm == "times",
                      let n = Int(tokens[j].norm) ?? Self.numberWords[tokens[j].norm], (1...9).contains(n) {
                keys = Array(repeating: keys[0], count: n)
                j += 2
            }
        }

        // "… in claude", "approve claude"
        var tool: String?
        if j < tokens.count {
            var k = j
            if let loc = Self.locationWords.match(tokens, at: k) { k += loc.length }
            else if tokens[k].norm == "to" { k += 1 }
            else if !isAnswer { return nil }
            k = skipArticles(tokens, from: k)
            guard let match = matchInstance(tokens, at: k), k + match.length == tokens.count else { return nil }
            tool = match.value
            j = tokens.count
        }
        return ToolKeyRequest(keys: keys, tool: tool, isAnswer: isAnswer)
    }

    private func optionNumber(_ word: String) -> Int? {
        if let n = Int(word), (1...9).contains(n) { return n }
        return Self.optionNumbers[word]
    }
}
