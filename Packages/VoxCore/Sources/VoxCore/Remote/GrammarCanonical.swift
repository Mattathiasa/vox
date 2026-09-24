import Foundation

/// One-line form of router actions, identical to windows/src/canonical.js, so
/// shared/grammar-cases.json can check the Swift and JavaScript grammars agree.
public enum GrammarCanonical {
    static func f(_ parts: [String?]) -> String {
        parts.map { $0 ?? "" }.joined(separator: "|")
    }

    public static func line(_ action: RouterAction) -> String {
        switch action {
        case let .launch(tool, directory, prompt): return f(["launch", tool, directory, prompt])
        case let .focus(tool): return f(["focus", tool])
        case let .send(tool, text): return f(["send", tool, text])
        case let .kill(tool): return f(["kill", tool])
        case .listSessions: return "list"
        case let .interrupt(tool): return f(["interrupt", tool])
        case let .showTool(tool): return f(["show", tool])
        case let .askConfirmation(question): return f(["confirm", question])
        case let .feedback(message):
            return message == SessionRouter.helpText ? "feedback|<help>" : f(["feedback", message])
        case let .llmFallback(request): return f(["llm", request.text])
        case let .desktop(command): return "desktop:" + line(command)
        }
    }

    public static func line(_ c: DesktopCommand) -> String {
        switch c {
        case let .openApp(name): return f(["openApp", name])
        case let .quitApp(name): return f(["quitApp", name])
        case let .focusApp(name): return f(["focusApp", name])
        case let .hideApp(name): return f(["hideApp", name])
        case let .createNote(text): return f(["createNote", text])
        case let .typeText(text): return f(["typeText", text])
        case let .webSearch(query): return f(["webSearch", query])
        case let .openURL(spoken): return f(["openURL", spoken])
        case let .pressKey(combo): return f(["pressKey", combo.description])
        case let .volume(change):
            let value: String
            switch change {
            case .up: value = "up"
            case .down: value = "down"
            case .mute: value = "mute"
            case .unmute: value = "unmute"
            case let .set(level): value = "set \(level)"
            }
            return f(["volume", value])
        case let .media(key): return f(["media", key.rawValue])
        case let .answer(question):
            switch question {
            case .time: return "answer|time"
            case .date: return "answer|date"
            case .battery: return "answer|battery"
            case .clipboard: return "answer|clipboard"
            case .openApps: return "answer|openApps"
            case let .calculation(expression): return f(["answer", "calculation", expression])
            }
        case let .timer(seconds): return f(["timer", String(seconds)])
        case .cancelTimers: return "cancelTimers"
        case let .reminder(text, seconds): return f(["reminder", text, seconds.map(String.init)])
        case let .openFolder(name): return f(["openFolder", name])
        case let .openProject(project, app): return f(["openProject", project, app])
        case let .siteSearch(site, query): return f(["siteSearch", site.rawValue, query])
        case let .system(action):
            switch action {
            case .screenOff: return "system|screenOff"
            case let .darkMode(on): return f(["system", "darkMode", on.map { $0 ? "on" : "off" } ?? "toggle"])
            }
        case .safariReadTab: return "safariReadTab"
        case let .safariRunJS(script): return f(["safariRunJS", script])
        case let .sendMessageToApp(app, text): return f(["sendMessageToApp", app, text])
        case let .ide(command): return "ide:" + line(command)
        }
    }

    static func line(_ i: IDECommand) -> String {
        func target(_ t: IDETerminalTarget) -> String {
            if case let .number(n) = t { return String(n) }
            return "any"
        }
        switch i {
        case let .openTerminals(count, commands): return f(["openTerminals", String(count), commands.joined(separator: ",")])
        case let .send(t, text, submit): return f(["send", target(t), text, submit ? "submit" : "type"])
        case .closeTerminals: return "closeTerminals"
        case let .chat(message, submit): return f(["chat", message, submit ? "submit" : "type"])
        case let .openFile(path): return f(["openFile", path])
        case let .openFolder(path): return f(["openFolder", path])
        case let .runTask(name): return f(["runTask", name])
        }
    }
}
