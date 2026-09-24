import Foundation
@testable import VoxCore

@MainActor
final class FakeDesktop: DesktopControlling {
    enum Call: Equatable {
        case openApp(String)
        case openURL(String)
        case createNote(String)
        case typeText(String)
        case pressKey(String)
        case quitApp(String)
        case hideApp(String)
        case volume(VolumeChange)
        case media(MediaKey)
        case timer(Int)
        case cancelTimers
        case reminder(String, Int?)
        case openWith(String, String)
        case darkMode(Bool?)
        case screenOff
        case terminal(String)
        case safariTab
        case safariJS(String)
        case setClipboard(String)
    }

    var battery = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t82%; discharging; 3:10 remaining present: true"
    var clipboard: String? = "hello from the clipboard"
    var appNames = ["Safari", "Notes"]
    var timers = 0

    /// App file names ("Safari.app") that count as running.
    var running: Set<String> = []

    var calls: [Call] = []
    var failWith: Error?

    func openApp(at url: URL) async throws {
        try check()
        calls.append(.openApp(url.lastPathComponent))
    }

    func openURL(_ url: URL) async throws {
        try check()
        calls.append(.openURL(url.absoluteString))
    }

    func createNote(_ text: String) async throws {
        try check()
        calls.append(.createNote(text))
    }

    func typeText(_ text: String) async throws {
        try check()
        calls.append(.typeText(text))
    }

    func pressKey(_ combo: KeyCombo) async throws {
        try check()
        calls.append(.pressKey(combo.description))
    }

    func quitApp(at url: URL) async throws -> Bool {
        try check()
        calls.append(.quitApp(url.lastPathComponent))
        return running.contains(url.lastPathComponent)
    }

    func hideApp(at url: URL) async throws -> Bool {
        try check()
        calls.append(.hideApp(url.lastPathComponent))
        return running.contains(url.lastPathComponent)
    }

    func setVolume(_ change: VolumeChange) async throws {
        try check()
        calls.append(.volume(change))
    }

    func pressMediaKey(_ key: MediaKey) async throws { calls.append(.media(key)) }
    func batteryReport() async throws -> String { battery }
    func clipboardText() async -> String? { clipboard }
    func runningAppNames() async -> [String] { appNames }
    func startTimer(seconds: Int) async { timers += 1; calls.append(.timer(seconds)) }
    func cancelTimers() async -> Int { defer { timers = 0 }; calls.append(.cancelTimers); return timers }
    func createReminder(_ text: String, dueInSeconds: Int?) async throws { calls.append(.reminder(text, dueInSeconds)) }
    func open(_ fileURL: URL, withAppAt appURL: URL) async throws {
        calls.append(.openWith(fileURL.lastPathComponent, appURL.lastPathComponent))
    }
    func setDarkMode(_ on: Bool?) async throws { calls.append(.darkMode(on)) }
    func screenOff() async throws { calls.append(.screenOff) }
    func openTerminal(running command: String) async throws { calls.append(.terminal(command)) }

    var safariResult: (url: String, title: String) = ("https://example.com", "Example")
    var jsResult: String = "undefined"

    func safariTabInfo() async throws -> (url: String, title: String) {
        try check()
        calls.append(.safariTab)
        return safariResult
    }

    func runJavaScriptInSafari(_ script: String) async throws -> String {
        try check()
        calls.append(.safariJS(script))
        return jsResult
    }

    func setClipboard(_ text: String) async throws {
        try check()
        calls.append(.setClipboard(text))
    }

    private func check() throws {
        if let failWith { throw failWith }
    }
}

extension AppCatalog {
    static let test = AppCatalog(entries: [
        "Safari", "Notes", "TextEdit", "Visual Studio Code", "Google Chrome", "Xcode",
        "System Settings", "Claude", "Kiro", "Antigravity"
    ].map { AppEntry(name: $0, url: URL(fileURLWithPath: "/Applications/\($0).app")) })
}
