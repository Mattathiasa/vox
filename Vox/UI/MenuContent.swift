import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
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

            PhoneSettings(remote: appState.remote)
                .tabItem { Text("Phone") }

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


// MARK: - Phone remote settings (Phase 8)

struct PhoneSettings: View {
    @ObservedObject var remote: RemoteHost
    @State private var tailscaleName: String?
    @State private var confirmNewCode = false

    private var pairingURL: String? {
        if let name = tailscaleName { return "https://\(name)/#pair=\(remote.code)" }
        return remote.lanURLs.first
    }

    var body: some View {
        Form {
            Toggle("Control Vox from your phone", isOn: Binding(get: { remote.enabled }, set: { remote.setEnabled($0) }))
            Toggle("Also allow on home Wi-Fi (http, no voice on iPhone)", isOn: Binding(get: { remote.allowLAN }, set: { remote.setAllowLAN($0) }))
                .disabled(!remote.enabled)
            LabeledContent("Status") { Text(remote.status).foregroundStyle(.secondary) }

            if remote.enabled {
                if let url = pairingURL {
                    HStack(alignment: .top, spacing: 16) {
                        if let image = QRCodeImage.make(url) {
                            Image(nsImage: image).interpolation(.none).resizable().frame(width: 150, height: 150)
                                .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 10))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scan with your phone's camera").font(.headline)
                            Text(tailscaleName == nil ? "Home Wi-Fi link. For voice and use away from home, set up Tailscale (below)." :
                                    "Tailscale link: works anywhere your phone has Tailscale on, with voice.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Copy link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }
                            Text("Then tap Share → Add to Home Screen for an app icon.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No phone link yet. Set up Tailscale (recommended) or allow home Wi-Fi.")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Pairing code") {
                    HStack {
                        Text(remote.code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button("New code…") { confirmNewCode = true }
                    }
                }
                DisclosureGroup("Set up Tailscale (HTTPS, voice, away from home)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Install Tailscale on this Mac and your phone, sign in to the same account.")
                        Text("2. Double-click scripts/Remote-Tailscale.command in the Vox folder (runs `tailscale serve --bg 7788`).")
                        Text("3. Come back here: the QR code switches to your https://…ts.net link.")
                    }
                    .font(.caption)
                    Button("Check again") { tailscaleName = Tailscale.dnsName() }
                }
            }
        }
        .padding(20)
        .onAppear { tailscaleName = Tailscale.dnsName() }
        .confirmationDialog("Make a new pairing code?", isPresented: $confirmNewCode) {
            Button("New code", role: .destructive) { remote.regenerateCode() }
        } message: {
            Text("Every paired phone will need to scan the new QR code.")
        }
    }
}

enum QRCodeImage {
    static func make(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

/// Reads this Mac's Tailscale name with a fixed command (no user input involved).
enum Tailscale {
    static let paths = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]

    static func dnsName() -> String? {
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = json["Self"] as? [String: Any], let name = me["DNSName"] as? String, !name.isEmpty else { return nil }
        return name.hasSuffix(".") ? String(name.dropLast()) : name
    }
}
