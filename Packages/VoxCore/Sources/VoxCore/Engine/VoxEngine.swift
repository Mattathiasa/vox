import Foundation

/// A line for the UI log (and later, for spoken feedback).
public struct EngineEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case info, success, warning, error, confirm
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

/// The current screen of one running tool, for the HUD's terminal grid.
public struct SessionScreen: Equatable, Sendable, Identifiable {
    public let tool: String
    public let text: String
    public let exited: Bool
    public var id: String { tool }

    public init(tool: String, text: String, exited: Bool) {
        self.tool = tool
        self.text = text
        self.exited = exited
    }
}

/// Terminal dimensions in character cells.
public struct TerminalSize: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    /// Cells that fit in `width`×`height` points at the given cell size.
    public init(width: Double, height: Double, cellWidth: Double, cellHeight: Double) {
        self.init(columns: Int(max(0, width) / cellWidth), rows: Int(max(0, height) / cellHeight))
    }

    /// Coding agents need some room; tmux needs at least 1×1.
    public var clamped: TerminalSize {
        TerminalSize(columns: min(max(columns, 40), 300), rows: min(max(rows, 10), 120))
    }
}

/// Glues the router (decisions) to tmux (effects). Input text can come from
/// the keyboard today and from speech-to-text in Phase 3; the engine doesn't care.
public actor VoxEngine {
    private var router: SessionRouter
    private let config: VoxConfig
    private let tmux: TmuxAdapter
    private let apps: AppCatalog
    private let desktop: (any DesktopControlling)?
    private let ideBridge: (any IDEBridging)?
    private let llm: (any LLMFallback)?
    /// The VS Code–based IDE opened most recently ("Antigravity"): IDE commands go there.
    private var preferredIDE: String?
    /// How long IDE commands wait for the IDE's bridge (e.g. while the IDE is still starting).
    public var ideWaitSeconds: Double = 25
    private let pause: @Sendable (Double) async -> Void

    /// Delay between typing text and pressing Enter. Some TUIs drop an Enter
    /// that arrives in the same burst as the text.
    public var submitDelaySeconds: Double = 0.15

    /// Timeout for LLM fallback calls (Phase 6).
    public var llmTimeoutSeconds: Double = 8

    public init(
        config: VoxConfig,
        tmux: TmuxAdapter,
        apps: AppCatalog = AppCatalog(entries: []),
        desktop: (any DesktopControlling)? = nil,
        ideBridge: (any IDEBridging)? = nil,
        llm: (any LLMFallback)? = nil,
        llmTimeoutSeconds: Double = 8,
        pause: @escaping @Sendable (Double) async -> Void = { seconds in
            _ = try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.config = config
        self.router = SessionRouter(config: config)
        self.tmux = tmux
        self.apps = apps
        self.desktop = desktop
        self.ideBridge = ideBridge
        self.llm = llm
        self.llmTimeoutSeconds = llmTimeoutSeconds
        self.pause = pause
    }

    public var mode: RouterMode { router.mode }
    public var pendingQuestion: String? { router.pending?.question }

    /// tmux session of the tool currently in pass-through mode.
    public var lockedSession: String? {
        router.mode.lockedTool.map(SessionNaming.sessionName(forTool:))
    }

    public func handle(_ text: String) async -> [EngineEvent] {
        await run(router.handle(text))
    }

    /// The HUD's per-terminal command box. Same safety rules as everything else.
    public func send(_ text: String, toTool tool: String) async -> [EngineEvent] {
        await run(router.sendTo(tool: tool, text: text))
    }

    /// The HUD's per-terminal key buttons (Enter, Esc, ↑, ↓, Tab, ⌃C…).
    public func press(_ key: String, inTool tool: String) -> [EngineEvent] {
        let session = SessionNaming.sessionName(forTool: tool)
        guard tmux.hasSession(session) else { return [EngineEvent(.warning, "\(tool) isn't running.")] }
        do {
            try tmux.sendKey(session: session, key: key)
            return []
        } catch {
            return [EngineEvent(.error, String(describing: error))]
        }
    }

    private func run(_ actions: [RouterAction]) async -> [EngineEvent] {
        var events: [EngineEvent] = []
        var needsFocusDelay = false
        for action in actions {
            // An openApp/focusApp fires immediately so the app starts launching.
            // The next action that actually uses the frontmost window waits for
            // it to come forward — but only as long as it hasn't already elapsed.
            if needsFocusDelay, action.needsFrontmostApp {
                await pause(focusDelaySeconds)
                needsFocusDelay = false
            }
            let result = await execute(action)
            events += result
            if case .desktop(let cmd) = action, cmd.launchesApp {
                needsFocusDelay = true
            } else {
                needsFocusDelay = false
            }
        }
        return events
    }

    /// How long to wait for an app to come forward before acting on it.
    /// Exposed for tests and future config.
    public var focusDelaySeconds: Double = 0.8

    /// Latest screen of the locked tool, for the output view.
    public func lockedOutput(lines: Int = 200) -> String? {
        guard let session = lockedSession else { return nil }
        return try? tmux.capture(session: session, lines: lines)
    }

    public func runningSessions() -> [String] {
        tmux.listSessions()
    }

    /// Screens of every tool Vox is running (not the self-test's sessions).
    public func screens(lines: Int = 150) -> [SessionScreen] {
        tmux.listSessions()
            .filter { !$0.hasPrefix(SessionNaming.prefix + "selftest") }
            .map { session in
                SessionScreen(
                    tool: String(session.dropFirst(SessionNaming.prefix.count)),
                    text: Self.tidy((try? tmux.capture(session: session, lines: lines)) ?? ""),
                    exited: tmux.isPaneDead(session))
            }
    }

    /// Last size sent to each session, so resizes only happen on change.
    private var sizes: [String: TerminalSize] = [:]

    /// Fits every running tool's terminal to `size` (the HUD tile), clamped to sane bounds.
    /// Returns how many sessions were actually resized.
    @discardableResult
    public func fitTerminals(to size: TerminalSize) -> Int {
        let target = size.clamped
        var changed = 0
        for session in tmux.listSessions() where !session.hasPrefix(SessionNaming.prefix + "selftest") {
            guard sizes[session] != target else { continue }
            if (try? tmux.resize(session: session, columns: target.columns, rows: target.rows)) != nil {
                sizes[session] = target
                changed += 1
            }
        }
        return changed
    }

    /// Drops trailing spaces on each line and trailing empty lines (tmux pads to the pane width).
    static func tidy(_ screen: String) -> String {
        var lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var text = String(line)
            while text.last == " " { text.removeLast() }
            return text
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    public func exitPassThrough() {
        router.unlock()
    }

    // MARK: Execution

    private func execute(_ action: RouterAction) async -> [EngineEvent] {
        switch action {
        case let .launch(toolName, directory, prompt):
            return await launch(toolName, directory: directory, prompt: prompt)

        case let .focus(toolName):
            let session = SessionNaming.sessionName(forTool: toolName)
            guard tmux.hasSession(session) else {
                router.unlock()
                return [EngineEvent(.warning, "\(toolName) isn't running. Say \"run \(toolName)\".")]
            }
            return [EngineEvent(.success, "Talking to \(toolName). Say \"exit\" to stop.")]

        case let .send(toolName, text):
            return await send(text, to: toolName)

        case let .kill(toolName):
            let session = SessionNaming.sessionName(forTool: toolName)
            guard tmux.hasSession(session) else {
                return [EngineEvent(.info, "\(toolName) wasn't running.")]
            }
            do {
                try tmux.kill(session: session)
                return [EngineEvent(.success, "Killed \(toolName).")]
            } catch {
                return [EngineEvent(.error, String(describing: error))]
            }

        case .listSessions:
            let sessions = tmux.listSessions()
            if sessions.isEmpty { return [EngineEvent(.info, "No tools running.")] }
            let names = sessions.map { String($0.dropFirst(SessionNaming.prefix.count)) }
            return [EngineEvent(.info, "Running: " + names.joined(separator: ", "))]

        case let .desktop(command):
            return await runDesktop(command)

        case let .interrupt(toolName):
            let session = SessionNaming.sessionName(forTool: toolName)
            guard tmux.hasSession(session) else {
                return [EngineEvent(.info, "\(toolName) isn't running.")]
            }
            do {
                try tmux.interrupt(session: session)
                return [EngineEvent(.success, "Interrupted \(toolName).")]
            } catch {
                return [EngineEvent(.error, String(describing: error))]
            }

        case let .showTool(toolName):
            let session = SessionNaming.sessionName(forTool: toolName)
            guard tmux.hasSession(session) else {
                return [EngineEvent(.warning, "\(toolName) isn't running. Say \"run \(toolName)\".")]
            }
            guard let desktop else { return [EngineEvent(.error, "Desktop control isn't available.")] }
            do {
                try await desktop.openTerminal(running: TmuxAdapter.attachCommand(session: session))
                return [EngineEvent(.success, "Showing \(toolName) in Terminal.")]
            } catch {
                return [EngineEvent(.error, String(describing: error))]
            }

        case let .askConfirmation(question):
            return [EngineEvent(.confirm, question)]

        case let .feedback(message):
            return [EngineEvent(.info, message)]

        case let .llmFallback(request):
            return await runLLMFallback(request)
        }
    }

    /// Phase 6: when the rule-based parser returns `.unknown`, ask the LLM.
    /// The LLM must reply with a Vox command string (never shell text); we
    /// re-feed it through the router so all safety checks still apply.
    /// Includes a timeout and logs every model decision.
    private func runLLMFallback(_ request: LLMRequest) async -> [EngineEvent] {
        guard let llm else {
            return [EngineEvent(.info,
                "Didn't catch a command in \"\(request.text)\"."
            )]
        }
        do {
            let result = try await withTimeout(llmTimeoutSeconds) {
                try await llm.plan(request: request)
            }
            let logEvent = logLLMDecision(result)
            switch result {
            case let .command(command):
                if command.isEmpty {
                    return [logEvent, EngineEvent(.info, "Hmm, I'm not sure what to do.")]
                }
                // Re-route through the parser — safety checks are applied again.
                let actions = router.handle(command)
                // Guard against LLM → unknown → LLM recursion.
                if actions.count == 1, case .llmFallback = actions.first {
                    return [logEvent, EngineEvent(.info,
                        "Didn't catch a command in \"\(command)\"."
                    )]
                }
                let runEvents = await run(actions)
                return [logEvent] + runEvents
            case let .feedback(message):
                return [logEvent, EngineEvent(.info, message)]
            }
        } catch LLMError.timedOut {
            return [EngineEvent(.info,
                "The LLM took too long. Try rephrasing."
            )]
        } catch {
            return [EngineEvent(.error,
                "LLM fallback failed: \(String(describing: error))."
            )]
        }
    }

    /// Logs the LLM's decision as an event (for the HUD log).
    private func logLLMDecision(_ result: LLMResult) -> EngineEvent {
        switch result {
        case let .command(command):
            return EngineEvent(.info, "LLM → \"\(command)\"")
        case let .feedback(message):
            return EngineEvent(.info, "LLM feedback: \"\(message)\"")
        }
    }

    private func runDesktop(_ command: DesktopCommand) async -> [EngineEvent] {
        guard let desktop else {
            return [EngineEvent(.error, "Desktop control isn't available.")]
        }
        do {
            switch command {
            case let .openApp(spoken):
                guard let app = apps.find(spoken) else {
                    // Not an app: maybe a website ("open youtube"), a project, or an address.
                    if let site = WebAddress.knownSite(spoken) ?? WebAddress.url(fromSpoken: spoken) {
                        try await desktop.openURL(site)
                        return [EngineEvent(.success, "Opened \(site.host ?? spoken).")]
                    }
                    if let folder = folderURL(spoken) {
                        try await desktop.openURL(folder)
                        return [EngineEvent(.success, "Opened \(folder.lastPathComponent) in Finder.")]
                    }
                    return [EngineEvent(.warning, "No app called \"\(spoken)\" found in Applications.")]
                }
                try await desktop.openApp(at: app.url)
                noteIfIDE(app)
                return [EngineEvent(.success, "Opened \(app.name).")]

            case let .createNote(text):
                try await desktop.createNote(text)
                return [EngineEvent(.success, text.isEmpty ? "Created a note." : "Created a note: \(text)")]

            case let .webSearch(query):
                try await desktop.openURL(WebAddress.searchURL(for: query))
                return [EngineEvent(.success, "Searching for \(query).")]

            case let .openURL(spoken):
                guard let url = WebAddress.url(fromSpoken: spoken) else {
                    return [EngineEvent(.warning, "\"\(spoken)\" doesn't look like a web address.")]
                }
                try await desktop.openURL(url)
                return [EngineEvent(.success, "Opened \(url.host ?? url.absoluteString).")]

            case let .typeText(text):
                try await desktop.typeText(text)
                return [EngineEvent(.success, "Typed: \(text)")]

            case let .pressKey(combo):
                try await desktop.pressKey(combo)
                return [EngineEvent(.success, "Pressed \(combo).")]

            case let .quitApp(spoken):
                guard let app = apps.find(spoken) else {
                    return [EngineEvent(.warning, "No app called \"\(spoken)\" found.")]
                }
                let wasRunning = try await desktop.quitApp(at: app.url)
                return [wasRunning ? EngineEvent(.success, "Quit \(app.name).")
                                   : EngineEvent(.info, "\(app.name) isn't running.")]

            case let .focusApp(spoken):
                guard let app = apps.find(spoken) else {
                    return [EngineEvent(.warning, "No app called \"\(spoken)\" found.")]
                }
                try await desktop.openApp(at: app.url)
                noteIfIDE(app)
                return [EngineEvent(.success, "Switched to \(app.name).")]

            case let .hideApp(spoken):
                guard let app = apps.find(spoken) else {
                    return [EngineEvent(.warning, "No app called \"\(spoken)\" found.")]
                }
                let wasRunning = try await desktop.hideApp(at: app.url)
                return [wasRunning ? EngineEvent(.success, "Hid \(app.name).")
                                   : EngineEvent(.info, "\(app.name) isn't running.")]

            case let .volume(change):
                try await desktop.setVolume(change)
                let label: String
                switch change {
                case .up: label = "Volume up."
                case .down: label = "Volume down."
                case .mute: label = "Muted."
                case .unmute: label = "Unmuted."
                case let .set(level): label = "Volume \(level)%."
                }
                return [EngineEvent(.success, label)]

            case let .media(key):
                try await desktop.pressMediaKey(key)
                switch key {
                case .playPause: return [EngineEvent(.success, "Play/pause.")]
                case .next: return [EngineEvent(.success, "Next track.")]
                case .previous: return [EngineEvent(.success, "Previous track.")]
                }

            case let .answer(question):
                return [EngineEvent(.info, try await answer(question, desktop: desktop))]

            case let .timer(seconds):
                await desktop.startTimer(seconds: seconds)
                return [EngineEvent(.info, "Timer set for \(SpokenDuration.describe(seconds)).")]

            case .cancelTimers:
                let count = await desktop.cancelTimers()
                return [EngineEvent(.info, count == 0 ? "No timers running."
                                                        : "Cancelled \(count) timer\(count == 1 ? "" : "s").")]

            case let .reminder(text, inSeconds):
                try await desktop.createReminder(text, dueInSeconds: inSeconds)
                let when = inSeconds.map { " in \(SpokenDuration.describe($0))" } ?? ""
                return [EngineEvent(.info, "I'll remind you to \(text)\(when).")]

            case let .openFolder(name):
                guard let folder = folderURL(name) else {
                    return [EngineEvent(.warning, "No folder or project called \"\(name)\".")]
                }
                try await desktop.openURL(folder)
                return [EngineEvent(.success, "Opened \(folder.lastPathComponent) in Finder.")]

            case let .openProject(projectName, appName):
                guard let folder = folderURL(projectName) else {
                    return [EngineEvent(.warning, "No project called \"\(projectName)\" in your config.")]
                }
                guard let app = apps.find(appName) else {
                    return [EngineEvent(.warning, "No app called \"\(appName)\" found.")]
                }
                try await desktop.open(folder, withAppAt: app.url)
                return [EngineEvent(.success, "Opened \(projectName) in \(app.name).")]

            case let .siteSearch(site, query):
                try await desktop.openURL(site.url(for: query))
                return [EngineEvent(.success, "Searching \(site.rawValue) for \(query).")]

            case let .ide(command):
                return await runIDE(command)

            case .safariReadTab:
                do {
                    let info = try await desktop.safariTabInfo()
                    return [EngineEvent(.info, "\(info.title)\n\(info.url)")]
                } catch {
                    return [EngineEvent(.warning, "Could not read Safari tab: \(error). Is Safari running?")]
                }

            case let .safariRunJS(script):
                let result = try await desktop.runJavaScriptInSafari(script)
                return [EngineEvent(.info, result)]

            case let .sendMessageToApp(app: appName, text):
                return await sendMessageToApp(name: appName, text: text)

            case let .system(action):
                switch action {
                case let .darkMode(on):
                    try await desktop.setDarkMode(on)
                    let state = on.map { $0 ? "on" : "off" } ?? "toggled"
                    return [EngineEvent(.success, "Dark mode \(state).")]
                case .screenOff:
                    try await desktop.screenOff()
                    return [EngineEvent(.success, "Screen off.")]
                }
            }
        } catch {
            return [EngineEvent(.error, String(describing: error))]
        }
    }

    // MARK: IDE

    /// Sends a prompt to a named app (Claude desktop) by focusing it, pasting
    /// via the clipboard (preserving the user's), and pressing Return.
    private func sendMessageToApp(name spoken: String, text: String) async -> [EngineEvent] {
        guard let desktop else {
            return [EngineEvent(.error, "Desktop control isn't available.")]
        }
        guard let app = apps.find(spoken) else {
            return [EngineEvent(.warning, "No app called \"\(spoken)\" found in Applications.")]
        }
        do {
            try await desktop.openApp(at: app.url)
            await pause(0.3)
            let saved = await desktop.clipboardText() ?? ""
            try await desktop.setClipboard(text)
            try await desktop.pressKey(KeyCombo(key: "v", modifiers: [.command]))
            await pause(0.15)
            try await desktop.pressKey(KeyCombo(key: "return"))
            if !saved.isEmpty {
                try await desktop.setClipboard(saved)
            }
            return [EngineEvent(.success, "Sent to \(app.name).")]
        } catch {
            return [EngineEvent(.error, String(describing: error))]
        }
    }

    /// Remember VS Code–based IDEs (they ship Contents/Resources/app/product.json).
    private func noteIfIDE(_ app: AppEntry) {
        let product = app.url.appendingPathComponent("Contents/Resources/app/product.json").path
        if FileManager.default.fileExists(atPath: product) || Self.knownIDEs.contains(app.name.lowercased()) {
            preferredIDE = app.name
        }
    }

    static let knownIDEs: Set<String> = ["antigravity", "kiro", "visual studio code", "cursor", "windsurf", "vscodium"]

    private func runIDE(_ command: IDECommand) async -> [EngineEvent] {
        guard let ideBridge else {
            return [EngineEvent(.error, "IDE control isn't available.")]
        }
        let resolved: IDECommand
        switch command {
        case let .openTerminals(count, commands):
            resolved = .openTerminals(count: count, commands: commands.map { terminalText($0) })
        case let .send(target, text, submit):
            resolved = .send(target, text: terminalText(text), submit: submit)
        case .closeTerminals:
            resolved = .closeTerminals
        case let .chat(message, submit):
            resolved = .chat(message: message, submit: submit)
        case let .openFile(path):
            resolved = .openFile(path: path)
        case let .openFolder(path):
            resolved = .openFolder(path: path)
        case let .runTask(name):
            resolved = .runTask(name: name)
        }
        do {
            let reply = try await ideBridge.perform(resolved, preferring: preferredIDE, waitSeconds: ideWaitSeconds)
            let message = reply.message ?? (reply.ok ? "Done." : "The IDE said no.")
            return [EngineEvent(reply.ok ? .success : .warning, message)]
        } catch {
            return [EngineEvent(.error, String(describing: error))]
        }
    }

    /// Spoken text -> what to type in a terminal. A configured tool's name runs its
    /// command ("free buff" -> "freebuff"); anything else is cleaned up by `ShellText`.
    func terminalText(_ spoken: String) -> String {
        let key = Tokenizer.normalizedPhrase(spoken)
        if let tool = config.tools.first(where: { $0.phrases.contains { Tokenizer.normalizedPhrase($0) == key } }) {
            return tool.command
        }
        return ShellText.normalize(spoken)
    }

    /// Standard folder ("downloads") or config project ("chirp") -> file URL.
    private func folderURL(_ spoken: String) -> URL? {
        let key = Tokenizer.normalizedPhrase(spoken)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standard: [String: URL] = [
            "home": home,
            "downloads": home.appendingPathComponent("Downloads"),
            "documents": home.appendingPathComponent("Documents"),
            "desktop": home.appendingPathComponent("Desktop"),
            "pictures": home.appendingPathComponent("Pictures"),
            "movies": home.appendingPathComponent("Movies"),
            "music": home.appendingPathComponent("Music"),
            "projects": home.appendingPathComponent("Projects"),
            "applications": URL(fileURLWithPath: "/Applications")
        ]
        if let url = standard[key] { return url }
        let project = config.projects.first { p in
            p.phrases.contains { Tokenizer.normalizedPhrase($0) == key }
        }
        return project.map { URL(fileURLWithPath: TmuxAdapter.expandTilde($0.path), isDirectory: true) }
    }

    private func answer(_ question: Question, desktop: any DesktopControlling) async throws -> String {
        switch question {
        case .time:
            let f = DateFormatter()
            f.timeStyle = .short
            f.dateStyle = .none
            return "It's \(f.string(from: Date()))."
        case .date:
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMMM d"
            return "Today is \(f.string(from: Date()))."
        case .battery:
            return BatteryReport.describe(try await desktop.batteryReport())
        case .clipboard:
            guard let text = await desktop.clipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return "The clipboard has no text." }
            return text.count > 200 ? "Your clipboard says: \(text.prefix(200))…" : "Your clipboard says: \(text)"
        case .openApps:
            let names = await desktop.runningAppNames()
            return names.isEmpty ? "No apps are open." : "Open apps: " + names.joined(separator: ", ") + "."
        case let .calculation(expression):
            guard let value = SpokenMath.evaluate(expression) else { return "I couldn't work that out." }
            return "That's \(SpokenMath.format(value))."
        }
    }

    private func launch(_ toolName: String, directory: String?, prompt: String?) async -> [EngineEvent] {
        guard let tool = config.tool(named: toolName) else {
            router.unlock()
            return [EngineEvent(.error, "\(toolName) is not in your config.")]
        }
        let session = SessionNaming.sessionName(forTool: tool.name)
        var events: [EngineEvent] = []

        if tmux.hasSession(session) && !tmux.isPaneDead(session) {
            events.append(EngineEvent(.info, "\(tool.name) is already running. Talking to it now."))
        } else {
            if tmux.hasSession(session) {
                // A dead pane left by remain-on-exit: clear it and start fresh.
                try? tmux.kill(session: session)
            }
            do {
                try tmux.start(session: session, command: tool.command, directory: directory)
            } catch {
                router.unlock()
                return [EngineEvent(.error, "Couldn't start \(tool.name): \(error)")]
            }
            let place = directory.map { " in \($0)" } ?? ""
            events.append(EngineEvent(.success, "Started \(tool.name)\(place). Talking to it now."))
            if prompt != nil {
                await pause(tool.startupDelaySeconds)
            }
        }

        if let prompt {
            events += await send(prompt, to: tool.name)
        }
        return events
    }

    private func send(_ text: String, to toolName: String) async -> [EngineEvent] {
        let session = SessionNaming.sessionName(forTool: toolName)
        guard tmux.hasSession(session) else {
            router.unlock()
            return [EngineEvent(.error, TmuxError.sessionNotRunning(toolName).description)]
        }
        if tmux.isPaneDead(session) {
            router.unlock()
            return [EngineEvent(.error, TmuxError.processExited(toolName).description)]
        }
        do {
            try tmux.type(session: session, text: text)
            await pause(submitDelaySeconds)
            try tmux.submit(session: session)
            return [EngineEvent(.success, "→ \(toolName): \(text)")]
        } catch {
            return [EngineEvent(.error, String(describing: error))]
        }
    }
}
