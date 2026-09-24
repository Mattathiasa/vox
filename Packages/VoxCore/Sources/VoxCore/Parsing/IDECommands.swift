import Foundation

/// IDE terminal commands (through the Vox Bridge extension):
///   "open 3 terminals [side by side] [running claude, freebuff and npm run dev]"
///   "split the terminal into 3"
///   "run claude on one of the terminals" / "run npm run dev in terminal 2"
///   "run claude in the first, freebuff in the second and npm run dev in the third"
///   "in terminal 3 run npm test" / "type hello in terminal 2" / "tell terminal 1 to fix the login bug"
///   "close the terminals"
extension CommandParser {
    static let terminalNouns = PhraseMatcher(phrases: [
        "terminals", "terminal", "terminal windows", "terminal window", "terminal panes", "terminal pane",
        "terminal tabs", "terminal tab", "terminal splits", "shells", "shell"
    ])
    static let openTerminalVerbs = PhraseMatcher(phrases: [
        "open", "open up", "create", "make", "start", "spawn", "add", "give me", "launch", "bring up"
    ])
    static let sideBySide = PhraseMatcher(phrases: [
        "side by side", "next to each other", "in a split", "split", "in split view", "in parallel",
        "split side by side", "in a row"
    ])
    static let runningWords = PhraseMatcher(phrases: ["running", "that run", "to run", "with"])
    static let terminalRunVerbs = PhraseMatcher(phrases: [
        "run", "start", "execute", "launch", "type and run", "write and run", "enter and run", "send"
    ])
    static let terminalTypeVerbs = PhraseMatcher(phrases: ["type", "write", "type in", "enter"])
    static let tellVerbs = PhraseMatcher(phrases: ["tell", "ask"])
    static let targetPrepositions: Set<String> = ["in", "on", "inside", "into", "to", "at"]
    static let ordinalWords: [String: Int] = [
        "first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3, "fourth": 4, "4th": 4,
        "fifth": 5, "5th": 5, "sixth": 6, "6th": 6, "left": 1, "middle": 2
    ]
    static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8
    ]
    static let closeTerminalPhrases = PhraseMatcher(phrases: [
        "close the terminals", "close all terminals", "close all the terminals", "close terminals",
        "kill the terminals", "kill all terminals", "kill all the terminals", "close the vox terminals",
        "close all vox terminals"
    ])

    // MARK: Entry point

    func parseIDEClause(_ text: String, _ tokens: [Token], from i: Int) -> [DesktopCommand]? {
        guard i < tokens.count else { return nil }

        if let m = wholeClause(Self.closeTerminalPhrases, tokens, at: i) {
            return chain([.ide(.closeTerminals)], text, tokens, after: m.end)
        }
        if let open = parseOpenTerminals(text, tokens, from: i) { return open }

        // "open file src slash parser slash tokenizer.swift"
        if tokens[i].norm == "open" {
            let j = i + 1
            if j < tokens.count && tokens[j].norm == "file" {
                if let path = Tokenizer.remainder(of: text, tokens: tokens, from: j + 1) {
                    return [.ide(.openFile(path: path))]
                }
            }
            if j < tokens.count && tokens[j].norm == "folder" {
                if let path = Tokenizer.remainder(of: text, tokens: tokens, from: j + 1) {
                    return [.ide(.openFolder(path: path))]
                }
            }
        }

        // "run task <name>" / "run the <name> task"
        if let run = Self.terminalRunVerbs.match(tokens, at: i) {
            let j = i + run.length
            if j < tokens.count && tokens[j].norm == "task" {
                if let name = Tokenizer.remainder(of: text, tokens: tokens, from: j + 1) {
                    return [.ide(.runTask(name: name))]
                }
            }
        }

        // "in terminal 3 run npm test", "on the second terminal type hello"
        if Self.targetPrepositions.contains(tokens[i].norm),
           let target = parseTerminalTarget(tokens, from: i + 1) {
            var j = target.end
            if let run = Self.terminalRunVerbs.match(tokens, at: j) {
                j += run.length
                guard let command = Tokenizer.remainder(of: text, tokens: tokens, from: j) else { return nil }
                return [.ide(.send(target.target, text: command, submit: true))]
            }
            if let type = Self.terminalTypeVerbs.match(tokens, at: j) {
                j += type.length
                guard let command = Tokenizer.remainder(of: text, tokens: tokens, from: j) else { return nil }
                return [.ide(.send(target.target, text: command, submit: false))]
            }
        }

        // "tell terminal 1 to fix the login bug"
        if let tell = Self.tellVerbs.match(tokens, at: i),
           let target = parseTerminalTarget(tokens, from: i + tell.length) {
            var j = target.end
            if j < tokens.count, tokens[j].norm == "to" { j += 1 }
            guard let message = Tokenizer.remainder(of: text, tokens: tokens, from: j) else { return nil }
            return [.ide(.send(target.target, text: message, submit: true))]
        }

        // "run claude on one of the terminals", "type hello in terminal 2", and lists of them
        if let run = Self.terminalRunVerbs.match(tokens, at: i) {
            return parseSendList(text, tokens, from: i + run.length, submit: true)
        }
        if let type = Self.terminalTypeVerbs.match(tokens, at: i) {
            return parseSendList(text, tokens, from: i + type.length, submit: false)
        }
        return nil
    }

    // MARK: Opening terminals

    private func parseOpenTerminals(_ text: String, _ tokens: [Token], from i: Int) -> [DesktopCommand]? {
        var j = i
        // "split the terminal into 3", "split the terminal in three"
        if tokens[j].norm == "split" {
            var k = skipArticles(tokens, from: j + 1)
            if let noun = Self.terminalNouns.match(tokens, at: k) {
                k += noun.length
                if k < tokens.count, ["into", "in"].contains(tokens[k].norm), let n = count(tokens, at: k + 1) {
                    return chain([.ide(.openTerminals(count: n, commands: []))], text, tokens, after: k + 2)
                }
            }
            return nil
        }

        if let verb = Self.openTerminalVerbs.match(tokens, at: j) { j += verb.length }
        guard let counted = terminalCount(tokens, at: j) else { return nil }
        let n = counted.0
        var k = counted.1
        if let side = Self.sideBySide.match(tokens, at: k) { k += side.length }

        // "... running claude, freebuff and npm run dev"
        if let running = Self.runningWords.match(tokens, at: k),
           let list = Tokenizer.remainder(of: text, tokens: tokens, from: k + running.length) {
            let commands = splitList(list)
            if !commands.isEmpty {
                return [.ide(.openTerminals(count: max(n, commands.count), commands: commands))]
            }
        }
        return chain([.ide(.openTerminals(count: n, commands: []))], text, tokens, after: k)
    }

    /// "3 terminals", "a new terminal", "three terminal windows" -> (3, index after the noun)
    func terminalCount(_ tokens: [Token], at k: Int) -> (Int, Int)? {
        guard let n = count(tokens, at: k) else { return nil }
        var e = k + 1
        while e < tokens.count, ["new", "more", "extra", "separate", "vox"].contains(tokens[e].norm) { e += 1 }
        guard let noun = Self.terminalNouns.match(tokens, at: e) else { return nil }
        return (n, e + noun.length)
    }

    private func count(_ tokens: [Token], at k: Int) -> Int? {
        guard k < tokens.count else { return nil }
        let word = tokens[k].norm
        let n = Int(word) ?? Self.numberWords[word] ?? (["a", "an", "another"].contains(word) ? 1 : nil)
        guard let n, (1...8).contains(n) else { return nil }
        return n
    }

    // MARK: Targets

    /// "terminal 2", "the second terminal", "the second one", "the second",
    /// "one of the terminals", "a terminal", "the terminal".
    func parseTerminalTarget(_ tokens: [Token], from start: Int) -> (target: IDETerminalTarget, end: Int)? {
        var j = start
        guard j < tokens.count else { return nil }

        if ["one", "any", "either", "each"].contains(tokens[j].norm), j + 1 < tokens.count, tokens[j + 1].norm == "of" {
            j = skipArticles(tokens, from: j + 2)
            while j < tokens.count, ["vox", "open", "new"].contains(tokens[j].norm) { j += 1 }
            guard let noun = Self.terminalNouns.match(tokens, at: j) else { return nil }
            return (.any, j + noun.length)
        }

        var hadArticle = false
        if ["a", "an", "any", "another", "the", "my"].contains(tokens[j].norm) {
            j += 1
            hadArticle = true
        }
        while j < tokens.count, ["new", "vox", "free", "empty"].contains(tokens[j].norm) { j += 1 }
        guard j < tokens.count else { return nil }

        // Ordinal first: "the second terminal", "the second one", "the second"
        if let n = Self.ordinalWords[tokens[j].norm] {
            var e = j + 1
            if let noun = Self.terminalNouns.match(tokens, at: e) {
                e += noun.length
            } else if e < tokens.count, tokens[e].norm == "one" {
                e += 1
            } else if !hadArticle {
                return nil
            }
            return (.number(n), e)
        }

        // Noun first: "terminal 2", "terminal number two", "the terminal"
        if let noun = Self.terminalNouns.match(tokens, at: j) {
            var e = j + noun.length
            if e < tokens.count, tokens[e].norm == "number" { e += 1 }
            if e < tokens.count, let n = Int(tokens[e].norm) ?? Self.numberWords[tokens[e].norm] {
                return (.number(n), e + 1)
            }
            return (.any, e)
        }
        return nil
    }

    // MARK: Sending

    /// "<cmd> in <target>[, <cmd> in <target> and <cmd> in <target>]"
    private func parseSendList(_ text: String, _ tokens: [Token], from start: Int, submit: Bool) -> [DesktopCommand]? {
        var commands: [DesktopCommand] = []
        var begin = start
        var consumed = start
        var currentSubmit = submit

        while begin < tokens.count {
            // Find the first "in/on <target>" that ends this clause.
            var found: (prepIndex: Int, target: IDETerminalTarget, end: Int)?
            var k = begin + 1
            while k < tokens.count {
                if Self.targetPrepositions.contains(tokens[k].norm),
                   let target = parseTerminalTarget(tokens, from: k + 1),
                   isClauseBoundary(text, tokens, at: target.end, explicit: target.target != .any) {
                    found = (k, target.target, target.end)
                    break
                }
                k += 1
            }
            guard let hit = found else { break }
            let command = String(text[tokens[begin].range.lowerBound..<tokens[hit.prepIndex - 1].range.upperBound])
            commands.append(.ide(.send(hit.target, text: command, submit: currentSubmit)))
            consumed = hit.end

            // Continue after ", " / " and " with another "<cmd> in <target>", with or without a verb.
            var next = hit.end
            if next < tokens.count, let brk = Self.clauseBreaks.match(tokens, at: next) { next += brk.length }
            guard next < tokens.count else { break }
            if let run = Self.terminalRunVerbs.match(tokens, at: next) {
                next += run.length
                currentSubmit = true
            } else if let type = Self.terminalTypeVerbs.match(tokens, at: next) {
                next += type.length
                currentSubmit = false
            }
            begin = next
        }

        guard !commands.isEmpty else { return nil }
        // Anything after the last send that isn't another send (e.g. "and open safari") chains normally.
        if consumed < tokens.count {
            return chain(commands, text, tokens, after: consumed) ?? commands
        }
        return commands
    }

    /// Where a "… in <target>" clause may end: end of utterance, "and"/"then", a comma
    /// in the original text, or (speech has no commas) right before another
    /// "<cmd> in <explicit target>" later in the sentence.
    private func isClauseBoundary(_ text: String, _ tokens: [Token], at index: Int, explicit: Bool) -> Bool {
        if index >= tokens.count { return true }
        if Self.clauseBreaks.match(tokens, at: index) != nil { return true }
        let gap = text[tokens[index - 1].range.upperBound..<tokens[index].range.lowerBound]
        if gap.contains(",") || gap.contains(";") { return true }
        guard explicit else { return false }
        var k = index + 1
        while k < tokens.count {
            if Self.targetPrepositions.contains(tokens[k].norm),
               let later = parseTerminalTarget(tokens, from: k + 1), later.target != .any {
                return true
            }
            k += 1
        }
        return false
    }

    /// "claude, freebuff and npm run dev" -> ["claude", "freebuff", "npm run dev"]
    private func splitList(_ list: String) -> [String] {
        list.replacingOccurrences(of: #"\s+(and then|then|and)\s+"#, with: ",", options: .regularExpression)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
