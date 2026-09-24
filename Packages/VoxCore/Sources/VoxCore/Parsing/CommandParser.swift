import Foundation

/// What an utterance means as a Vox command (as opposed to text for a tool).
public enum Intent: Equatable, Sendable {
    /// "run freebuff in chirp and add tests"
    case launch(tool: String, project: String?, prompt: String?)
    /// "switch to claude", or just "claude"
    case focus(tool: String)
    /// "kill freebuff"
    case kill(tool: String)
    /// "list sessions", "what's running"
    case listSessions
    /// "open notes and create a note called groceries". `unparsed` is a
    /// follow-up clause that wasn't understood (reported, never guessed at).
    case desktop([DesktopCommand], unparsed: String?)
    /// "exit", "done": leave pass-through mode
    case exit
    /// "never mind", "cancel"
    case cancel
    /// "help", "what can you do"
    case help
    /// "interrupt" (the current tool) / "interrupt freebuff": Ctrl-C
    case interrupt(tool: String?)
    /// "restart freebuff"
    case restart(tool: String)
    /// "show freebuff": open Terminal attached to its session
    case showTool(String)
    /// "tell claude to fix the login bug": text for a running tool, without switching to it
    case tell(tool: String, text: String)
    /// A verb we understood, aimed at a tool that is not in the config.
    case unknownTool(spoken: String)
    /// "run freebuff in <something not in the config>"
    case unknownProject(spoken: String)
    case unknown
}

/// Rule-based parser. Deliberately dumb and predictable: an LLM fallback can
/// be added later for utterances that come back `.unknown`.
public struct CommandParser: Sendable {
    let tools: PhraseMatcher
    let projects: PhraseMatcher
    private let exitPhrases: PhraseMatcher
    private let prefixes: PhraseMatcher
    private let affirmatives: PhraseMatcher

    public init(config: VoxConfig) {
        tools = PhraseMatcher(config.tools.map { (value: $0.name, phrases: $0.phrases) })
        projects = PhraseMatcher(config.projects.map { (value: $0.name, phrases: $0.phrases) })
        exitPhrases = PhraseMatcher(phrases: config.exitPhrases)
        prefixes = PhraseMatcher(phrases: config.commandPrefixes)
        affirmatives = PhraseMatcher(phrases: config.affirmativePhrases)
    }

    // MARK: Vocabulary

    static let fillers: Set<String> = ["please", "hey", "ok", "okay", "um", "uh", "so", "now"]
    static let articles: Set<String> = ["the", "my", "a"]
    static let projectNouns: Set<String> = ["project", "folder", "repo", "repository", "directory", "app"]

    static let launchVerbs = PhraseMatcher(phrases: [
        "run", "start", "launch", "open", "fire up", "spin up", "boot up", "start up"
    ])
    static let focusVerbs = PhraseMatcher(phrases: [
        "switch to", "go to", "talk to", "use", "attach to", "focus", "focus on", "back to"
    ])
    static let killVerbs = PhraseMatcher(phrases: [
        "kill", "close", "quit", "stop", "end", "shut down", "terminate"
    ])
    static let listPhrases = PhraseMatcher(phrases: [
        "list", "list sessions", "sessions", "show sessions", "status",
        "whats running", "what is running"
    ])
    /// Launch verbs that may also open a Mac app ("run" is only for tools).
    static let openVerbs = PhraseMatcher(phrases: [
        "open", "launch", "start", "fire up", "start up", "bring up"
    ])
    static let appNouns: Set<String> = ["app", "application"]
    static let clauseBreaks = PhraseMatcher(phrases: ["and then", "then", "and"])

    static let noteVerbs = PhraseMatcher(phrases: [
        "create a note", "create a new note", "create note", "create new note",
        "make a note", "make a new note", "make note",
        "new note", "add a note", "write a note", "take a note", "note down", "jot down"
    ])
    static let noteConnectors = PhraseMatcher(phrases: [
        "called", "titled", "named", "saying", "that says", "which says", "with", "about", "to"
    ])
    static let searchVerbs = PhraseMatcher(phrases: [
        "search for", "search the web for", "search google for", "google search",
        "search", "google", "look up"
    ])
    static let urlVerbs = PhraseMatcher(phrases: [
        "go to", "visit", "browse to", "navigate to", "open website", "open the website",
        "open site", "open the site"
    ])
    static let hideVerbs = PhraseMatcher(phrases: ["hide"])
    static let cancelPhrases = PhraseMatcher(phrases: [
        "never mind", "nevermind", "cancel", "cancel that", "forget it", "nothing", "stop that", "ignore that"
    ])
    static let helpPhrases = PhraseMatcher(phrases: [
        "help", "what can you do", "what can i say", "what can i ask", "show commands", "list commands"
    ])
    static let namedShortcuts = PhraseMatcher(KeyCombo.named.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let volumeCommands: [(phrases: [String], change: VolumeChange)] = [
        (["volume up", "turn up the volume", "turn the volume up", "louder", "increase the volume",
          "increase volume", "raise the volume"], .up),
        (["volume down", "turn down the volume", "turn the volume down", "quieter", "softer",
          "lower the volume", "decrease the volume", "decrease volume"], .down),
        (["mute", "mute sound", "mute the sound", "mute volume", "mute the volume"], .mute),
        (["unmute", "unmute sound", "unmute the sound", "unmute volume", "unmute the volume"], .unmute)
    ]
    static let volumeMatcher = PhraseMatcher(volumeCommands.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let setVolumePrefixes = PhraseMatcher(phrases: [
        "set volume to", "set the volume to", "set volume", "volume to", "volume at", "volume"
    ])
    static let typeVerbs = PhraseMatcher(phrases: ["type", "type in", "type out"])
    static let pressVerbs = PhraseMatcher(phrases: ["press", "hit", "push the", "tap"])

    static let locationWords = PhraseMatcher(phrases: ["in", "on", "for", "inside", "at"])
    static let connectors = PhraseMatcher(phrases: [
        "and", "then", "and then", "to", "with",
        "and tell it to", "and ask it to", "tell it to", "ask it to", "and have it", "and say"
    ])

    // MARK: Helpers used by the router

    /// True if the whole utterance is an exit phrase ("exit", "done").
    public func isExit(_ text: String) -> Bool {
        let tokens = Tokenizer.tokenize(text)
        return !tokens.isEmpty && exitPhrases.matchesWhole(tokens)
    }

    /// True if the whole utterance is a confirmation ("yes", "do it").
    public func isAffirmative(_ text: String) -> Bool {
        let tokens = Tokenizer.tokenize(text)
        return !tokens.isEmpty && affirmatives.matchesWhole(tokens)
    }

    /// If the utterance starts with a command prefix ("vox ..."), the text after it.
    /// Returns "" when the prefix is all there is.
    public func strippingPrefix(_ text: String) -> String? {
        let tokens = Tokenizer.tokenize(text)
        guard let m = prefixes.match(tokens, at: 0) else { return nil }
        return Tokenizer.remainder(of: text, tokens: tokens, from: m.length) ?? ""
    }

    // MARK: Parsing

    public func parse(_ text: String) -> Intent {
        let tokens = Tokenizer.tokenize(text)
        var i = 0

        // Leading prefix and filler words: "hey vox, please run freebuff".
        if let p = prefixes.match(tokens, at: i) { i += p.length }
        while i < tokens.count, Self.fillers.contains(tokens[i].norm) { i += 1 }
        guard i < tokens.count else { return .unknown }

        let rest = Array(tokens[i...])

        if exitPhrases.matchesWhole(rest) { return .exit }
        if Self.listPhrases.matchesWhole(rest) { return .listSessions }
        if Self.cancelPhrases.matchesWhole(rest) { return .cancel }
        if Self.helpPhrases.matchesWhole(rest) { return .help }
        if let toolIntent = parseToolControl(text, tokens, from: i) { return toolIntent }

        if let commands = parseDesktopClause(text, tokens, from: i) {
            return .desktop(commands, unparsed: nil)
        }

        if let verb = Self.launchVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            // "open claude" is the tool; "open the claude app" is the Mac app.
            if let tool = tools.match(tokens, at: j), !isAppNoun(tokens, at: j + tool.length) {
                return parseLaunch(text, tokens, from: i + verb.length)
            }
            if Self.openVerbs.match(tokens, at: i) != nil,
               let intent = parseAppClause(text, tokens, from: j, make: DesktopCommand.openApp) {
                return intent
            }
            return unknownTool(text, tokens, from: j)
        }
        if let verb = Self.focusVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j), !isAppNoun(tokens, at: j + tool.length) {
                return .focus(tool: tool.value)
            }
            if let intent = parseAppClause(text, tokens, from: j, make: DesktopCommand.focusApp) { return intent }
            return unknownTool(text, tokens, from: j)
        }
        if let verb = Self.killVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j), !isAppNoun(tokens, at: j + tool.length) {
                return .kill(tool: tool.value)
            }
            if let intent = parseAppClause(text, tokens, from: j, make: DesktopCommand.quitApp) { return intent }
            return unknownTool(text, tokens, from: j)
        }

        // A bare tool name focuses it: "claude".
        if let tool = tools.match(tokens, at: i), tool.length == rest.count {
            return .focus(tool: tool.value)
        }
        return .unknown
    }

    private func parseLaunch(_ text: String, _ tokens: [Token], from start: Int) -> Intent {
        var j = skipArticles(tokens, from: start)
        guard let tool = tools.match(tokens, at: j) else {
            return unknownTool(text, tokens, from: j)
        }
        j += tool.length

        var project: String?
        if let loc = Self.locationWords.match(tokens, at: j) {
            var k = skipArticles(tokens, from: j + loc.length)
            if let p = projects.match(tokens, at: k) {
                project = p.value
                k += p.length
                if k < tokens.count, Self.projectNouns.contains(tokens[k].norm) { k += 1 }
                j = k
            } else {
                // Refuse to guess a directory. Starting an agent in the wrong
                // repo is worse than asking.
                return .unknownProject(spoken: Tokenizer.remainder(of: text, tokens: tokens, from: k) ?? "")
            }
        }

        if let c = Self.connectors.match(tokens, at: j) { j += c.length }
        let prompt = Tokenizer.remainder(of: text, tokens: tokens, from: j)
        return .launch(tool: tool.value, project: project, prompt: prompt)
    }

    // MARK: Desktop commands

    func isAppNoun(_ tokens: [Token], at index: Int) -> Bool {
        index < tokens.count && Self.appNouns.contains(tokens[index].norm)
    }

    /// "<verb> <app name> [and <desktop clause>]", e.g. open / close / switch to.
    func parseAppClause(
        _ text: String, _ tokens: [Token], from start: Int,
        make: (String) -> DesktopCommand
    ) -> Intent? {
        var k = start
        var nameTokens: [Token] = []
        // Stop at "and"/"then", or at "with 3 terminals" ("open antigravity with 3 terminals").
        func breakLength(at k: Int) -> Int? {
            if let brk = Self.clauseBreaks.match(tokens, at: k) { return brk.length }
            if tokens[k].norm == "with", terminalCount(tokens, at: k + 1) != nil { return 1 }
            return nil
        }
        while k < tokens.count, breakLength(at: k) == nil {
            nameTokens.append(tokens[k])
            k += 1
        }
        while let last = nameTokens.last, Self.appNouns.contains(last.norm) { nameTokens.removeLast() }
        guard let first = nameTokens.first, let last = nameTokens.last else { return nil }
        let name = String(text[first.range.lowerBound..<last.range.upperBound])

        var commands: [DesktopCommand] = [make(name)]
        var unparsed: String?
        if k < tokens.count, let length = breakLength(at: k) {
            let next = k + length
            if let more = parseDesktopClause(text, tokens, from: next) {
                commands += more
            } else {
                unparsed = Tokenizer.remainder(of: text, tokens: tokens, from: next)
            }
        }
        return .desktop(commands, unparsed: unparsed)
    }

    /// One desktop action starting at `i`, or nil if the words there aren't one.
    func parseDesktopClause(_ text: String, _ tokens: [Token], from i: Int) -> [DesktopCommand]? {
        guard i < tokens.count else { return nil }

        if let extra = parseExtraClause(text, tokens, from: i) { return extra }

        // Named shortcuts and volume: whole clause only ("copy", not "copy the file").
        if let first = wholeClause(Self.namedShortcuts, tokens, at: i) {
            let combo = KeyCombo.named[Int(first.value)!].combo
            return chain([.pressKey(combo)], text, tokens, after: first.end)
        }
        if let first = wholeClause(Self.volumeMatcher, tokens, at: i) {
            let change = Self.volumeCommands[Int(first.value)!].change
            return chain([.volume(change)], text, tokens, after: first.end)
        }
        if let prefix = Self.setVolumePrefixes.match(tokens, at: i) {
            var k = i + prefix.length
            if k < tokens.count, let level = Int(tokens[k].norm), (0...100).contains(level) {
                k += 1
                if k < tokens.count, tokens[k].norm == "percent" { k += 1 }
                if k == tokens.count || Self.clauseBreaks.match(tokens, at: k) != nil {
                    return chain([.volume(.set(level))], text, tokens, after: k)
                }
            }
        }
        if let verb = Self.hideVerbs.match(tokens, at: i),
           let intent = parseAppClause(text, tokens, from: skipArticles(tokens, from: i + verb.length),
                                       make: DesktopCommand.hideApp),
           case let .desktop(commands, unparsed) = intent, unparsed == nil {
            return commands
        }

        if let verb = Self.noteVerbs.match(tokens, at: i) {
            var j = i + verb.length
            if let c = Self.noteConnectors.match(tokens, at: j) { j += c.length }
            return [.createNote(Tokenizer.remainder(of: text, tokens: tokens, from: j) ?? "")]
        }

        if let verb = Self.urlVerbs.match(tokens, at: i),
           let rest = Tokenizer.remainder(of: text, tokens: tokens, from: i + verb.length),
           WebAddress.url(fromSpoken: rest) != nil {
            return [.openURL(rest)]
        }

        if let verb = Self.searchVerbs.match(tokens, at: i),
           let query = Tokenizer.remainder(of: text, tokens: tokens, from: i + verb.length) {
            return [.webSearch(query)]
        }

        if let verb = Self.typeVerbs.match(tokens, at: i) {
            let start = i + verb.length
            guard start < tokens.count else { return nil }
            // "type hello and press enter": split off a trailing key press.
            var k = start + 1
            while k < tokens.count {
                if let brk = Self.clauseBreaks.match(tokens, at: k),
                   let press = Self.pressVerbs.match(tokens, at: k + brk.length),
                   let keys = Tokenizer.remainder(of: text, tokens: tokens, from: k + brk.length + press.length),
                   let combo = KeyCombo.parse(keys) {
                    let typed = String(text[tokens[start].range.lowerBound..<tokens[k - 1].range.upperBound])
                    return [.typeText(typed), .pressKey(combo)]
                }
                k += 1
            }
            guard let typed = Tokenizer.remainder(of: text, tokens: tokens, from: start) else { return nil }
            return [.typeText(typed)]
        }

        if let verb = Self.pressVerbs.match(tokens, at: i),
           let keys = Tokenizer.remainder(of: text, tokens: tokens, from: i + verb.length),
           let combo = KeyCombo.parse(keys) {
            return [.pressKey(combo)]
        }

        return nil
    }

    /// A phrase from `matcher` at `i` that is a whole clause: it ends the
    /// utterance or is followed by "and"/"then". Returns its value and end index.
    func wholeClause(_ matcher: PhraseMatcher, _ tokens: [Token], at i: Int) -> (value: String, end: Int)? {
        guard let m = matcher.match(tokens, at: i) else { return nil }
        let end = i + m.length
        guard end == tokens.count || Self.clauseBreaks.match(tokens, at: end) != nil else { return nil }
        return (m.value, end)
    }

    /// Appends a following "and <desktop clause>". nil if that follow-up isn't understood.
    func chain(_ commands: [DesktopCommand], _ text: String, _ tokens: [Token], after end: Int) -> [DesktopCommand]? {
        guard end < tokens.count, let brk = Self.clauseBreaks.match(tokens, at: end) else { return commands }
        guard let more = parseDesktopClause(text, tokens, from: end + brk.length) else { return nil }
        return commands + more
    }

    func skipArticles(_ tokens: [Token], from index: Int) -> Int {
        var j = index
        while j < tokens.count, Self.articles.contains(tokens[j].norm) { j += 1 }
        return j
    }

    private func unknownTool(_ text: String, _ tokens: [Token], from index: Int) -> Intent {
        guard let spoken = Tokenizer.remainder(of: text, tokens: tokens, from: index) else {
            return .unknown
        }
        return .unknownTool(spoken: spoken)
    }
}
