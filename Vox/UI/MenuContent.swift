import SwiftUI
import VoxCore
import KeyboardShortcuts

/// The menu-bar dropdown.
struct MenuContent: View {
    @ObservedObject var appState: AppState
    let panel: CommandPanelController

    var body: some View {
        Button("Show Command Panel") { panel.showForTyping() }
        Toggle("Listen for \"\(appState.wakeName)\"", isOn: Binding(
            get: { appState.wakeEnabled },
            set: { appState.setWakeEnabled($0) }
        ))
        Toggle("Launch at login", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { appState.setLaunchAtLogin($0) }
        ))
        Text("Or hold ⌥Space to talk, tap to type")
        if !appState.lastHeard.isEmpty {
            Text("Last heard: \(appState.lastHeard)")
        }

        Divider()

        Text(appState.lockedTool.map { "Talking to \($0)" } ?? "Idle")
        if let problem = appState.setupProblem {
            Text("⚠︎ " + problem.prefix(60))
        }

        Divider()

        Button("Open Config") { appState.openConfig() }
        Button("Reveal Config in Finder") { appState.revealConfig() }
        Button("Reload Config") { appState.reloadConfig() }
        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit Vox") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @AppStorage(HUDTheme.storageKey) private var themeRaw = HUDTheme.fallback.rawValue
    @AppStorage("hudShowOrb") private var showOrb = true

    var body: some View {
        TabView {
            Form {
                KeyboardShortcuts.Recorder("Talk (hold) / type (tap):", name: .talk)
                Picker("Accent colour:", selection: $themeRaw) {
                    ForEach(HUDTheme.allCases) { theme in
                        Text(theme.name).tag(theme.rawValue)
                    }
                }
                Toggle("Show the orb when idle", isOn: $showOrb)
                Toggle("Launch at login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.setLaunchAtLogin($0) }
                ))
            }
            .padding(20)
            .tabItem { Text("General") }

            ToolsEditor(tools: $appState.tools)
                .tabItem { Text("Tools") }

            ProjectsEditor(projects: $appState.projects)
                .tabItem { Text("Projects") }

            LLMSettings(config: Binding(
                get: { appState.llmConfig ?? LLMConfig() },
                set: { appState.llmConfig = $0 }
            ), save: appState.saveConfig)
                .tabItem { Text("LLM") }
        }
        .frame(width: 560, height: 380)
        .toolbar {
            Button("Save") { appState.saveConfig() }
            Button("Reload") { appState.reloadConfig() }
        }
    }
}

/// Editor for the tools table.
struct ToolsEditor: View {
    @Binding var tools: [ToolConfig]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Tools (terminal sessions)")
                .font(.headline)
            ForEach(tools.indices, id: \.self) { idx in
                let tool = $tools[idx]
                VStack(alignment: .leading) {
                    TextField("Name", text: tool.name)
                    TextField("Command (exact shell command)", text: tool.command)
                    TextField("Aliases (comma-separated)", text: Binding(
                        get: { tool.wrappedValue.aliases.joined(separator: ", ") },
                        set: { tool.aliases.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                    TextField("Default directory (optional)", text: Binding(
                        get: { tool.wrappedValue.defaultDirectory ?? "" },
                        set: { tool.defaultDirectory.wrappedValue = $0.isEmpty ? nil : $0 }
                    ))
                    Stepper("Startup delay: \(Int(tool.wrappedValue.startupDelaySeconds))s", value: tool.startupDelaySeconds, in: 0...10, step: 0.5)
                }
                .padding(.vertical, 4)
            }
            Button("+ Add Tool") { tools.append(ToolConfig(name: "", command: "")) }
        }
        .padding()
    }
}

/// Editor for the projects table.
struct ProjectsEditor: View {
    @Binding var projects: [ProjectConfig]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Projects (working directories)")
                .font(.headline)
            ForEach(projects.indices, id: \.self) { idx in
                let project = $projects[idx]
                VStack(alignment: .leading) {
                    TextField("Name", text: project.name)
                    TextField("Path", text: project.path)
                    TextField("Aliases (comma-separated)", text: Binding(
                        get: { project.wrappedValue.aliases.joined(separator: ", ") },
                        set: { project.aliases.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                    ))
                }
                .padding(.vertical, 4)
            }
            Button("+ Add Project") { projects.append(ProjectConfig(name: "", path: "")) }
        }
        .padding()
    }
}

/// Settings for the LLM fallback (Phase 6).
struct LLMSettings: View {
    @Binding var config: LLMConfig
    let save: () -> Void

    var body: some View {
        Form {
            Toggle("Enable LLM fallback", isOn: $config.enabled)
            Picker("Provider", selection: $config.provider) {
                Text("Apple (on-device)").tag(LLMProvider.apple)
                Text("Claude API").tag(LLMProvider.claude)
            }
            if config.provider == .claude {
                HStack {
                    SecureField("Claude API key (stored in Keychain)", text: Binding(
                        get: { Keychain.read("com.vox.llm.claude-api-key") ?? "" },
                        set: { _ = Keychain.set("com.vox.llm.claude-api-key", $0) }
                    ))
                    Button("Save key") { save() }
                }
            }
            TextField("Model (optional)", text: Binding(
                get: { config.model ?? "" },
                set: { config.model = $0.isEmpty ? nil : $0 }
            ))
            Stepper("Timeout: \(Int(config.timeoutSeconds))s", value: $config.timeoutSeconds, in: 5...30, step: 1)
            Text("When Vox doesn't recognize a command, it asks the LLM to translate it into a Vox command. The LLM never runs shell — all output goes through the same safety checks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
