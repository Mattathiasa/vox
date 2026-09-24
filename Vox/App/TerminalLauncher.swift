import Foundation

/// Opens Terminal.app running a command. Uses Apple Events, so the first call
/// triggers macOS's "Vox wants to control Terminal" prompt.
///
/// The command passed here is built by Vox (a tmux attach), never from speech.
enum TerminalLauncher {
    /// Returns an error message, or nil on success.
    @MainActor
    static func open(command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return "Couldn't build the AppleScript."
        }
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
            return "Terminal: \(message). Check System Settings › Privacy & Security › Automation."
        }
        return nil
    }
}
