import AppKit
import SwiftUI
import ServiceManagement
import SystemConfiguration
import VoxCore

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let kind: EngineEvent.Kind
    let text: String
}

/// One command in the HUD's history strip.
struct HistoryItem: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let command: String
    let kind: EngineEvent.Kind
    let reply: String
    let spoken: Bool
    /// Came from the phone remote (Phase 8).
    var fromPhone = false
}

/// UI-facing state. Owns the engine; views only talk to this.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var mode: RouterMode = .idle
    @Published private(set) var pendingQuestion: String?
    @Published private(set) var output = ""
    @Published private(set) var isBusy = false
    @Published private(set) var setupProblem: String?
    @Published private(set) var isListening = false
    @Published private(set) var heard = ""
    /// Wake word ("Balcha") listening on/off. Remembered across launches.
    @Published private(set) var wakeEnabled: Bool
    /// Launch Vox at login. Remembered via SMAppService.
    @Published private(set) var launchAtLogin: Bool = false
    /// LLM fallback config from config.json.
    @Published var llmConfig: LLMConfig? = nil
    /// The wake word was heard and Vox is waiting for the rest of the command.
    @Published private(set) var isAwake = false
    /// Last thing the wake listener heard, to tune `wakeWord.phrases`.
    @Published private(set) var lastHeard = ""
    @Published private(set) var wakeName = "Balcha"

    // HUD
    /// Microphone loudness 0…1 (only updated while the HUD is visible).
    @Published private(set) var level: Double = 0
    @Published private(set) var history: [HistoryItem] = []
    /// Most important result of the last command (drives the core's flash colour).
    @Published private(set) var lastResult: HistoryItem?
    @Published private(set) var sessions: [String] = []
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var batteryCharging = false
    /// Live screen of every running tool, for the terminal grid.
    @Published private(set) var screens: [SessionScreen] = []
    /// Tools from config.json, for the quick-launch buttons.
    @Published private(set) var toolNames: [String] = []
    /// Tools from config.json, for the Settings editor.
    @Published var tools: [ToolConfig] = []
    /// Projects from config.json, for the Settings editor.
    @Published var projects: [ProjectConfig] = []
    private var levelTimer: Timer?
    private var slowTicks = 0

    /// UI hooks set by AppDelegate (show / hide the panel).
    var onWake: (() -> Void)?
    var onVoiceCommandDone: (() -> Void)?

    let desktop = DesktopController()
    private let transcriber: Transcriber = SpeechController()
    private let wake = WakeWordListener()
    private let voiceOut = SpeechOutput()
    private var speakFeedback = true
    private var wakeConfig = WakeWordConfig()
    private static let wakeDefaultsKey = "wakeWordEnabled"
    private var wantsToListen = false
    private var engine: VoxEngine?
    private var outputTimer: Timer?
    private let configURL = ConfigStore.defaultURL
    /// Phone remote (Phase 8). Off until turned on in Settings → Phone.
    let remote = RemoteHost()

    init() {
        wakeEnabled = UserDefaults.standard.object(forKey: Self.wakeDefaultsKey) as? Bool ?? true
        launchAtLogin = (try? SMAppService.mainApp.status == .enabled) ?? false
        transcriber.onPartial = { [weak self] text in self?.heard = text }
        wake.onHeard = { [weak self] text in self?.lastHeard = String(text.suffix(80)) }
        wake.onAwake = { [weak self] command in self?.wakeHeard(command) }
        wake.onCommand = { [weak self] command in self?.wakeCommand(command) }
        wake.onTimeout = { [weak self] in self?.wakeTimedOut() }
        desktop.onTimerFinished = { [weak self] length in
            guard let self else { return }
            self.append(.success, "⏰ \(length) timer done.")
            if self.speakFeedback { self.voiceOut.say("Your \(length) timer is done.") }
            self.onWake?()
            self.onVoiceCommandDone?()
        }
        voiceOut.onStart = { [weak self] in self?.wake.setMuted(true) }
        voiceOut.onFinish = { [weak self] in self?.wake.setMuted(false) }
        reloadConfig()
        remote.attach(self)
    }

    var lockedTool: String? { mode.lockedTool }
    /// For the phone remote (RemoteHost).
    var currentEngine: VoxEngine? { engine }

    // MARK: Input

    /// Handles one utterance. `spoken` = it came from the microphone, so
    /// replies are also spoken.
    func submit(_ text: String, spoken: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let engine else {
            append(.error, setupProblem ?? "Vox isn't set up.")
            return
        }
        Task { _ = await perform(trimmed, spoken: spoken) }
    }

    /// Runs one command and returns what happened (the phone remote needs the events).
    /// `fromPhone`: the phone speaks its own replies, so the Mac stays quiet.
    @discardableResult
    func perform(_ text: String, spoken: Bool = false, fromPhone: Bool = false) async -> [EngineEvent] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard let engine else {
            let message = setupProblem ?? "Vox isn't set up."
            append(.error, message)
            return [EngineEvent(.error, message)]
        }
        append(.info, (fromPhone ? "📱 " : "") + "› \(trimmed)")
        isBusy = true
        let events = await engine.handle(trimmed)
        for event in events { append(event.kind, event.message) }
        if spoken && !fromPhone { speak(events) }
        recordHistory(trimmed, events: events, spoken: spoken, fromPhone: fromPhone)
        await syncFromEngine()
        isBusy = false
        return events
    }

    // MARK: Voice

    // MARK: Wake word

    func setWakeEnabled(_ on: Bool) {
        wakeEnabled = on
        UserDefaults.standard.set(on, forKey: Self.wakeDefaultsKey)
        on ? startWakeListening() : stopWakeListening()
    }

    func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
        if on {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func startWakeListening() {
        guard wakeEnabled, wakeConfig.enabled, engine != nil, !wake.isRunning, !transcriber.isListening else { return }
        Task {
            do {
                try await transcriber.ensurePermissions()
                guard wakeEnabled, !wake.isRunning, !transcriber.isListening else { return }
                try wake.start()
                append(.info, "Listening for \"\(wakeName)\". Say \"\(wakeName), open safari\".")
            } catch {
                append(.error, "Wake word: \(error)")
            }
        }
    }

    private func stopWakeListening() {
        wake.stop()
        isAwake = false
        heard = ""
    }

    private func wakeHeard(_ command: String) {
        if !isAwake {
            isAwake = true
            NSSound(named: "Tink")?.play()
            onWake?()
        }
        heard = command
    }

    private func wakeCommand(_ command: String) {
        isAwake = false
        heard = ""
        NSSound(named: "Pop")?.play()
        submit(command, spoken: true)
        Task {
            while isBusy { try? await Task.sleep(nanoseconds: 100_000_000) }
            onVoiceCommandDone?()
        }
    }

    private func wakeTimedOut() {
        isAwake = false
        heard = ""
        onVoiceCommandDone?()
    }

    // MARK: Push-to-talk

    /// Hotkey pressed: start listening (asks for permissions the first time).
    func startListening() {
        guard engine != nil else {
            append(.error, setupProblem ?? "Vox isn't set up.")
            return
        }
        // One microphone user at a time: pause the wake word while the key is held.
        stopWakeListening()
        wantsToListen = true
        heard = ""
        Task {
            do {
                try await transcriber.ensurePermissions()
                // The key may have been released while a permission prompt was up.
                guard wantsToListen else { return }
                try transcriber.start()
                isListening = true
            } catch {
                wantsToListen = false
                append(.error, String(describing: error))
            }
        }
    }

    /// A tap, not a hold: throw away whatever was heard.
    func cancelListening() {
        wantsToListen = false
        transcriber.cancel()
        isListening = false
        heard = ""
        startWakeListening()
    }

    /// Hotkey released: get the final transcript and run it.
    func finishListening(then done: @escaping @MainActor () -> Void) {
        wantsToListen = false
        Task {
            let text = await transcriber.stop()
            isListening = false
            heard = ""
            if text.isEmpty {
                append(.warning, "Didn't hear anything.")
            } else {
                submit(text, spoken: true)
                // Let the command finish before the panel decides whether to hide.
                while isBusy { try? await Task.sleep(nanoseconds: 100_000_000) }
            }
            done()
            startWakeListening()
        }
    }

    func confirm(_ yes: Bool) {
        submit(yes ? "yes" : "no")
    }

    func exitPassThrough() {
        guard let engine else { return }
        Task {
            await engine.exitPassThrough()
            append(.info, "Back to commands.")
            await syncFromEngine()
        }
    }

    // MARK: Output view

    func panelDidShow() {
        refreshOutput()
        refreshStatus()
        outputTimer?.invalidate()
        outputTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshOutput()
                self?.slowTick()
            }
        }
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLevel() }
        }
    }

    func panelDidHide() {
        outputTimer?.invalidate()
        outputTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
    }

    // MARK: HUD status

    private func pollLevel() {
        let hearing = isListening || isAwake || wakeEnabled
        let target = hearing ? Double(AudioLevel.shared.value) : 0
        level = level * 0.5 + target * 0.5
    }

    private func slowTick() {
        slowTicks += 1
        if slowTicks % 5 == 0 { refreshStatus() }
    }

    /// Running tool sessions and battery, for the side cards.
    func refreshStatus() {
        if let engine {
            Task {
                let running = await engine.runningSessions()
                    .map { String($0.dropFirst(SessionNaming.prefix.count)) }
                if running != sessions { sessions = running }
            }
        }
        Task {
            guard let report = try? await desktop.batteryReport(),
                  let range = report.range(of: #"\d{1,3}%"#, options: .regularExpression) else { return }
            batteryPercent = Int(report[range].dropLast())
            let lower = report.lowercased()
            batteryCharging = lower.contains("ac power") || (lower.contains("charging") && !lower.contains("discharging"))
        }
    }

    private func recordHistory(_ command: String, events: [EngineEvent], spoken: Bool, fromPhone: Bool = false) {
        let order: [EngineEvent.Kind] = [.error, .confirm, .warning, .info, .success]
        let worst = order.first { kind in events.contains { $0.kind == kind } } ?? .info
        let reply = events.first { $0.kind == worst }?.message ?? ""
        let item = HistoryItem(command: command, kind: worst, reply: reply, spoken: spoken, fromPhone: fromPhone)
        history.insert(item, at: 0)
        if history.count > 8 { history.removeLast(history.count - 8) }
        lastResult = item
    }

    func refreshOutput() {
        guard let engine else { return }
        Task {
            let text = await engine.lockedOutput() ?? ""
            if text != output { output = text }
            let latest = await engine.screens()
            if latest != screens { screens = latest }
        }
    }

    // MARK: Terminal grid actions

    private var fitTask: Task<Void, Never>?

    /// Called by the grid when a tile's size changes: after a short pause (so
    /// dragging the window edge doesn't resize 60×/s) every tool's terminal is
    /// resized to fit, and the tools redraw for the new width.
    func fitTerminals(width: Double, height: Double, cellWidth: Double, cellHeight: Double) {
        guard let engine else { return }
        let size = TerminalSize(width: width, height: height, cellWidth: cellWidth, cellHeight: cellHeight)
        fitTask?.cancel()
        fitTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            if await engine.fitTerminals(to: size) > 0 { refreshOutput() }
        }
    }

    /// "vox …" works both when idle and while talking to a tool.
    func launchTool(_ tool: String) { submit("vox run \(tool)") }
    func focusTool(_ tool: String) { submit("vox switch to \(tool)") }
    func killTool(_ tool: String) { submit("vox kill \(tool)") }

    /// A tile's command box: text goes to that tool (Enter included) without switching to it.
    func sendToTool(_ tool: String, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine else { return }
        append(.info, "› \(tool): \(trimmed)")
        Task {
            let events = await engine.send(trimmed, toTool: tool)
            for event in events { append(event.kind, event.message) }
            await syncFromEngine()
            try? await Task.sleep(nanoseconds: 400_000_000)
            refreshOutput()
        }
    }

    /// Same as `sendToTool`, awaited (phone remote).
    func sendToToolNow(_ tool: String, _ text: String) async -> [EngineEvent] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine else { return [] }
        append(.info, "› \(tool): \(trimmed)")
        let events = await engine.send(trimmed, toTool: tool)
        for event in events { append(event.kind, event.message) }
        await syncFromEngine()
        return events
    }

    /// Live typing: keystrokes straight into a tool's terminal (no Enter).
    func typeInTool(_ tool: String, _ text: String) {
        guard let engine else { return }
        Task {
            let events = await engine.type(text, inTool: tool)
            for event in events { append(event.kind, event.message) }
            try? await Task.sleep(nanoseconds: 120_000_000)
            refreshOutput()
        }
    }

    /// A tile's key buttons.
    func pressKey(_ key: String, inTool tool: String) {
        guard let engine else { return }
        Task {
            let events = await engine.press(key, inTool: tool)
            for event in events { append(event.kind, event.message) }
            try? await Task.sleep(nanoseconds: 250_000_000)
            refreshOutput()
        }
    }

    func openToolInTerminal(_ tool: String) {
        let session = SessionNaming.sessionName(forTool: tool)
        if let error = TerminalLauncher.open(command: TmuxAdapter.attachCommand(session: session)) {
            append(.error, error)
        }
    }

    // MARK: Terminal

    /// Opens Terminal attached to the locked tool's tmux session, so you can watch it.
    func openLockedSessionInTerminal() {
        guard let tool = lockedTool else { return }
        let session = SessionNaming.sessionName(forTool: tool)
        if let error = TerminalLauncher.open(command: TmuxAdapter.attachCommand(session: session)) {
            append(.error, error)
        }
    }

    // MARK: Config

    func reloadConfig() {
        do {
            let config = try ConfigStore.loadOrCreate(at: configURL)
            guard let tmuxPath = TmuxAdapter.locate(configured: config.tmuxPath) else {
                fail(TmuxError.tmuxNotFound.description)
                return
            }
            let tmux = TmuxAdapter(tmuxPath: tmuxPath, shell: config.shell)
            let apps = AppCatalog.scan()
            toolNames = config.tools.map(\.name)
            tools = config.tools
            projects = config.projects
            llmConfig = config.llm
            engine = VoxEngine(config: config, tmux: tmux, apps: apps, desktop: desktop, ideBridge: HTTPIDEBridge(), llm: makeLLMAdapter(config: config))
            // Apple recommends keeping contextual strings to about 100.
            var vocabulary = ["vox", "create a note", "search for", "press enter"]
            vocabulary += config.tools.flatMap(\.phrases) + config.projects.flatMap(\.phrases)
            vocabulary += apps.names
            var seen = Set<String>()
            transcriber.contextualStrings = Array(vocabulary.filter { seen.insert($0.lowercased()).inserted }.prefix(100))
            stopWakeListening()
            wakeConfig = config.wakeWord
            speakFeedback = config.speakFeedback
            wakeName = (config.wakeWord.phrases.first ?? "Balcha").capitalized
            wake.configure(config.wakeWord, vocabulary: transcriber.contextualStrings)
            setupProblem = nil
            mode = .idle
            pendingQuestion = nil
            append(.success, "Loaded \(config.tools.count) tools and \(apps.entries.count) apps.")
            startWakeListening()
        } catch {
            fail(String(describing: error))
        }
    }

    /// Phase 6: Create an LLM adapter from config, reading the API key from Keychain.
    private func makeLLMAdapter(config: VoxConfig) -> (any LLMFallback)? {
        guard let llmConfig = config.llm, llmConfig.enabled else { return nil }
        switch llmConfig.provider {
        case .claude:
            let key = Keychain.read("com.vox.llm.claude-api-key")
            return LLMAdapter(config: llmConfig, apiKey: key)
        case .apple:
            return LLMAdapter(config: llmConfig)
        }
    }

    /// Save the current tools, projects, and LLM config to config.json.
    func saveConfig() {
        Task {
            do {
                // Read current config, replace the edited sections.
                let current = (try? ConfigStore.load(from: configURL)) ?? VoxConfig.starter
                var updated = current
                updated.tools = tools
                updated.projects = projects
                updated.llm = llmConfig
                try ConfigStore.save(updated, to: configURL)
                reloadConfig()
                append(.success, "Config saved.")
            } catch {
                append(.error, "Could not save config: \(error)")
            }
        }
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    // MARK: Private

    /// Say what needs saying: questions, problems and short answers. Successes
    /// stay silent (the Pop sound already said "done").
    private func speak(_ events: [EngineEvent]) {
        guard speakFeedback else { return }
        for event in events where event.kind != .success {
            if event.message == SessionRouter.helpText {
                voiceOut.say("Here's what you can say. It's in the Vox panel.")
                onWake?()
            } else if event.kind == .confirm {
                voiceOut.say(event.message.replacingOccurrences(of: " Say yes to confirm.", with: "") + " Yes or no?")
            } else if event.message.count <= 120 {
                voiceOut.say(event.message)
            } else {
                voiceOut.say("That didn't work. Details are in the Vox panel.")
                onWake?()
            }
        }
    }

    private func fail(_ message: String) {
        engine = nil
        setupProblem = message
        append(.error, message)
    }

    private func syncFromEngine() async {
        guard let engine else { return }
        mode = await engine.mode
        pendingQuestion = await engine.pendingQuestion
        refreshOutput()
    }

    private func append(_ kind: EngineEvent.Kind, _ text: String) {
        log.append(LogLine(kind: kind, text: text))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}


// MARK: - Phone remote (Phase 8)

/// Owns the phone remote's server and pairing code. Lives here (not a new file) so ⌘R works
/// without regenerating the project.
@MainActor
final class RemoteHost: ObservableObject {
    static let enabledKey = "remoteEnabled"
    static let lanKey = "remoteAllowLAN"
    static let codeKey = "remote-pairing-code"
    static let port: UInt16 = 7788

    @Published private(set) var enabled: Bool
    @Published private(set) var allowLAN: Bool
    @Published private(set) var status = "Off"
    @Published private(set) var code: String

    private var server: RemoteServer?
    private weak var appState: AppState?

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        allowLAN = UserDefaults.standard.bool(forKey: Self.lanKey)
        if let saved = Keychain.read(Self.codeKey), !saved.isEmpty {
            code = saved
        } else {
            code = RemotePairing.newCode()
            _ = Keychain.set(Self.codeKey, code)
        }
    }

    func attach(_ appState: AppState) {
        self.appState = appState
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    func setAllowLAN(_ on: Bool) {
        allowLAN = on
        UserDefaults.standard.set(on, forKey: Self.lanKey)
        if enabled { stop(); start() }
    }

    /// New code: every paired phone has to pair again.
    func regenerateCode() {
        code = RemotePairing.newCode()
        _ = Keychain.set(Self.codeKey, code)
        syncCode()
    }

    private func start() {
        stop()
        let codeBox = CodeBox(code)
        currentCode = codeBox
        let server = RemoteServer(
            port: Self.port, allowLAN: allowLAN,
            code: { codeBox.value },
            onStatus: { [weak self] message in Task { @MainActor in self?.status = message } },
            handler: { [weak self] route in
                guard let self else { return .error(500, "Vox is shutting down.") }
                return await self.handle(route)
            })
        do {
            try server.start()
            self.server = server
            status = "Starting…"
        } catch {
            status = "Couldn't start: \(error)"
        }
    }

    private func stop() {
        server?.stop()
        server = nil
        status = "Off"
    }

    /// The server reads the code off the main actor, so it gets a thread-safe copy.
    private var currentCode: CodeBox?
    final class CodeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String
        init(_ value: String) { stored = value }
        var value: String { lock.lock(); defer { lock.unlock() }; return stored }
        func set(_ value: String) { lock.lock(); stored = value; lock.unlock() }
    }

    func syncCode() { currentCode?.set(code) }

    // MARK: Links for pairing

    /// Addresses a phone can use, best first (Tailscale HTTPS, then home Wi-Fi when allowed).
    func links(tailscale: Tailscale.Status) -> [PhoneLink] {
        PhoneLinks.make(code: code, port: Self.port, allowLAN: allowLAN,
                        tailscaleName: tailscale.name, tailscaleServing: tailscale.serving,
                        interfaces: Self.ipv4Interfaces(), localHostName: Self.localHostName())
    }

    /// Bonjour name ("Matts-MacBook-Pro"), which iPhones resolve as <name>.local on the home Wi-Fi.
    static func localHostName() -> String? { SCDynamicStoreCopyLocalHostName(nil) as String? }

    static func ipv4Interfaces() -> [(name: String, address: String)] {
        var result: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for ifa in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                result.append((String(cString: ifa.pointee.ifa_name), String(cString: host)))
            }
        }
        return result
    }

    // MARK: API

    private func handle(_ route: RemoteRoute) async -> HTTPResponse {
        guard let appState else { return .error(500, "Vox isn't ready.") }
        func events(_ list: [EngineEvent]) -> HTTPResponse { .json(200, ["events": list.map(\.remoteJSON)]) }
        switch route {
        case .asset, .ping:
            return .error(404, "Not found")
        case let .state(lines):
            return .encoded(await appState.remoteState(lines: lines))
        case let .command(text, spoken, _):
            return events(await appState.perform(text, spoken: spoken, fromPhone: true))
        case let .confirm(yes):
            // Only answers a pending question; otherwise "yes" would go to the tool you're talking to.
            guard appState.pendingQuestion != nil else { return events([EngineEvent(.info, "Nothing to confirm.")]) }
            return events(await appState.perform(yes ? "yes" : "no", fromPhone: true))
        case .exitTool:
            appState.exitPassThrough()
            return events([])
        case let .launch(tool):
            return events(await appState.perform("vox run \(tool)", fromPhone: true))
        case let .kill(tool):
            return events(await appState.perform("vox kill \(tool)", fromPhone: true))
        case let .focus(tool):
            return events(await appState.perform("vox switch to \(tool)", fromPhone: true))
        case let .send(tool, text):
            return events(await appState.sendToToolNow(tool, text))
        case let .type(tool, text):
            return events(await appState.typeNow(tool, text))
        case let .key(tool, key):
            return events(await appState.pressKeyNow(key, inTool: tool))
        }
    }
}

extension AppState {
    /// Looked up once: Host.current() can be slow and the phone polls every second.
    static let macName: String = Host.current().localizedName ?? "Mac"

    func typeNow(_ tool: String, _ text: String) async -> [EngineEvent] {
        guard let engine = currentEngine else { return [] }
        return await engine.type(text, inTool: tool)
    }

    func pressKeyNow(_ key: String, inTool tool: String) async -> [EngineEvent] {
        guard let engine = currentEngine else { return [] }
        return await engine.press(key, inTool: tool)
    }

    /// What the phone sees (GET /api/state). Screens are read fresh even while the panel is hidden.
    func remoteState(lines: Int) async -> RemoteState {
        let screens = await currentEngine?.screens(lines: lines) ?? []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return RemoteState(
            host: Self.macName,
            lockedTool: lockedTool,
            pendingQuestion: pendingQuestion,
            busy: isBusy,
            wake: .init(enabled: wakeEnabled, name: wakeName, phrases: wakeConfig.phrases),
            tools: toolNames,
            screens: screens.map { RemoteState.Screen(tool: $0.tool, text: $0.text, exited: $0.exited) },
            history: history.map {
                RemoteState.Item(command: $0.command, kind: $0.kind.rawValue, reply: $0.reply,
                                 spoken: $0.spoken, source: $0.fromPhone ? "phone" : "local")
            },
            log: log.suffix(60).map { RemoteState.Line(kind: $0.kind.rawValue, text: $0.text, time: formatter.string(from: $0.date)) })
    }
}
