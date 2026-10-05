import Foundation

/// What a running tool is doing, read off its screen (Phase 12.1).
public enum ToolActivity: String, Equatable, Sendable {
    /// Busy ("esc to interrupt" is showing).
    case working
    /// Asking permission ("Do you want to proceed?").
    case needsApproval
    /// Waiting for your next prompt.
    case idle
    /// The program has exited.
    case exited
}

/// Substrings (case-insensitive) that tell what a tool's screen means.
public struct AttentionPatterns: Equatable, Sendable {
    public var approval: [String]
    public var busy: [String]

    public init(approval: [String] = AttentionPatterns.defaultApproval, busy: [String] = AttentionPatterns.defaultBusy) {
        self.approval = approval
        self.busy = busy
    }

    /// Claude Code, Codex and Gemini CLI permission prompts.
    public static let defaultApproval = [
        "do you want to proceed", "do you want to make this edit", "do you want to create",
        "do you want to allow", "would you like to run", "would you like to make",
        "allow command?", "allow execution", "apply this change", "waiting for your approval",
        "requires approval"
    ]
    /// Shown only while a tool is working.
    public static let defaultBusy = ["esc to interrupt", "esc to cancel", "ctrl+c to interrupt", "press esc to stop"]

    public static func forTool(_ tool: ToolConfig?) -> AttentionPatterns {
        AttentionPatterns(approval: tool?.approvalPatterns ?? defaultApproval, busy: tool?.busyPatterns ?? defaultBusy)
    }
}

public enum ActivityDetector {
    /// Only the bottom of the screen counts: older prompts scroll up but stay in the capture.
    public static let tailLines = 25

    public static func classify(screen: String, exited: Bool, patterns: AttentionPatterns = AttentionPatterns()) -> ToolActivity {
        if exited { return .exited }
        let lines = screen.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let tail = lines.suffix(tailLines).joined(separator: "\n").lowercased()
        if patterns.approval.contains(where: { !$0.isEmpty && tail.contains($0.lowercased()) }) { return .needsApproval }
        if patterns.busy.contains(where: { !$0.isEmpty && tail.contains($0.lowercased()) }) { return .working }
        return .idle
    }
}

/// Something worth telling the owner about a tool.
public struct AttentionAlert: Equatable, Sendable {
    public let tool: String
    public let activity: ToolActivity
    public let message: String

    public init(tool: String, activity: ToolActivity, message: String) {
        self.tool = tool
        self.activity = activity
        self.message = message
    }
}

/// Turns a stream of per-tool activities into alerts: once when a tool starts
/// asking for approval, once when it finishes working, once when it exits.
public struct AttentionTracker: Sendable {
    /// Idle must be seen this many checks in a row before "done" (the busy line flickers between steps).
    public var settleChecks: Int

    private var last: [String: ToolActivity] = [:]
    private var wasWorking: Set<String> = []
    private var idleStreak: [String: Int] = [:]

    public init(settleChecks: Int = 2) {
        self.settleChecks = settleChecks
    }

    public mutating func update(tool: String, activity: ToolActivity) -> AttentionAlert? {
        let previous = last[tool]
        last[tool] = activity
        let name = InstanceName.spoken(tool)
        switch activity {
        case .working:
            wasWorking.insert(tool)
            idleStreak[tool] = 0
            return nil
        case .needsApproval:
            idleStreak[tool] = 0
            guard previous != .needsApproval else { return nil }
            return AttentionAlert(tool: tool, activity: activity, message: "\(name) needs your approval.")
        case .exited:
            wasWorking.remove(tool)
            guard previous != nil, previous != .exited else { return nil }
            return AttentionAlert(tool: tool, activity: activity, message: "\(name) exited.")
        case .idle:
            let streak = (idleStreak[tool] ?? 0) + 1
            idleStreak[tool] = streak
            guard wasWorking.contains(tool), streak >= settleChecks else { return nil }
            wasWorking.remove(tool)
            return AttentionAlert(tool: tool, activity: activity, message: "\(name) is done.")
        }
    }

    /// Drops tools that are no longer running.
    public mutating func keep(only tools: Set<String>) {
        for tool in last.keys where !tools.contains(tool) {
            last[tool] = nil
            idleStreak[tool] = nil
            wasWorking.remove(tool)
        }
    }

    public func activity(of tool: String) -> ToolActivity? { last[tool] }
}

/// A running tool instance: "claude", or "claude@chirp" for a second session in a project (Phase 12.4).
public enum InstanceName {
    /// "claude@chirp" -> "claude in chirp" (for speech and messages).
    public static func spoken(_ instance: String) -> String {
        guard let at = instance.firstIndex(of: "@") else { return instance }
        return "\(instance[..<at]) in \(instance[instance.index(after: at)...])"
    }
}
