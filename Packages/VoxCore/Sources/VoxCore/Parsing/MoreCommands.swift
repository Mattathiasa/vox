import Foundation

/// Batch-2 commands: media, questions, timers, reminders, folders, projects,
/// site searches, system actions, and tool control. Kept apart from the core
/// grammar so it can grow without touching it.
extension CommandParser {
    // MARK: Vocabulary

    static let mediaCommands: [(phrases: [String], key: MediaKey)] = [
        (["play", "pause", "resume", "play music", "pause music", "resume music", "pause the music",
          "stop the music", "play pause", "play the music"], .playPause),
        (["next", "next track", "next song", "skip", "skip song", "skip this song", "skip track"], .next),
        (["previous track", "previous song", "last song", "go back a song", "play the last song"], .previous)
    ]
    static let mediaMatcher = PhraseMatcher(mediaCommands.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })

    static let questions: [(phrases: [String], question: Question)] = [
        (["what time is it", "whats the time", "what is the time", "tell me the time", "time", "current time",
          "the time"], .time),
        (["whats the date", "what is the date", "what day is it", "whats today", "todays date",
          "whats todays date", "what is today", "date", "the date"], .date),
        (["battery", "how much battery", "how much battery do i have", "battery level", "hows my battery",
          "battery status", "whats my battery", "whats the battery", "how is the battery"], .battery),
        (["read clipboard", "read my clipboard", "read the clipboard", "whats on my clipboard",
          "whats in my clipboard", "whats on the clipboard", "clipboard"], .clipboard),
        (["what apps are open", "which apps are open", "whats open", "list open apps", "open apps",
          "what apps are running", "which apps are running"], .openApps)
    ]
    static let questionMatcher = PhraseMatcher(questions.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let mathVerbs = PhraseMatcher(phrases: [
        "whats", "what is", "calculate", "compute", "how much is", "what does"
    ])

    static let timerVerbs = PhraseMatcher(phrases: [
        "set a timer for", "set timer for", "start a timer for", "start timer for", "timer for",
        "set a timer", "start a timer", "set an alarm for", "countdown", "count down"
    ])
    static let cancelTimerPhrases = PhraseMatcher(phrases: [
        "cancel timer", "cancel the timer", "cancel timers", "cancel all timers", "cancel my timer",
        "stop timer", "stop the timer", "stop timers", "stop all timers", "clear timers"
    ])

    static let reminderVerbs = PhraseMatcher(phrases: [
        "remind me to", "remind me", "add a reminder to", "add a reminder", "create a reminder to",
        "create a reminder", "new reminder", "set a reminder to", "set a reminder", "reminder to"
    ])

    static let standardFolders: Set<String> = [
        "downloads", "documents", "desktop", "home", "applications", "projects", "pictures", "movies", "music"
    ]
    /// These open as folders even without the word "folder" (no app has these names).
    static let unambiguousFolders: Set<String> = ["downloads", "documents", "projects", "home"]
    static let folderNouns: Set<String> = ["folder", "directory"]
    static let showVerbs = PhraseMatcher(phrases: ["show", "show me", "reveal"])
    static let withWords = PhraseMatcher(phrases: ["in", "with", "using"])

    static let sitePhrases = PhraseMatcher(SearchSite.allCases.map { (value: $0.rawValue, phrases: $0.phrases) })
    static let playVerbs = PhraseMatcher(phrases: ["play", "watch", "find"])
    static let directionsVerbs = PhraseMatcher(phrases: [
        "directions to", "get directions to", "how do i get to", "where is", "show me on the map",
        "find on the map", "map of"
    ])

    static let darkModePhrases: [(phrases: [String], on: Bool?)] = [
        (["dark mode", "toggle dark mode", "switch dark mode"], nil),
        (["turn on dark mode", "enable dark mode", "dark mode on", "go dark"], true),
        (["turn off dark mode", "disable dark mode", "dark mode off", "light mode", "turn on light mode"], false)
    ]
    static let darkModeMatcher = PhraseMatcher(darkModePhrases.enumerated().map {
        (value: String($0.offset), phrases: $0.element.phrases)
    })
    static let screenOffPhrases = PhraseMatcher(phrases: [
        "turn off the screen", "turn off screen", "screen off", "turn off the display", "turn off display",
        "sleep display", "sleep the display", "sleep screen"
    ])

    static let interruptPhrases = PhraseMatcher(phrases: [
        "interrupt", "stop it", "stop generating", "control c", "ctrl c", "abort", "cancel it"
    ])
    static let interruptVerbs = PhraseMatcher(phrases: ["interrupt", "stop"])
    static let restartVerbs = PhraseMatcher(phrases: ["restart", "relaunch", "reboot", "reload"])
    static let watchVerbs = PhraseMatcher(phrases: ["show", "watch", "view", "show me"])
    static let tellToolVerbs = PhraseMatcher(phrases: ["tell", "ask", "message", "say to"])

    /// IDE names recognized for "ask <ide> to <prompt>" chat commands.
    static let ideNames = PhraseMatcher(phrases: [
        "antigravity", "kiro", "visual studio code", "cursor", "windsurf", "vscodium"
    ])

    /// Words that turn "claude" into a reference to the Claude desktop app
    /// rather than the terminal tool configured in VoxConfig.
    static let claudeDesktopAppNouns: Set<String> = ["desktop", "app", "application"]

    // MARK: Tool control (checked before launch/focus/kill)

    /// True if the whole utterance means "interrupt the current tool".
    public func isInterrupt(_ text: String) -> Bool {
        let tokens = Tokenizer.tokenize(text)
        return !tokens.isEmpty && Self.interruptPhrases.matchesWhole(tokens)
    }

    func parseToolControl(_ text: String, _ tokens: [Token], from i: Int) -> Intent? {
        let rest = Array(tokens[i...])
        if Self.interruptPhrases.matchesWhole(rest) { return .interrupt(tool: nil) }

        // "tell claude to fix the login bug", "ask freebuff what this file does"
        if let verb = Self.tellToolVerbs.match(tokens, at: i) {
            var j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j),
               !(tool.value == "claude" && j + tool.length < tokens.count && Self.claudeDesktopAppNouns.contains(tokens[j + tool.length].norm)) {
                j += tool.length
                if j < tokens.count, tokens[j].norm == "to" { j += 1 }
                if let message = Tokenizer.remainder(of: text, tokens: tokens, from: j) {
                    return .tell(tool: tool.value, text: message)
                }
            } else if let ide = Self.ideNames.match(tokens, at: j) {
                // "ask antigravity to explain this file" — send a prompt to an IDE's AI chat.
                j += ide.length
                if j < tokens.count, tokens[j].norm == "to" { j += 1 }
                if let message = Tokenizer.remainder(of: text, tokens: tokens, from: j) {
                    return .desktop([.ide(.chat(message: message, submit: true))], unparsed: nil)
                }
            }
        }

        if let verb = Self.interruptVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j), j + tool.length == tokens.count,
               verb.value == "interrupt" {
                return .interrupt(tool: tool.value)
            }
        }
        if let verb = Self.restartVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j), j + tool.length == tokens.count {
                return .restart(tool: tool.value)
            }
        }
        if let verb = Self.watchVerbs.match(tokens, at: i) {
            let j = skipArticles(tokens, from: i + verb.length)
            if let tool = tools.match(tokens, at: j), j + tool.length == tokens.count {
                return .showTool(tool.value)
            }
        }
        return nil
    }

    // MARK: Desktop clauses

    /// Phrases that trigger Safari tab reading or Claude desktop messaging.
    static let safariTabPhrases = PhraseMatcher(phrases: [
        "read safari tab", "safari tab", "safari url", "what url is this", "what's the url"
    ])
    static let claudeDesktopPhrases = PhraseMatcher(phrases: [
        "claude desktop", "claude app"
    ])

    func parseExtraClause(_ text: String, _ tokens: [Token], from i: Int) -> [DesktopCommand]? {
        guard i < tokens.count else { return nil }

        if let ide = parseIDEClause(text, tokens, from: i) { return ide }

        if let m = wholeClause(Self.safariTabPhrases, tokens, at: i) {
            return chain([.safariReadTab], text, tokens, after: m.end)
        }

        // "ask claude desktop to explain this file" — send a prompt to the Claude desktop app.
        // (Tool "claude" is handled in parseToolControl; this catches "claude desktop" / "claude app".)
        if let verb = Self.tellToolVerbs.match(tokens, at: i),
           let target = Self.claudeDesktopPhrases.match(tokens, at: i + verb.length) {
            var j = i + verb.length + target.length
            if j < tokens.count, tokens[j].norm == "to" { j += 1 }
            if let message = Tokenizer.remainder(of: text, tokens: tokens, from: j) {
                return [.sendMessageToApp(app: "claude", text: message)]
            }
        }

        if let m = wholeClause(Self.mediaMatcher, tokens, at: i) {
            return chain([.media(Self.mediaCommands[Int(m.value)!].key)], text, tokens, after: m.end)
        }
        if let m = wholeClause(Self.questionMatcher, tokens, at: i) {
            return chain([.answer(Self.questions[Int(m.value)!].question)], text, tokens, after: m.end)
        }
        if let m = wholeClause(Self.darkModeMatcher, tokens, at: i) {
            return chain([.system(.darkMode(Self.darkModePhrases[Int(m.value)!].on))], text, tokens, after: m.end)
        }
        if let m = wholeClause(Self.screenOffPhrases, tokens, at: i) {
            return chain([.system(.screenOff)], text, tokens, after: m.end)
        }
        if let m = wholeClause(Self.cancelTimerPhrases, tokens, at: i) {
            return chain([.cancelTimers], text, tokens, after: m.end)
        }

        // "set a timer for 5 minutes"
        if let verb = Self.timerVerbs.match(tokens, at: i) {
            var j = i + verb.length
            if j < tokens.count, tokens[j].norm == "for" { j += 1 }
            if let duration = SpokenDuration.parse(tokens, from: j), duration.end == tokens.count {
                return [.timer(seconds: duration.seconds)]
            }
        }
        // "5 minute timer"
        if let duration = SpokenDuration.parse(tokens, from: i), duration.end + 1 == tokens.count,
           tokens[duration.end].norm == "timer" {
            return [.timer(seconds: duration.seconds)]
        }

        // "remind me [in 10 minutes] to call mom [in 10 minutes]"
        if let verb = Self.reminderVerbs.match(tokens, at: i) {
            return parseReminder(text, tokens, from: i + verb.length)
        }

        // "search youtube for lofi", "search for lofi on youtube", "youtube lofi beats"
        if let search = Self.searchVerbs.match(tokens, at: i) {
            var j = i + search.length
            if let site = Self.sitePhrases.match(tokens, at: j) {
                j += site.length
                if j < tokens.count, tokens[j].norm == "for" { j += 1 }
                if let query = Tokenizer.remainder(of: text, tokens: tokens, from: j) {
                    return [.siteSearch(SearchSite(rawValue: site.value)!, query)]
                }
            }
            if let (query, site) = splitTrailingSite(text, tokens, from: j) {
                return [.siteSearch(site, query)]
            }
        }
        // "play lofi on youtube"
        if let play = Self.playVerbs.match(tokens, at: i),
           let (query, site) = splitTrailingSite(text, tokens, from: i + play.length) {
            return [.siteSearch(site, query)]
        }
        // "directions to bole airport"
        if let verb = Self.directionsVerbs.match(tokens, at: i),
           let place = Tokenizer.remainder(of: text, tokens: tokens, from: i + verb.length) {
            return [.siteSearch(.maps, place)]
        }

        // Folders and projects: "open downloads", "open the chirp project", "open chirp in kiro"
        if let verb = Self.openVerbs.match(tokens, at: i) ?? Self.showVerbs.match(tokens, at: i) {
            if let result = parseFolderOrProject(text, tokens, from: skipArticles(tokens, from: i + verb.length)) {
                return result
            }
        }

        // "what's 12 times 8", "calculate 15 percent of 80"
        if let verb = Self.mathVerbs.match(tokens, at: i),
           let expression = Tokenizer.remainder(of: text, tokens: tokens, from: i + verb.length),
           SpokenMath.evaluate(expression) != nil {
            return [.answer(.calculation(expression))]
        }
        if let whole = Tokenizer.remainder(of: text, tokens: tokens, from: i),
           tokens[i].norm.first?.isNumber == true, SpokenMath.evaluate(whole) != nil {
            return [.answer(.calculation(whole))]
        }

        return nil
    }

    // MARK: Helpers

    private func parseReminder(_ text: String, _ tokens: [Token], from start: Int) -> [DesktopCommand]? {
        var j = start
        var due: Int?
        // Leading time: "remind me in 10 minutes to …"
        if j < tokens.count, tokens[j].norm == "in", let d = SpokenDuration.parse(tokens, from: j + 1) {
            due = d.seconds
            j = d.end
            if j < tokens.count, tokens[j].norm == "to" { j += 1 }
        } else if j < tokens.count, tokens[j].norm == "to" {
            j += 1
        }
        guard j < tokens.count else { return nil }
        var end = tokens.count
        // Trailing time: "… in 10 minutes"
        if due == nil {
            var k = tokens.count - 2
            while k > j {
                if tokens[k].norm == "in", let d = SpokenDuration.parse(tokens, from: k + 1), d.end == tokens.count {
                    due = d.seconds
                    end = k
                    break
                }
                k -= 1
            }
        }
        guard end > j else { return nil }
        let what = String(text[tokens[j].range.lowerBound..<tokens[end - 1].range.upperBound])
        return [.reminder(what, inSeconds: due)]
    }

    /// "<query> on youtube" -> (query, .youtube)
    private func splitTrailingSite(_ text: String, _ tokens: [Token], from start: Int) -> (String, SearchSite)? {
        var k = tokens.count - 1
        while k > start {
            if ["on", "in"].contains(tokens[k].norm),
               let site = Self.sitePhrases.match(tokens, at: k + 1), k + 1 + site.length == tokens.count {
                let query = String(text[tokens[start].range.lowerBound..<tokens[k - 1].range.upperBound])
                return (query, SearchSite(rawValue: site.value)!)
            }
            k -= 1
        }
        return nil
    }

    private func parseFolderOrProject(_ text: String, _ tokens: [Token], from j: Int) -> [DesktopCommand]? {
        guard j < tokens.count else { return nil }

        // Standard folder: "downloads", "the music folder", "my documents"
        let name = tokens[j].norm
        if Self.standardFolders.contains(name) {
            var k = j + 1
            let saidFolder = k < tokens.count && Self.folderNouns.contains(tokens[k].norm)
            if saidFolder { k += 1 }
            if (saidFolder || Self.unambiguousFolders.contains(name)),
               k == tokens.count || Self.clauseBreaks.match(tokens, at: k) != nil {
                return chain([.openFolder(name)], text, tokens, after: k)
            }
        }

        // Config project: "chirp", "the chirp project", "chirp in kiro"
        guard let project = projects.match(tokens, at: j) else { return nil }
        var k = j + project.length
        let saidNoun = k < tokens.count && Self.projectNouns.contains(tokens[k].norm)
        if saidNoun { k += 1 }
        if let with = Self.withWords.match(tokens, at: k) {
            let appStart = k + with.length
            var end = appStart
            while end < tokens.count, Self.clauseBreaks.match(tokens, at: end) == nil { end += 1 }
            guard end > appStart else { return nil }
            let app = String(text[tokens[appStart].range.lowerBound..<tokens[end - 1].range.upperBound])
            return chain([.openProject(project: project.value, app: app)], text, tokens, after: end)
        }
        if saidNoun, k == tokens.count || Self.clauseBreaks.match(tokens, at: k) != nil {
            return chain([.openFolder(project.value)], text, tokens, after: k)
        }
        return nil
    }
}
