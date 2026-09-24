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
        .frame(width: 580, height: 520)
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
    @StateObject private var check = PhoneCheck()
    @State private var confirmNewCode = false
    @State private var chosen: String?

    private var links: [PhoneLink] { remote.links(tailscale: check.tailscale) }
    private var link: PhoneLink? { links.first(where: { $0.base == chosen }) ?? links.first }

    var body: some View {
        Form {
            Section {
                Toggle("Control Vox from your phone", isOn: Binding(get: { remote.enabled }, set: { remote.setEnabled($0) }))
                Toggle("Also allow on home Wi-Fi", isOn: Binding(get: { remote.allowLAN }, set: { remote.setAllowLAN($0) }))
                    .disabled(!remote.enabled)
                LabeledContent("Status") { Text(remote.status).foregroundStyle(.secondary) }
            } footer: {
                Text("Home Wi-Fi is plain http: devices on your Wi-Fi can load the page, but nothing works without the pairing code. The iPhone mic button needs the Tailscale link (HTTPS); on Wi-Fi, use the keyboard's dictation mic.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if remote.enabled {
                Section("Pair a phone") { pairing }
                Section("Connection check") { checks }
                Section("Tailscale: HTTPS, voice on iPhone, away from home") { tailscaleSetup }
                Section {
                    LabeledContent("Pairing code") {
                        HStack {
                            Text(remote.code).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Button("New code…") { confirmNewCode = true }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: "\(remote.enabled)-\(remote.allowLAN)") { await check.run(remote) }
        .confirmationDialog("Make a new pairing code?", isPresented: $confirmNewCode) {
            Button("New code", role: .destructive) { remote.regenerateCode() }
        } message: {
            Text("Every paired phone will need to scan the new QR code.")
        }
    }

    @ViewBuilder private var pairing: some View {
        if let link {
            HStack(alignment: .top, spacing: 16) {
                if let image = QRCodeImage.make(link.url) {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 150, height: 150)
                        .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(link.base).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    CheckRow(title: "Reachable from this Mac", result: check.reach[link.base] ?? .unknown)
                    Text(Self.note(for: link.kind)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Copy link") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.url, forType: .string)
                        }
                        Button("Open here") { if let url = URL(string: link.url) { NSWorkspace.shared.open(url) } }
                    }
                    Text("On the phone: scan with the Camera app, open the link, then Share → Add to Home Screen.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if links.count > 1 {
                Picker("Link in the QR code", selection: Binding(get: { link.base }, set: { chosen = $0 })) {
                    ForEach(links) { Text(Self.label(for: $0)).tag($0.base) }
                }
            }
        } else {
            Text("Your phone has no way in yet: Vox is only listening on this Mac.").foregroundStyle(.secondary)
            HStack {
                Button("Use home Wi-Fi now") { remote.setAllowLAN(true) }.buttonStyle(.borderedProminent)
                Text("or set up Tailscale below for HTTPS and voice.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var checks: some View {
        CheckRow(title: "Vox server on this Mac", result: check.server)
        CheckRow(title: "Home Wi-Fi", result: wifiResult)
        CheckRow(title: "Tailscale", result: tailscaleResult)
        if check.firewallOn && remote.allowLAN {
            Text("The macOS Firewall is on. If your phone can't connect on Wi-Fi: System Settings → Network → Firewall → Options → set Vox to “Allow incoming connections” (a rebuilt Vox may need allowing again).")
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Button("Check again") { Task { await check.run(remote) } }.disabled(check.running)
            if check.running { ProgressView().controlSize(.small) }
        }
        Text("These checks run on this Mac. If they pass but the phone can't connect, put the phone on the same Wi-Fi (not guest Wi-Fi or mobile data), or switch Tailscale on in the phone.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var wifiResult: PhoneCheck.Result {
        guard remote.allowLAN else { return .off("Off: turn on “Also allow on home Wi-Fi”") }
        guard let wifi = links.first(where: { $0.kind == .wifi }) else { return .failed("This Mac has no Wi-Fi/Ethernet address") }
        return check.reach[wifi.base] ?? .unknown
    }

    private var tailscaleResult: PhoneCheck.Result {
        switch check.tailscale {
        case .notInstalled: return .off("Not installed (optional)")
        case .notRunning: return .failed("Installed, but not connected: open Tailscale and sign in")
        case .ready(_, serving: false): return .failed("Connected, but not serving Vox: press “Turn on HTTPS link” below")
        case .ready:
            guard let ts = links.first(where: { $0.kind == .tailscale }) else { return .unknown }
            return check.reach[ts.base] ?? .unknown
        }
    }

    @ViewBuilder private var tailscaleSetup: some View {
        switch check.tailscale {
        case .notInstalled:
            Text("Install Tailscale (free) on this Mac and on your phone and sign in to the same account on both. Then come back here and press “Turn on HTTPS link”.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Get Tailscale") { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download")!) }
        case .notRunning:
            Text("Tailscale is installed but not connected. Open it from the menu bar and sign in (the same account as on your phone).")
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Tailscale") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Tailscale.app")) }
        case let .ready(name, serving):
            if serving {
                Text("Serving Vox at https://\(name)/ to your own devices only.").fixedSize(horizontal: false, vertical: true)
                Button("Turn off HTTPS link") { Task { await check.setServe(false, remote) } }.disabled(check.running)
            } else {
                Text("Connected as \(name). This publishes Vox to your own devices only (it runs `tailscale serve --bg 7788`).")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on HTTPS link") { Task { await check.setServe(true, remote) } }
                    .buttonStyle(.borderedProminent).disabled(check.running)
            }
        }
        if let message = check.serveMessage {
            Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        if let url = check.enableURL { Link("Enable HTTPS for your tailnet", destination: url) }
        Text("On the phone: install Tailscale, sign in, keep it switched on, then scan the QR code above.")
            .font(.caption).foregroundStyle(.secondary)
    }

    static func label(for link: PhoneLink) -> String {
        switch link.kind {
        case .tailscale: return "Tailscale (HTTPS): \(link.base)"
        case .wifi: return "Wi-Fi: \(link.base)"
        case .bonjour: return "Wi-Fi name (iPhone): \(link.base)"
        }
    }

    static func note(for kind: PhoneLink.Kind) -> String {
        switch kind {
        case .tailscale: return "Works anywhere your phone has Tailscale switched on. HTTPS, so the mic button works on iPhone."
        case .wifi: return "Home Wi-Fi only. If the router gives this Mac a new address, scan again (or use the .local link on iPhone)."
        case .bonjour: return "Home Wi-Fi only, and survives the Mac getting a new IP. Works on iPhone; many Android phones can't open .local names."
        }
    }
}

/// One ✓/✗ line in the Phone tab.
struct CheckRow: View {
    let title: String
    let result: PhoneCheck.Result

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon.frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail = result.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch result {
        case .unknown: ProgressView().controlSize(.mini)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
        case .off: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

/// Runs the Phone tab's checks off the main thread: Tailscale, firewall, and a real /api/ping to every link.
@MainActor
final class PhoneCheck: ObservableObject {
    enum Result: Equatable {
        case unknown, ok, failed(String), off(String)
        var detail: String? {
            switch self {
            case .unknown, .ok: return nil
            case let .failed(text), let .off(text): return text
            }
        }
    }

    @Published var tailscale = Tailscale.Status.notInstalled
    @Published var firewallOn = false
    @Published var server = Result.unknown
    @Published var reach: [String: Result] = [:]
    @Published var running = false
    @Published var serveMessage: String?
    @Published var enableURL: URL?

    func run(_ remote: RemoteHost) async {
        running = true
        defer { running = false }
        let port = RemoteHost.port
        tailscale = await Task.detached { Tailscale.status(port: port) }.value
        firewallOn = await Task.detached { Firewall.isOn() }.value
        guard remote.enabled else { server = .off("Off"); reach = [:]; return }
        try? await Task.sleep(nanoseconds: 500_000_000)   // a toggle restarts the listener
        server = await Self.ping("http://127.0.0.1:\(port)/")
        let links = remote.links(tailscale: tailscale)
        reach = reach.filter { key, _ in links.contains(where: { $0.base == key }) }
        for link in links { reach[link.base] = await Self.ping(link.base) }
    }

    func setServe(_ on: Bool, _ remote: RemoteHost) async {
        running = true
        serveMessage = on ? "Turning on the HTTPS link…" : nil
        enableURL = nil
        let port = RemoteHost.port
        let result = await Task.detached { Tailscale.serve(on, port: port) }.value
        enableURL = TailscaleServe.enableLink(in: result.output)
        if enableURL != nil {
            serveMessage = "Tailscale needs HTTPS switched on for your account first: open the link below, click Enable, then press “Turn on HTTPS link” again."
        } else if !result.ok {
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            serveMessage = text.isEmpty ? "Tailscale didn't answer. Is it connected?" : String(text.prefix(300))
        } else {
            serveMessage = nil
        }
        running = false
        await run(remote)
    }

    nonisolated static func ping(_ base: String) async -> Result {
        guard let url = URL(string: base + "api/ping") else { return .failed("Bad address") }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  String(decoding: data, as: UTF8.self).contains("\"Vox\"") else { return .failed("Something else answered on that address") }
            return .ok
        } catch {
            return .failed(error.localizedDescription)
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

/// Runs `tailscale` with fixed arguments only (no user input involved).
enum Tailscale {
    enum Status: Equatable, Sendable {
        case notInstalled, notRunning
        case ready(name: String, serving: Bool)
        var name: String? { if case let .ready(name, _) = self { return name }; return nil }
        var serving: Bool { if case .ready(_, true) = self { return true }; return false }
    }

    static let paths = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]
    static var binary: String? { paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) }

    static func status(port: UInt16) -> Status {
        guard let binary else { return .notInstalled }
        guard let name = TailscaleServe.dnsName(statusJSON: FixedCommand.run(binary, ["status", "--json"], timeout: 5).output) else { return .notRunning }
        let serve = FixedCommand.run(binary, ["serve", "status", "--json"], timeout: 5).output
        return .ready(name: name, serving: TailscaleServe.proxies(port: port, statusJSON: serve))
    }

    /// `serve --bg <port>` waits for ever when HTTPS isn't enabled for the tailnet, so it gets a time limit.
    static func serve(_ on: Bool, port: UInt16) -> (ok: Bool, output: String) {
        guard let binary else { return (false, "Tailscale isn't installed.") }
        let args = on ? ["serve", "--bg", "\(port)"] : ["serve", "--https=443", "off"]
        let result = FixedCommand.run(binary, args, timeout: 15)
        return (result.status == 0, String(decoding: result.output, as: UTF8.self))
    }
}

enum Firewall {
    /// Reads the macOS application firewall state (read-only, no admin rights needed).
    static func isOn() -> Bool {
        let tool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return false }
        let text = String(decoding: FixedCommand.run(tool, ["--getglobalstate"], timeout: 3).output, as: UTF8.self).lowercased()
        return text.contains("enabled")
    }
}

/// A fixed executable + fixed arguments, stdout+stderr captured, killed after `timeout`.
enum FixedCommand {
    static func run(_ path: String, _ args: [String], timeout: TimeInterval) -> (output: Data, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = OutputBox()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { collected.append(chunk) }
        }
        do { try process.run() } catch { return (Data(), -1) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)
        pipe.fileHandleForReading.readabilityHandler = nil
        return (collected.data, timedOut ? -1 : process.terminationStatus)
    }

    final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = Data()
        func append(_ chunk: Data) { lock.lock(); stored.append(chunk); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
