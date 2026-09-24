import AppKit
import ApplicationServices
import VoxCore

enum DesktopError: Error, CustomStringConvertible {
    case accessibilityNotGranted
    case appleScript(String)
    case unsupportedKey(String)

    var description: String {
        switch self {
        case .accessibilityNotGranted:
            return "Vox needs Accessibility access to type and press keys. Turn it on in System Settings › Privacy & Security › Accessibility, then try again."
        case let .appleScript(message):
            return "AppleScript: \(message). If it mentions permission, allow Vox in System Settings › Privacy & Security › Automation."
        case let .unsupportedKey(key):
            return "Vox doesn't know the key \"\(key)\" yet."
        }
    }
}

/// Does GUI things on this Mac: open apps and URLs (NSWorkspace), Notes
/// (AppleScript), typing and key presses (CGEvent, needs Accessibility).
@MainActor
final class DesktopController: DesktopControlling {
    /// Called before typing/pressing so the Vox panel gives keyboard focus back
    /// to the app you were using.
    var prepareForInput: () -> Void = {}

    func openApp(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func openURL(_ url: URL) async throws {
        NSWorkspace.shared.open(url)
    }

    func createNote(_ text: String) async throws {
        let html = text.isEmpty ? "<div><br></div>" : "<div>\(Self.escapeHTML(text))</div>"
        let body = Self.escapeAppleScript(html)
        try runAppleScript("""
        tell application "Notes"
            activate
            try
                set newNote to make new note with properties {body:"\(body)"}
            on error
                set newNote to make new note at folder 1 of default account with properties {body:"\(body)"}
            end try
            try
                show newNote
            end try
        end tell
        """)
    }

    func typeText(_ text: String) async throws {
        try requireAccessibility()
        prepareForInput()
        try await Task.sleep(nanoseconds: 250_000_000)

        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var chunk = Array(units[index..<min(index + 16, units.count)])
            index += chunk.count
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.post(tap: .cghidEventTap)
            }
            try await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    func pressKey(_ combo: KeyCombo) async throws {
        try requireAccessibility()
        guard let code = Self.keyCodes[combo.key] else { throw DesktopError.unsupportedKey(combo.key) }
        prepareForInput()
        try await Task.sleep(nanoseconds: 250_000_000)

        var flags = CGEventFlags()
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }

        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    func quitApp(at url: URL) async throws -> Bool {
        let running = runningApps(at: url)
        guard !running.isEmpty else { return false }
        running.forEach { $0.terminate() }
        return true
    }

    func hideApp(at url: URL) async throws -> Bool {
        let running = runningApps(at: url)
        guard !running.isEmpty else { return false }
        running.forEach { $0.hide() }
        return true
    }

    func setVolume(_ change: VolumeChange) async throws {
        let script: String
        switch change {
        case .up:
            script = "set volume output volume ((output volume of (get volume settings)) + 10) without output muted"
        case .down:
            script = "set volume output volume ((output volume of (get volume settings)) - 10)"
        case .mute:
            script = "set volume with output muted"
        case .unmute:
            script = "set volume without output muted"
        case let .set(level):
            script = "set volume output volume \(max(0, min(100, level))) without output muted"
        }
        try runAppleScript(script)
    }

    // MARK: Batch 2

    /// Fired when a timer ends, with its length in words ("5 minutes").
    var onTimerFinished: ((String) -> Void)?
    private var timers: [UUID: Task<Void, Never>] = [:]

    func pressMediaKey(_ key: MediaKey) async throws {
        try requireAccessibility()
        // NX_KEYTYPE_PLAY / NEXT / PREVIOUS, sent as system-defined media key events.
        let code: Int
        switch key {
        case .playPause: code = 16
        case .next: code = 17
        case .previous: code = 18
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (code << 16) | ((down ? 0xa : 0xb) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    func batteryReport() async throws -> String {
        try Self.run("/usr/bin/pmset", ["-g", "batt"])
    }

    func clipboardText() async -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func runningAppNames() async -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap(\.localizedName)
    }

    func startTimer(seconds: Int) async {
        let id = UUID()
        timers[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.timers[id] = nil
            NSSound(named: "Glass")?.play()
            self.onTimerFinished?(SpokenDuration.describe(seconds))
        }
    }

    func cancelTimers() async -> Int {
        let count = timers.count
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        return count
    }

    func createReminder(_ text: String, dueInSeconds: Int?) async throws {
        let name = Self.escapeAppleScript(text)
        var properties = "name:\"\(name)\""
        if let seconds = dueInSeconds {
            properties += ", due date:((current date) + \(seconds)), remind me date:((current date) + \(seconds))"
        }
        try runAppleScript("tell application \"Reminders\" to make new reminder with properties {\(properties)}")
    }

    func open(_ fileURL: URL, withAppAt appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration)
    }

    func setDarkMode(_ on: Bool?) async throws {
        let value = on.map { $0 ? "true" : "false" } ?? "not dark mode"
        try runAppleScript(
            "tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)")
    }

    func screenOff() async throws {
        _ = try Self.run("/usr/bin/pmset", ["displaysleepnow"])
    }

    func openTerminal(running command: String) async throws {
        if let error = TerminalLauncher.open(command: command) {
            throw DesktopError.appleScript(error)
        }
    }

    // MARK: Phase 5: Safari + clipboard

    func safariTabInfo() async throws -> (url: String, title: String) {
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then error "Safari has no windows"
            tell front document
                return {URL, name}
            end tell
        end tell
        """
        var errorInfo: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw DesktopError.appleScript(errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error")
        }
        let url = descriptor?.atIndex(1)?.stringValue ?? ""
        let title = descriptor?.atIndex(2)?.stringValue ?? ""
        return (url, title)
    }

    func runJavaScriptInSafari(_ script: String) async throws -> String {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
                               .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Safari"
            if (count of windows) is 0 then error "Safari has no windows"
            do JavaScript "\(escaped)" in front document
        end tell
        """
        var result: AnyObject?
        try runAppleScript(source, returning: &result)
        return (result as? String) ?? ""
    }

    func setClipboard(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: AppleScript helper (with return value)

    private func runAppleScript(_ source: String, returning result: inout AnyObject?) throws {
        guard let script = NSAppleScript(source: source) else {
            throw DesktopError.appleScript("couldn't compile the script")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw DesktopError.appleScript(errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error")
        }
        result = descriptor as AnyObject?
    }

    /// Runs a fixed system tool (never with spoken text) and returns its output.
    private static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Helpers

    private func runningApps(at url: URL) -> [NSRunningApplication] {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        if let bundleID = Bundle(url: url)?.bundleIdentifier {
            let byID = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if !byID.isEmpty { return byID }
        }
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == target
        }
    }

    /// Checks Accessibility trust; the first failure also shows macOS's prompt.
    private func requireAccessibility() throws {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw DesktopError.accessibilityNotGranted }
    }

    private func runAppleScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw DesktopError.appleScript("couldn't compile the script")
        }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw DesktopError.appleScript(errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error")
        }
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// US ANSI virtual key codes (Carbon kVK_*).
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "pageup": 116, "pagedown": 121, "home": 115, "end": 119,
        "leftbracket": 33, "rightbracket": 30, "equal": 24, "minus": 27, "comma": 43
    ]
}
