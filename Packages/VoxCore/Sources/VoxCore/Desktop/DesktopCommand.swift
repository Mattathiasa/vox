import Foundation

/// Something Vox does to the Mac's GUI, as opposed to a tmux tool.
public enum DesktopCommand: Equatable, Sendable {
    /// "open safari": the spoken name, resolved against installed apps by the engine.
    case openApp(String)
    /// "create a note called groceries"
    case createNote(String)
    /// "search for swift concurrency"
    case webSearch(String)
    /// "go to github.com": the spoken address, normalized by `WebAddress`.
    case openURL(String)
    /// "type hello world": typed into the frontmost app.
    case typeText(String)
    /// "press command s", or a named shortcut like "close tab" / "copy"
    case pressKey(KeyCombo)
    /// "close safari", "quit notes": politely quit (the app may ask to save)
    case quitApp(String)
    /// "switch to safari": bring a running app forward (launches it if needed)
    case focusApp(String)
    /// "hide slack"
    case hideApp(String)
    /// "volume up", "mute", "set volume to 40"
    case volume(VolumeChange)
    /// "play", "pause", "next song"
    case media(MediaKey)
    /// "what time is it", "what's 12 times 8": answered, not acted on
    case answer(Question)
    /// "set a timer for 5 minutes"
    case timer(seconds: Int)
    /// "cancel the timer"
    case cancelTimers
    /// "remind me to call mom in 10 minutes"
    case reminder(String, inSeconds: Int?)
    /// "open downloads", "open the chirp project": a standard folder or a config project, in Finder
    case openFolder(String)
    /// "open chirp in kiro": a config project opened with an app
    case openProject(project: String, app: String)
    /// "search youtube for lofi", "directions to bole airport"
    case siteSearch(SearchSite, String)
    /// "dark mode", "turn off the screen"
    case system(SystemAction)
    /// Terminals in a VS Code–based IDE, through the Vox Bridge extension
    case ide(IDECommand)
    /// Read the URL (and title) of the frontmost Safari tab.
    case safariReadTab
    /// Run JavaScript in the frontmost Safari tab. Requires Accessibility + Develop menu enabled.
    case safariRunJS(String)
    /// Paste text into a specific app via the pasteboard: focus app, save clipboard,
    /// set new text, Cmd+V, Return, restore clipboard.
    case sendMessageToApp(app: String, text: String)
}

public enum MediaKey: String, Equatable, Sendable {
    case playPause, next, previous
}

public enum Question: Equatable, Sendable {
    case time, date, battery, clipboard, openApps
    case calculation(String)
}

public enum SearchSite: String, CaseIterable, Equatable, Sendable {
    case youtube, github, amazon, wikipedia, maps, images, reddit, stackoverflow

    public func url(for query: String) -> URL {
        let q = WebAddress.encode(query)
        let base: String
        switch self {
        case .youtube: base = "https://www.youtube.com/results?search_query="
        case .github: base = "https://github.com/search?q="
        case .amazon: base = "https://www.amazon.com/s?k="
        case .wikipedia: base = "https://en.wikipedia.org/w/index.php?search="
        case .maps: base = "https://maps.apple.com/?q="
        case .images: base = "https://www.google.com/search?tbm=isch&q="
        case .reddit: base = "https://www.reddit.com/search/?q="
        case .stackoverflow: base = "https://stackoverflow.com/search?q="
        }
        return URL(string: base + q)!
    }

    /// Spoken names for each site.
    public var phrases: [String] {
        switch self {
        case .youtube: return ["youtube", "you tube"]
        case .github: return ["github", "git hub"]
        case .amazon: return ["amazon"]
        case .wikipedia: return ["wikipedia", "wiki"]
        case .maps: return ["maps", "the map", "apple maps", "google maps", "map"]
        case .images: return ["images", "google images", "pictures"]
        case .reddit: return ["reddit"]
        case .stackoverflow: return ["stack overflow", "stackoverflow"]
        }
    }
}

public enum SystemAction: Equatable, Sendable {
    /// nil = toggle
    case darkMode(Bool?)
    case screenOff
}

public enum VolumeChange: Equatable, Sendable {
    case up, down, mute, unmute
    /// 0...100
    case set(Int)
}

/// Effects on the Mac. Implemented in the app target (AppKit, AppleScript,
/// CGEvent); faked in tests. Main-actor because all of those APIs are.
@MainActor
public protocol DesktopControlling: AnyObject, Sendable {
    func openApp(at url: URL) async throws
    func openURL(_ url: URL) async throws
    func createNote(_ text: String) async throws
    func typeText(_ text: String) async throws
    func pressKey(_ combo: KeyCombo) async throws
    /// Returns false if the app wasn't running.
    func quitApp(at url: URL) async throws -> Bool
    /// Returns false if the app wasn't running.
    func hideApp(at url: URL) async throws -> Bool
    func setVolume(_ change: VolumeChange) async throws
    func pressMediaKey(_ key: MediaKey) async throws
    /// Raw `pmset -g batt` output.
    func batteryReport() async throws -> String
    func clipboardText() async -> String?
    func runningAppNames() async -> [String]
    /// Starts a countdown; the app announces it when done.
    func startTimer(seconds: Int) async
    /// Returns how many timers were cancelled.
    func cancelTimers() async -> Int
    func createReminder(_ text: String, dueInSeconds: Int?) async throws
    func open(_ fileURL: URL, withAppAt appURL: URL) async throws
    func setDarkMode(_ on: Bool?) async throws
    func screenOff() async throws
    /// Returns the URL and title of the frontmost tab in Safari.
    func safariTabInfo() async throws -> (url: String, title: String)
    /// Runs JavaScript in the frontmost Safari tab. Returns the result string.
    func runJavaScriptInSafari(_ script: String) async throws -> String
    /// Sets the system clipboard to the given text.
    func setClipboard(_ text: String) async throws

    /// Opens Terminal running a command Vox built itself (a tmux attach), never speech.
    func openTerminal(running command: String) async throws
}

// MARK: - Key combos

public struct KeyCombo: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Modifier: String, CaseIterable, Sendable, Hashable {
        case command, shift, option, control
    }

    /// Canonical key name: "a"..."z", "0"..."9", or one of `KeyCombo.specialKeys`.
    public var key: String
    public var modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let specialKeys: Set<String> = [
        "return", "tab", "space", "delete", "escape", "up", "down", "left", "right",
        "pageup", "pagedown", "home", "end", "leftbracket", "rightbracket", "equal", "minus", "comma"
    ]

    static let modifierWords: [String: Modifier] = [
        "command": .command, "cmd": .command, "commander": .command,
        "shift": .shift,
        "option": .option, "alt": .option, "opt": .option,
        "control": .control, "ctrl": .control
    ]

    static let keyAliases: [String: String] = [
        "enter": "return", "return": "return",
        "backspace": "delete", "delete": "delete",
        "esc": "escape", "escape": "escape", "escaped": "escape",
        "spacebar": "space", "space": "space",
        "tab": "tab",
        "up": "up", "down": "down", "left": "left", "right": "right",
        "pageup": "pageup", "pagedown": "pagedown", "home": "home", "end": "end",
        "equal": "equal", "equals": "equal", "minus": "minus", "dash": "minus", "comma": "comma",
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"
    ]

    static let ignoredWords: Set<String> = ["the", "key", "button", "plus", "and", "arrow", "keys"]

    /// "command shift t", "cmd+s", "the enter key" -> KeyCombo. nil if there is
    /// not exactly one non-modifier key.
    public static func parse(_ spoken: String) -> KeyCombo? {
        var modifiers = Set<Modifier>()
        var keys: [String] = []
        let joined = " " + Tokenizer.words(spoken).joined(separator: " ") + " "
        let text = joined
            .replacingOccurrences(of: " page up ", with: " pageup ")
            .replacingOccurrences(of: " page down ", with: " pagedown ")
        for word in text.split(separator: " ").map(String.init) where !ignoredWords.contains(word) {
            if let modifier = modifierWords[word] {
                modifiers.insert(modifier)
            } else if let alias = keyAliases[word] {
                keys.append(alias)
            } else if word.count == 1, let ch = word.first, ch.isLetter || ch.isNumber {
                keys.append(word)
            } else {
                return nil
            }
        }
        guard keys.count == 1 else { return nil }
        return KeyCombo(key: keys[0], modifiers: modifiers)
    }

    /// Everyday shortcuts you can say by name ("close tab", "copy", "scroll down").
    /// Matched only as a whole clause, so "copy the file to src" isn't a shortcut.
    public static let named: [(phrases: [String], combo: KeyCombo)] = [
        (["close window", "close the window", "close this window"], KeyCombo(key: "w", modifiers: [.command])),
        (["close tab", "close the tab", "close this tab"], KeyCombo(key: "w", modifiers: [.command])),
        (["new tab", "open a new tab", "open new tab"], KeyCombo(key: "t", modifiers: [.command])),
        (["new window", "open a new window", "open new window"], KeyCombo(key: "n", modifiers: [.command])),
        (["reopen tab", "reopen closed tab", "reopen the last tab"], KeyCombo(key: "t", modifiers: [.command, .shift])),
        (["next tab"], KeyCombo(key: "tab", modifiers: [.control])),
        (["previous tab", "last tab"], KeyCombo(key: "tab", modifiers: [.control, .shift])),
        (["minimize", "minimise", "minimize window", "minimize this"], KeyCombo(key: "m", modifiers: [.command])),
        (["full screen", "fullscreen", "toggle full screen", "enter full screen", "exit full screen"],
         KeyCombo(key: "f", modifiers: [.control, .command])),
        (["hide this", "hide this app", "hide window"], KeyCombo(key: "h", modifiers: [.command])),
        (["quit this app", "quit this", "close this app", "quit the app"], KeyCombo(key: "q", modifiers: [.command])),
        (["go back", "back"], KeyCombo(key: "leftbracket", modifiers: [.command])),
        (["go forward", "forward"], KeyCombo(key: "rightbracket", modifiers: [.command])),
        (["reload", "refresh", "reload page", "refresh page", "reload the page", "refresh the page"],
         KeyCombo(key: "r", modifiers: [.command])),
        (["copy", "copy that", "copy this"], KeyCombo(key: "c", modifiers: [.command])),
        (["paste", "paste it", "paste that"], KeyCombo(key: "v", modifiers: [.command])),
        (["cut", "cut that", "cut this"], KeyCombo(key: "x", modifiers: [.command])),
        (["undo", "undo that"], KeyCombo(key: "z", modifiers: [.command])),
        (["redo", "redo that"], KeyCombo(key: "z", modifiers: [.command, .shift])),
        (["save", "save it", "save this", "save file", "save the file"], KeyCombo(key: "s", modifiers: [.command])),
        (["select all", "select everything"], KeyCombo(key: "a", modifiers: [.command])),
        (["find", "find in page", "search this page"], KeyCombo(key: "f", modifiers: [.command])),
        (["scroll down", "page down"], KeyCombo(key: "pagedown")),
        (["scroll up", "page up"], KeyCombo(key: "pageup")),
        (["scroll to top", "go to top", "go to the top", "scroll to the top"], KeyCombo(key: "up", modifiers: [.command])),
        (["scroll to bottom", "go to bottom", "go to the bottom", "scroll to the bottom"],
         KeyCombo(key: "down", modifiers: [.command])),
        (["zoom in"], KeyCombo(key: "equal", modifiers: [.command])),
        (["zoom out"], KeyCombo(key: "minus", modifiers: [.command])),
        (["take a screenshot", "screenshot", "take screenshot"], KeyCombo(key: "3", modifiers: [.command, .shift])),
        (["screenshot selection", "screenshot part of the screen"], KeyCombo(key: "4", modifiers: [.command, .shift])),
        // System
        (["lock screen", "lock the screen", "lock my mac", "lock the computer", "lock computer"],
         KeyCombo(key: "q", modifiers: [.control, .command])),
        (["spotlight", "open spotlight", "search my mac"], KeyCombo(key: "space", modifiers: [.command])),
        (["mission control", "show all windows"], KeyCombo(key: "up", modifiers: [.control])),
        (["app windows", "show app windows"], KeyCombo(key: "down", modifiers: [.control])),
        (["next desktop", "desktop right", "switch desktop right", "next space"],
         KeyCombo(key: "right", modifiers: [.control])),
        (["previous desktop", "desktop left", "switch desktop left", "previous space"],
         KeyCombo(key: "left", modifiers: [.control])),
        (["emoji", "emojis", "show emoji", "open emoji picker"], KeyCombo(key: "space", modifiers: [.control, .command])),
        (["switch app", "switch apps", "last app", "previous app"], KeyCombo(key: "tab", modifiers: [.command])),
        // Text editing
        (["new line", "newline", "next line"], KeyCombo(key: "return")),
        (["new paragraph"], KeyCombo(key: "return", modifiers: [.shift])),
        (["delete word", "delete last word", "delete the last word"], KeyCombo(key: "delete", modifiers: [.option])),
        (["delete line", "delete the line", "clear line"], KeyCombo(key: "delete", modifiers: [.command])),
        (["bold", "make it bold"], KeyCombo(key: "b", modifiers: [.command])),
        (["italic", "italics", "make it italic"], KeyCombo(key: "i", modifiers: [.command])),
        (["underline", "underline it"], KeyCombo(key: "u", modifiers: [.command])),
        (["go to start of line", "start of line", "beginning of line"], KeyCombo(key: "left", modifiers: [.command])),
        (["go to end of line", "end of line"], KeyCombo(key: "right", modifiers: [.command])),
        // App
        (["preferences", "settings for this app", "open preferences", "app settings"],
         KeyCombo(key: "comma", modifiers: [.command])),
        (["print", "print this"], KeyCombo(key: "p", modifiers: [.command])),
        (["close all windows"], KeyCombo(key: "w", modifiers: [.command, .option])),
        (["new folder"], KeyCombo(key: "n", modifiers: [.command, .shift])),
        (["new document", "new file"], KeyCombo(key: "n", modifiers: [.command])),
        (["open file", "open a file"], KeyCombo(key: "o", modifiers: [.command])),
        (["private window", "new private window", "incognito"], KeyCombo(key: "n", modifiers: [.command, .shift])),
        (["address bar", "focus address bar", "go to address bar"], KeyCombo(key: "l", modifiers: [.command])),
        (["bookmark this", "bookmark this page", "add bookmark"], KeyCombo(key: "d", modifiers: [.command]))
    ]

    public var description: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        let mods = order.filter(modifiers.contains).map(\.rawValue)
        return (mods + [key]).joined(separator: "+")
    }
}

// MARK: - Web addresses

public enum WebAddress {
    /// "github dot com", "GitHub.com/anthropics" -> https URL. nil unless the
    /// result has a plausible host (letters/digits/hyphens with at least one dot).
    public static func url(fromSpoken spoken: String) -> URL? {
        var s = " " + spoken.lowercased() + " "
        s = s.replacingOccurrences(of: " dot ", with: ".")
        s = s.replacingOccurrences(of: " slash ", with: "/")
        s = s.components(separatedBy: .whitespacesAndNewlines).joined()
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:"))
        if !(s.hasPrefix("http://") || s.hasPrefix("https://")) {
            s = "https://" + s
        }
        guard let url = URL(string: s),
              let scheme = url.scheme, scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard host.unicodeScalars.allSatisfy(allowed.contains),
              !host.split(separator: ".", omittingEmptySubsequences: false).contains(where: \.isEmpty)
        else { return nil }
        return url
    }

    public static func searchURL(for query: String) -> URL {
        URL(string: "https://www.google.com/search?q=" + encode(query))!
    }

    public static func encode(_ query: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// "open youtube" when there's no YouTube app.
    public static let knownSites: [String: String] = [
        "youtube": "https://www.youtube.com", "you tube": "https://www.youtube.com",
        "gmail": "https://mail.google.com", "google": "https://www.google.com",
        "google drive": "https://drive.google.com", "drive": "https://drive.google.com",
        "google docs": "https://docs.google.com", "google calendar": "https://calendar.google.com",
        "github": "https://github.com", "git hub": "https://github.com",
        "chatgpt": "https://chatgpt.com", "chat gpt": "https://chatgpt.com",
        "claude dot ai": "https://claude.ai", "claude ai": "https://claude.ai",
        "twitter": "https://x.com", "linkedin": "https://www.linkedin.com", "linked in": "https://www.linkedin.com",
        "facebook": "https://www.facebook.com", "instagram": "https://www.instagram.com",
        "reddit": "https://www.reddit.com", "netflix": "https://www.netflix.com",
        "stack overflow": "https://stackoverflow.com", "stackoverflow": "https://stackoverflow.com",
        "whatsapp web": "https://web.whatsapp.com", "telegram web": "https://web.telegram.org",
        "vercel": "https://vercel.com", "supabase": "https://supabase.com/dashboard",
        "firebase": "https://console.firebase.google.com", "lovable": "https://lovable.dev"
    ]

    public static func knownSite(_ spoken: String) -> URL? {
        var words = Tokenizer.words(spoken)
        while let last = words.last, ["website", "site", "dot", "com"].contains(last) { words.removeLast() }
        return knownSites[words.joined(separator: " ")].flatMap(URL.init(string:))
    }
}

extension DesktopCommand {
    /// True when this command opens or brings forward an app window.
    /// The engine uses this to pipeline: the launch fires immediately, and the
    /// next action that needs the app frontmost waits `focusDelaySeconds`.
    public var launchesApp: Bool {
        switch self {
        case .openApp, .focusApp: return true
        default: return false
        }
    }
}
