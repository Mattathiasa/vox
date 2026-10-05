import Foundation

/// Finds the last answer on a coding agent's screen, as plain text to speak (Phase 12.3).
/// Claude Code marks answers with "⏺", Gemini with "✦", Codex with "•"; tool calls and their
/// results ("⏺ Bash(npm test)", "⎿ 3 passed"), the input box and the status line are skipped.
public enum ScreenReader {
    static let answerMarkers: [Character] = ["⏺", "●", "✦", "•"]
    static let resultMarkers: [Character] = ["⎿"]
    static let boxCharacters = Set("─│╭╮╰╯┌┐└┘├┤┬┴┼═║╔╗╚╝▌▐█▏▕━┃┏┓┗┛")
    /// Status/help lines that aren't part of any answer.
    static let chrome = [
        "? for shortcuts", "esc to interrupt", "esc to cancel", "shift+tab", "bypass permissions", "auto-accept",
        "accept edits", "context left", "ctrl+", "tokens)", "press esc", "/help for help"
    ]

    public static func lastAnswer(_ screen: String, maxCharacters: Int = 700) -> String {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(clean)
        var picked: [String] = []
        if let start = lines.lastIndex(where: isAnswerStart) {
            for line in lines[start...] {
                if line.text.isEmpty || line.isResult { continue }
                if line.isPrompt || isChrome(line.text) { break }
                if line.text != lines[start].text, isToolCall(line) { break }
                picked.append(line.text)
            }
            if !picked.isEmpty { picked[0] = String(picked[0].drop { answerMarkers.contains($0) || $0 == " " }) }
        } else {
            picked = Array(lines.filter { !$0.text.isEmpty && !$0.isPrompt && !$0.isResult && !isChrome($0.text) }
                .map(\.text).suffix(6))
        }
        var text = picked.joined(separator: " ")
            .filter { !"*`#".contains($0) }
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        if text.count > maxCharacters {
            let cut = text.prefix(maxCharacters)
            let sentence = cut.lastIndex { ".!?".contains($0) }
            text = String(sentence.map { cut[...$0] } ?? cut) + " …"
        }
        return text
    }

    struct Line {
        let text: String
        /// The input box ("> ", "❯ ") — where the answer ends.
        let isPrompt: Bool
        let isResult: Bool
    }

    static func clean(_ raw: Substring) -> Line {
        let stripped = String(raw.filter { !boxCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
        let isPrompt = stripped == ">" || stripped.hasPrefix("> ") || stripped == "❯" || stripped.hasPrefix("❯ ")
        let isResult = stripped.first.map(resultMarkers.contains) ?? false
        return Line(text: stripped, isPrompt: isPrompt, isResult: isResult)
    }

    static func isAnswerStart(_ line: Line) -> Bool {
        guard let first = line.text.first, answerMarkers.contains(first) else { return false }
        return !isToolCall(line)
    }

    /// "⏺ Bash(npm test)", "⏺ Update(Sources/App.swift)": a tool call, not words for you.
    static func isToolCall(_ line: Line) -> Bool {
        let body = line.text.drop { answerMarkers.contains($0) || $0 == " " }
        guard let paren = body.firstIndex(of: "("), paren > body.startIndex else { return false }
        return body[..<paren].allSatisfy { $0.isLetter || $0 == "_" }
    }

    static func isChrome(_ text: String) -> Bool {
        let lower = text.lowercased()
        return chrome.contains { lower.contains($0) }
    }
}
