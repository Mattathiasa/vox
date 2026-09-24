import Foundation

/// Where spoken text goes.
public enum RouterMode: Equatable, Sendable {
    /// Every utterance is a Vox command.
    case idle
    /// Pass-through: every utterance goes straight to this tool, unless it is an
    /// exit phrase or starts with a command prefix ("vox ...").
    case locked(tool: String)

    public var lockedTool: String? {
        if case let .locked(tool) = self { return tool }
        return nil
    }
}

/// Something the engine should do. The router decides; the engine executes.
public enum RouterAction: Equatable, Sendable {
    case launch(tool: String, directory: String?, initialPrompt: String?)
    case focus(tool: String)
    case send(tool: String, text: String)
    case kill(tool: String)
    case listSessions
    /// Ctrl-C to a tool's session.
    case interrupt(tool: String)
    /// Open Terminal attached to a tool's session.
    case showTool(String)
    /// A GUI action (open app, note, web, type, key). Doesn't change the mode.
    case desktop(DesktopCommand)
    case askConfirmation(String)
    case feedback(String)
    /// Parser returned .unknown — hand off to the LLM. The engine calls the LLM,
    /// then re-routes the result through the parser so safety checks still apply.
    case llmFallback(LLMRequest)
}

/// Actions held back until the user says "yes".
public struct PendingConfirmation: Equatable, Sendable {
    public let question: String
    public let actions: [RouterAction]
}

extension RouterAction {
    /// True when this action needs the target app to be the frontmost window
    /// (i.e. it types into it or uses AppleScript that targets the front app).
    /// The engine delays execution of these actions when preceded by an openApp/focusApp.
    var needsFrontmostApp: Bool {
        guard case let .desktop(cmd) = self else { return false }
        switch cmd {
        case .typeText, .pressKey, .createNote, .reminder, .webSearch, .openURL: return true
        default: return false
        }
    }
}/// Pure state machine: text in, actions out. No I/O, so it is fully unit-tested.
public struct SessionRouter: Sendable {
    public private(set) var mode: RouterMode = .idle
    public private(set) var pending: PendingConfirmation?

    private let config: VoxConfig
    private let parser: CommandParser
    private let safety: SafetyPolicy

    public init(config: VoxConfig) {
        self.config = config
        self.parser = CommandParser(config: config)
        self.safety = SafetyPolicy(config: config)
    }

    /// Called by the engine when a launch/focus/send turned out to be impossible
    /// (the session died, tmux failed), so the user is not left talking to nothing.
    public mutating func unlock() {
        mode = .idle
    }

    public mutating func cancelPending() {
        pending = nil
    }

    public mutating func handle(_ text: String) -> [RouterAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. A pending confirmation swallows the next utterance, whatever it is.
        if let held = pending {
            pending = nil
            if parser.isAffirmative(trimmed) {
                return release(held.actions)
            }
            return [.feedback("Cancelled.")]
        }

        // 2. Pass-through mode.
        if case let .locked(tool) = mode {
            if parser.isExit(trimmed) {
                mode = .idle
                return [.feedback("Stopped talking to \(tool). \(tool) is still running.")]
            }
            if parser.isInterrupt(trimmed) {
                return [.interrupt(tool: tool)]
            }
            if let command = parser.strippingPrefix(trimmed) {
                if command.isEmpty { return [.feedback("Listening for a command.")] }
                return handleCommand(command)
            }
            return guarded([.send(tool: tool, text: trimmed)], text: trimmed,
                           question: "Send to \(tool): \"\(trimmed)\"?")
        }

        // 3. Idle: everything is a command.
        return handleCommand(trimmed)
    }

    // MARK: Commands

    private mutating func handleCommand(_ text: String) -> [RouterAction] {
        switch parser.parse(text) {
        case let .launch(toolName, projectName, prompt):
            guard let tool = config.tool(named: toolName) else {
                return [.feedback("\(toolName) is not in your config.")]
            }
            var directory = tool.defaultDirectory
            if let projectName {
                directory = config.project(named: projectName)?.path ?? directory
            }
            let action = RouterAction.launch(tool: tool.name, directory: directory, initialPrompt: prompt)
            guard let prompt else { return release([action]) }
            return guarded([action], text: prompt,
                           question: "Start \(tool.name) and send: \"\(prompt)\"?")

        case let .focus(tool):
            return release([.focus(tool: tool)])

        case let .kill(tool):
            return hold([.kill(tool: tool)],
                        question: "Kill the \(tool) session? Anything it is doing will stop.")

        case .listSessions:
            return [.listSessions]

        case let .desktop(commands, unparsed):
            var actions = commands.map { RouterAction.desktop($0) }
            if let unparsed {
                actions.append(.feedback("Didn't understand \"\(unparsed)\"."))
            }
            // Text that will be typed somewhere (front app or an IDE terminal).
            let typed = commands.flatMap { command -> [String] in
                switch command {
                case let .typeText(text): return [text]
                case let .ide(.send(_, text, _)): return [text]
                case let .ide(.openTerminals(_, list)): return list
                default: return []
                }
            }.joined(separator: " ")
            if !typed.isEmpty, safety.needsConfirmation(typed) {
                return hold(actions, question: "Type \"\(typed)\" into the front app?")
            }
            return release(actions)

        case .cancel:
            return [.feedback("OK.")]

        case let .interrupt(tool):
            guard let target = tool ?? mode.lockedTool else {
                return [.feedback("Not talking to any tool. Say \"interrupt freebuff\".")]
            }
            return [.interrupt(tool: target)]

        case let .restart(toolName):
            guard let tool = config.tool(named: toolName) else {
                return [.feedback("\(toolName) is not in your config.")]
            }
            return hold([.kill(tool: tool.name),
                         .launch(tool: tool.name, directory: tool.defaultDirectory, initialPrompt: nil)],
                        question: "Restart \(tool.name)? Whatever it's doing will stop.")

        case let .showTool(tool):
            return [.showTool(tool)]

        case let .tell(tool, message):
            return sendTo(tool: tool, text: message)

        case .help:
            return [.feedback(SessionRouter.helpText)]

        case .exit:
            if mode == .idle { return [.feedback("Not talking to any tool.")] }
            mode = .idle
            return [.feedback("Back to commands.")]

        case let .unknownTool(spoken):
            return [.feedback("No tool called \"\(spoken)\" in your config.")]

        case let .unknownProject(spoken):
            return [.feedback("No project called \"\(spoken)\" in your config.")]

        case .unknown:
            // Always hand off to the engine; it decides whether an LLM is wired up.
            return [.llmFallback(makeLLMRequest(text: text))]
        }
    }

    /// Builds the LLM request from the user's text and the tool names in config.
    private func makeLLMRequest(text: String) -> LLMRequest {
        let toolDefs = config.tools.map { tool in
            LLMToolDefinition(name: tool.name, spokenPhrases: tool.phrases)
        }
        return LLMRequest(text: text, tools: toolDefs, instruction: llmInstruction)
    }

    public static let helpText = """
    Apps: open / close / switch to / hide safari · open chirp in kiro · open downloads
    Web: search for … · search youtube for … · play … on youtube · directions to … · go to github dot com
    Keys: close tab · new tab · copy · paste · undo · save · scroll down · go back · lock screen · spotlight
    Type: type … and press enter · press command s
    Media: play · pause · next song · volume up · mute · set volume to 30
    Ask: what time is it · what's the date · battery · what's 12 times 8 · read clipboard · what apps are open
    Do: create a note called … · remind me to … in 10 minutes · set a timer for 5 minutes · dark mode
    Tools: run freebuff in vox · tell claude to … · exit · interrupt · restart freebuff · show freebuff · what's running
    IDE: open antigravity with 3 terminals · run claude in the first · in terminal 2 run npm run dev · close the terminals
    """

    /// Text for one tool (voice "tell X to …" or the HUD's per-terminal box).
    /// Doesn't change which tool you're talking to; destructive text still needs a "yes".
    public mutating func sendTo(tool: String, text: String) -> [RouterAction] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard config.tool(named: tool) != nil else { return [.feedback("\(tool) is not in your config.")] }
        return guarded([.send(tool: tool, text: trimmed)], text: trimmed,
                       question: "Send to \(tool): \"\(trimmed)\"?")
    }

    // MARK: Confirmation plumbing

    /// Holds the actions for confirmation if the text looks destructive.
    private mutating func guarded(_ actions: [RouterAction], text: String, question: String) -> [RouterAction] {
        if safety.needsConfirmation(text) {
            return hold(actions, question: question)
        }
        return release(actions)
    }

    private mutating func hold(_ actions: [RouterAction], question: String) -> [RouterAction] {
        pending = PendingConfirmation(question: question, actions: actions)
        return [.askConfirmation(question + " Say yes to confirm.")]
    }

    /// Applies each action's effect on the mode, then hands the actions out.
    private mutating func release(_ actions: [RouterAction]) -> [RouterAction] {
        for action in actions {
            switch action {
            case let .launch(tool, _, _), let .focus(tool):
                mode = .locked(tool: tool)
            case let .kill(tool):
                if mode == .locked(tool: tool) { mode = .idle }
            default:
                break
            }
        }
        return actions
    }
}
