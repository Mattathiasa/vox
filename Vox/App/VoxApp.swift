import SwiftUI

@main
struct VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Vox", systemImage: "waveform") {
            MenuContent(appState: appDelegate.appState, panel: appDelegate.panel)
        }
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) lazy var panel = CommandPanelController(appState: appState)
    private var pressStart: Date?

    /// Shorter than this is a tap (open the typing panel), longer is talking.
    private let tapThreshold: TimeInterval = 0.35

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.desktop.prepareForInput = { [weak self] in self?.panel.hide() }
        appState.onWake = { [weak self] in self?.panel.showPassive() }
        appState.onVoiceCommandDone = { [weak self] in self?.panel.hideSoonIfIdle() }
        panel.showOrbIfEnabled()
        Hotkeys.register(
            onPress: { [weak self] in self?.hotkeyDown() },
            onRelease: { [weak self] in self?.hotkeyUp() }
        )
    }

    private func hotkeyDown() {
        guard pressStart == nil else { return } // ignore key repeat
        pressStart = Date()
        if !panel.isTyping { panel.showPassive() }
        appState.startListening()
    }

    private func hotkeyUp() {
        guard let start = pressStart else { return }
        pressStart = nil

        if Date().timeIntervalSince(start) < tapThreshold {
            appState.cancelListening()
            if panel.isTyping { panel.hide() } else { panel.showForTyping() }
        } else {
            appState.finishListening { [weak self] in
                self?.panel.hideSoonIfIdle()
            }
        }
    }
}
