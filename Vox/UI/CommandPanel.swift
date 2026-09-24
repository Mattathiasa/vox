import AppKit
import SwiftUI
import VoxCore

// Vox's window: frosted glass over the desktop, SF Pro, continuous corners,
// capsule controls and a Siri-style orb. On macOS 26+ controls use Liquid Glass;
// earlier systems get frosted material with a hairline edge.

// MARK: - Theme

/// Accent colours. Chosen in Settings, stored in UserDefaults ("hudTheme").
enum HUDTheme: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, orange, green, teal, graphite

    var id: String { rawValue }
    var name: String { self == .system ? "System accent" : rawValue.capitalized }

    var accent: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .orange: return Color(nsColor: .systemOrange)
        case .green: return Color(nsColor: .systemGreen)
        case .teal: return Color(nsColor: .systemTeal)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }

    static let storageKey = "hudTheme"
    static let fallback = HUDTheme.system

    /// Old HUD themes ("cyan", "amber" …) fall back to the system accent.
    static func from(_ raw: String) -> HUDTheme { HUDTheme(rawValue: raw) ?? fallback }
}

enum HUDPalette {
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)

    static func color(for kind: EngineEvent.Kind, accent: Color) -> Color {
        switch kind {
        case .success: return success
        case .warning, .confirm: return warning
        case .error: return error
        case .info: return accent
        }
    }

    static func symbol(for kind: EngineEvent.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .confirm: return "questionmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// The bright-top, faint-bottom edge that makes glass read as glass.
    static let hairline = LinearGradient(
        colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
        startPoint: .top, endPoint: .bottom)
}

// MARK: - Phase

enum HUDPhase: Equatable {
    case standby, listening, processing, confirm, linked(String)

    var label: String {
        switch self {
        case .standby: return "Ready"
        case .listening: return "Listening…"
        case .processing: return "Working…"
        case .confirm: return "Needs your OK"
        case let .linked(tool): return "Talking to \(tool)"
        }
    }

    var symbol: String {
        switch self {
        case .standby: return "sparkles"
        case .listening: return "waveform"
        case .processing: return "ellipsis"
        case .confirm: return "questionmark.circle.fill"
        case .linked: return "terminal.fill"
        }
    }

    /// How fast the orb's colours swirl.
    var speed: Double {
        switch self {
        case .standby: return 0.35
        case .listening: return 0.9
        case .processing: return 2.0
        case .confirm: return 0.5
        case .linked: return 0.55
        }
    }

    @MainActor
    static func from(_ state: AppState) -> HUDPhase {
        if state.pendingQuestion != nil { return .confirm }
        if state.isBusy { return .processing }
        if state.isListening || state.isAwake { return .listening }
        if let tool = state.lockedTool { return .linked(tool) }
        return .standby
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass on macOS 26+, frosted material with a hairline edge before that.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(liquidGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .overlay(shape.strokeBorder(HUDPalette.hairline, lineWidth: 0.75))
        }
    }

    /// A frosted content card (sidebar, widgets, terminals).
    func frostedCard(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(HUDPalette.hairline, lineWidth: 0.75))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

@available(macOS 26.0, *)
private func liquidGlass(tint: Color?, interactive: Bool) -> Glass {
    let glass = Glass.regular.tint(tint)
    return interactive ? glass.interactive() : glass
}

/// Real behind-window blur: the desktop shows through, frosted.
struct GlassWindowBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(radius: cornerRadius)
    }

    /// A stretchable rounded-rect mask (the standard way to round an NSVisualEffectView).
    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Windows

/// Borderless panels that can take keyboard input without activating Vox, so
/// the app you were using stays frontmost ("type …" and "press …" land there).
final class VoxPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CommandPanelController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private var panel: VoxPanel?
    private var orb: VoxPanel?
    private var hideTask: Task<Void, Never>?

    static let orbKey = "hudShowOrb"
    static let maximizedKey = "hudMaximized"
    private var restoreFrame: NSRect?

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// Visible and taking keyboard input.
    var isTyping: Bool { isVisible && (panel?.isKeyWindow ?? false) }

    /// Show for typing: the command line gets keyboard focus.
    func showForTyping() {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        orb?.orderOut(nil)
        appState.panelDidShow()
    }

    /// Show without taking focus (while talking).
    func showPassive() {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        orb?.orderOut(nil)
        appState.panelDidShow()
    }

    func show() { showForTyping() }

    func hide() {
        hideTask?.cancel()
        panel?.orderOut(nil)
        appState.panelDidHide()
        showOrbIfEnabled()
    }

    /// After a voice command: hide in a few seconds unless you're typing,
    /// talking to a tool, or Vox is waiting for a yes/no.
    func hideSoonIfIdle() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if !self.isTyping, self.appState.pendingQuestion == nil,
               self.appState.lockedTool == nil, !self.appState.isListening, !self.appState.isAwake {
                self.hide()
            }
        }
    }

    /// The small idle orb in the top-right corner. Click it to open the HUD.
    func showOrbIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: Self.orbKey) as? Bool ?? true
        guard enabled, !isVisible else {
            orb?.orderOut(nil)
            return
        }
        let orb = self.orb ?? makeOrb()
        self.orb = orb
        orb.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        appState.panelDidHide()
    }

    /// Fills the screen (minus menu bar and Dock) or goes back to the previous size.
    func toggleMaximize() {
        guard let panel else { return }
        let maximized = UserDefaults.standard.bool(forKey: Self.maximizedKey)
        if maximized {
            let frame = restoreFrame ?? defaultFrame(on: panel.screen ?? NSScreen.main)
            panel.setFrame(frame, display: true, animate: true)
        } else {
            restoreFrame = panel.frame
            if let screen = panel.screen ?? NSScreen.main {
                panel.setFrame(screen.visibleFrame, display: true, animate: true)
            }
        }
        UserDefaults.standard.set(!maximized, forKey: Self.maximizedKey)
    }

    /// 1200×780, or 90 % of a smaller screen, centred.
    private func defaultFrame(on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1200, visible.width * 0.9)
        let height = min(780, visible.height * 0.9)
        return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    private func makePanel() -> VoxPanel {
        let screen = NSScreen.main
        let panel = VoxPanel(
            contentRect: defaultFrame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        // Native window shadow follows the rounded glass shape.
        panel.hasShadow = true
        panel.minSize = NSSize(width: 640, height: 440)
        panel.contentView = NSHostingView(rootView: HUDView(
            appState: appState,
            close: { [weak self] in self?.hide() },
            toggleMaximize: { [weak self] in self?.toggleMaximize() }))
        if UserDefaults.standard.bool(forKey: Self.maximizedKey), let screen {
            restoreFrame = panel.frame
            panel.setFrame(screen.visibleFrame, display: false)
        }
        return panel
    }

    private func makeOrb() -> VoxPanel {
        let size: CGFloat = 72
        let orb = VoxPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(orb)
        orb.contentView = NSHostingView(rootView: OrbView(appState: appState, open: { [weak self] in
            self?.showForTyping()
        }))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            orb.setFrameOrigin(NSPoint(x: frame.maxX - size - 18, y: frame.maxY - size - 18))
        }
        return orb
    }

    private func configure(_ panel: VoxPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
    }
}

// MARK: - Main window

struct HUDView: View {
    @ObservedObject var appState: AppState
    let close: () -> Void
    let toggleMaximize: () -> Void

    @AppStorage(HUDTheme.storageKey) private var themeRaw = HUDTheme.fallback.rawValue
    @AppStorage(CommandPanelController.maximizedKey) private var maximized = false
    @State private var input = ""
    @State private var showLog = false
    /// A terminal tile blown up to fill the grid area.
    @State private var expandedTool: String?
    @FocusState private var inputFocused: Bool

    private var accent: Color { HUDTheme.from(themeRaw).accent }
    private var phase: HUDPhase { HUDPhase.from(appState) }
    private var cornerRadius: CGFloat { maximized ? 14 : 26 }
    private var windowShape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .circular) }

    var body: some View {
        ZStack {
            backdrop

            GeometryReader { geo in
                let side: CGFloat = 236
                let showLeft = geo.size.width >= 900
                let showRight = geo.size.width >= 1320
                let hasTerminals = !appState.screens.isEmpty
                let mainWidth = geo.size.width - 40 - (showLeft ? side + 16 : 0) - (showRight ? side + 16 : 0)

                VStack(spacing: 14) {
                    topBar
                    HStack(alignment: .top, spacing: 16) {
                        if showLeft { sidebar.frame(width: side) }
                        VStack(spacing: 14) {
                            if hasTerminals {
                                compactStatus
                                launchBar
                                terminalGrid(width: mainWidth, height: geo.size.height - 316)
                            } else {
                                Spacer(minLength: 0)
                                heroStatus
                                launchBar
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showRight { widgets.frame(width: side) }
                    }
                    .frame(maxHeight: .infinity)
                    commandLine
                }
                .padding(20)
            }

            if showLog {
                Color.black.opacity(0.18)
                    .onTapGesture { showLog = false }
                    .transition(.opacity)
                LogOverlay(log: appState.log, accent: accent) { showLog = false }
                    .padding(48)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .clipShape(windowShape)
        .frame(minWidth: 640, minHeight: 440)
        .onAppear {
            inputFocused = true
            if HUDTheme(rawValue: themeRaw) == nil { themeRaw = HUDTheme.fallback.rawValue }
        }
        .onExitCommand(perform: close)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: phase)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showLog)
    }

    // MARK: Backdrop

    /// Frosted desktop + a soft colour wash, the glassmorphism signature.
    private var backdrop: some View {
        ZStack {
            GlassWindowBackground(cornerRadius: cornerRadius)
            GeometryReader { geo in
                ZStack {
                    Circle().fill(accent.opacity(0.22))
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: -geo.size.width * 0.28, y: -geo.size.height * 0.3)
                    Circle().fill(Color.purple.opacity(0.16))
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: geo.size.width * 0.3, y: geo.size.height * 0.28)
                    Circle().fill(Color.pink.opacity(0.10))
                        .frame(width: geo.size.width * 0.35)
                        .offset(x: geo.size.width * 0.25, y: -geo.size.height * 0.35)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 90)
            }
            .allowsHitTesting(false)
            windowShape.strokeBorder(HUDPalette.hairline, lineWidth: 1)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 14) {
            TrafficLights(close: close, minimize: close, zoom: toggleMaximize, zoomed: maximized)
            HStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vox")
                        .font(.system(size: 15, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(appState.setupProblem == nil ? HUDPalette.success : HUDPalette.error)
                            .frame(width: 6, height: 6)
                        Text(appState.setupProblem == nil ? "Ready" : "Needs attention")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            wakeToggle
            GlassIconButton(symbol: "list.bullet.rectangle.portrait", help: "Activity log") { showLog.toggle() }
        }
        .frame(height: 36)
    }

    private var wakeToggle: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.wakeEnabled ? "ear.fill" : "ear")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(appState.wakeEnabled ? accent : .secondary)
            Text(appState.wakeEnabled ? "“\(appState.wakeName)”" : "Wake word off")
                .font(.system(size: 12, weight: .medium))
            Toggle("", isOn: Binding(get: { appState.wakeEnabled },
                                     set: { appState.setWakeEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .tint(accent)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .glassSurface(Capsule())
        .help("Listen for “\(appState.wakeName)”")
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Sessions", symbol: "terminal")
                if appState.sessions.isEmpty {
                    EmptyHint(text: "No tools running", hint: "Say “run claude”")
                } else {
                    ForEach(appState.sessions, id: \.self) { tool in
                        SessionRow(tool: tool, active: appState.lockedTool == tool, accent: accent) {
                            appState.focusTool(tool)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Recent", symbol: "clock.arrow.circlepath")
                if appState.history.isEmpty {
                    EmptyHint(text: "Nothing yet", hint: nil)
                } else {
                    ForEach(appState.history.prefix(6)) { item in
                        HistoryRow(item: item, accent: accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .frostedCard(cornerRadius: 20)
    }

    // MARK: Widgets

    private var widgets: some View {
        VStack(spacing: 12) {
            // Clock
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.month(.wide).day())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .frostedCard()
            }

            // Battery + mic
            HStack(spacing: 12) {
                if let percent = appState.batteryPercent {
                    RingWidget(value: Double(percent) / 100,
                               symbol: appState.batteryCharging ? "bolt.fill" : "battery.100",
                               caption: "\(percent)%",
                               color: percent <= 15 ? HUDPalette.error : HUDPalette.success)
                }
                RingWidget(value: appState.level,
                           symbol: appState.isListening || appState.isAwake ? "mic.fill" : "mic",
                           caption: appState.isListening || appState.isAwake ? "Live" : "Mic",
                           color: accent)
            }

            // Suggestions
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Try saying", symbol: "text.bubble")
                HintTicker(wakeName: appState.wakeName, accent: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frostedCard()

            Spacer(minLength: 0)
        }
    }

    // MARK: Status

    /// No terminals: big orb in the middle, like Siri.
    private var heroStatus: some View {
        VStack(spacing: 16) {
            SiriOrb(level: appState.level, phase: phase, accent: accent,
                    flash: appState.lastResult.map { HUDPalette.color(for: $0.kind, accent: accent) },
                    flashID: appState.lastResult?.id)
                .frame(width: 210, height: 210)
            PhasePill(phase: phase, accent: accent)
            transcriptLine(size: 22, alignment: .center)
            replyBanner
            if let question = appState.pendingQuestion {
                ConfirmBar(question: question, accent: accent,
                           yes: { appState.confirm(true) }, no: { appState.confirm(false) })
            }
            if let problem = appState.setupProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(HUDPalette.error)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)
            }
        }
    }

    /// Terminals running: a slim status card so the grid gets the space.
    private var compactStatus: some View {
        HStack(spacing: 16) {
            SiriOrb(level: appState.level, phase: phase, accent: accent,
                    flash: appState.lastResult.map { HUDPalette.color(for: $0.kind, accent: accent) },
                    flashID: appState.lastResult?.id)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                PhasePill(phase: phase, accent: accent)
                transcriptLine(size: 15, alignment: .leading)
            }
            Spacer(minLength: 8)
            if let question = appState.pendingQuestion {
                ConfirmBar(question: question, accent: accent, compact: true,
                           yes: { appState.confirm(true) }, no: { appState.confirm(false) })
            } else {
                replyBanner
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frostedCard(cornerRadius: 20)
    }

    private func transcriptLine(size: CGFloat, alignment: TextAlignment) -> some View {
        let text: String
        if !appState.heard.isEmpty {
            text = appState.heard
        } else if appState.isAwake {
            text = "Yes? Say a command…"
        } else if appState.isListening {
            text = "Listening… release to run"
        } else {
            text = appState.wakeEnabled ? "Say “\(appState.wakeName)” or type below" : "Hold ⌥Space or type below"
        }
        return Text(text)
            .font(.system(size: size, weight: appState.heard.isEmpty ? .regular : .medium))
            .foregroundStyle(appState.heard.isEmpty ? .secondary : .primary)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: 560, alignment: alignment == .center ? .center : .leading)
            .contentTransition(.opacity)
    }

    /// The last result, as an iOS-style notification banner.
    @ViewBuilder
    private var replyBanner: some View {
        if let result = appState.lastResult, !result.reply.isEmpty, appState.pendingQuestion == nil {
            let color = HUDPalette.color(for: result.kind, accent: accent)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: HUDPalette.symbol(for: result.kind))
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
                Text(result.reply)
                    .font(.system(size: 13))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 480, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .id(result.id)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Launch bar

    /// One-click launch for every tool in config.json that isn't running.
    @ViewBuilder
    private var launchBar: some View {
        let running = Set(appState.screens.map(\.tool))
        let idle = appState.toolNames.filter { tool in
            !running.contains(String(SessionNaming.sessionName(forTool: tool).dropFirst(SessionNaming.prefix.count)))
        }
        if !idle.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Start")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(idle, id: \.self) { tool in
                        GlassCapsuleButton(title: tool, symbol: "plus", tint: accent) { appState.launchTool(tool) }
                            .help("Start \(tool) in its default folder")
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 34)
        }
    }

    // MARK: Terminals

    /// Every running tool's live screen. Columns adapt to the width (1 on narrow
    /// windows, up to 4), at most two rows are shown without scrolling, and each
    /// tool's terminal is resized to its tile so it redraws to fit. Double-click
    /// a tile's title bar (or the expand button) to give it the whole area.
    private func terminalGrid(width: CGFloat, height: CGFloat) -> some View {
        let all = appState.screens
        let shown = expandedTool.flatMap { tool in all.first { $0.tool == tool } }.map { [$0] } ?? all
        let count = max(shown.count, 1)
        let spacing: CGFloat = 14
        let columns = width < 700 ? 1 : max(1, min(count, min(4, Int((width + spacing) / (420 + spacing)))))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let visibleRows = CGFloat(height < 520 ? 1 : min(rows, 2))
        let tileWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let tileHeight = max(180, (height - (visibleRows - 1) * spacing) / visibleRows)
        let fontSize: CGFloat = tileWidth >= 760 ? 12 : (tileWidth >= 480 ? 11 : 10)
        // SF Mono cell ≈ 0.6 em wide, 1.25 em tall. Title bar 40, command bar 46,
        // screen inset 8 each side + 8 text padding each side, 6 bottom gap.
        let cellWidth = Double(fontSize) * 0.602
        let cellHeight = Double(fontSize) * 1.25
        let contentWidth = Double(tileWidth) - 32
        let contentHeight = Double(tileHeight) - TerminalTile.titleHeight - TerminalTile.barHeight - 22

        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
                      spacing: spacing) {
                ForEach(shown) { screen in
                    TerminalTile(screen: screen, linked: appState.lockedTool == screen.tool, accent: accent,
                                 fontSize: fontSize, expanded: expandedTool == screen.tool,
                                 focus: { appState.focusTool(screen.tool) },
                                 toggleExpand: {
                                     withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                         expandedTool = expandedTool == screen.tool ? nil : screen.tool
                                     }
                                 },
                                 openInTerminal: { appState.openToolInTerminal(screen.tool) },
                                 unlink: { appState.exitPassThrough() },
                                 kill: { appState.killTool(screen.tool) },
                                 send: { appState.sendToTool(screen.tool, $0) },
                                 press: { appState.pressKey($0, inTool: screen.tool) })
                        .frame(height: tileHeight)
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.never)
        .onAppear { appState.fitTerminals(width: contentWidth, height: contentHeight,
                                          cellWidth: cellWidth, cellHeight: cellHeight) }
        .onChange(of: "\(Int(contentWidth))x\(Int(contentHeight))x\(fontSize)x\(all.count)") {
            appState.fitTerminals(width: contentWidth, height: contentHeight,
                                  cellWidth: cellWidth, cellHeight: cellHeight)
        }
        .onChange(of: all.map(\.tool)) {
            if let expandedTool, !all.contains(where: { $0.tool == expandedTool }) { self.expandedTool = nil }
        }
    }

    // MARK: Command line (Spotlight-style)

    private var commandLine: some View {
        let live = appState.isListening || appState.isAwake
        return HStack(spacing: 12) {
            Image(systemName: live ? "waveform" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(live ? accent : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: live)
                .frame(width: 22)
            if let tool = appState.lockedTool {
                HStack(spacing: 4) {
                    Image(systemName: "terminal.fill").font(.system(size: 10, weight: .semibold))
                    Text(tool).font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(HUDPalette.success.gradient, in: Capsule())
            }
            TextField("", text: $input, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(appState.isBusy)
            if appState.isBusy {
                ProgressView().controlSize(.small)
            } else {
                KeyCap(label: "return", symbol: "return")
                    .opacity(input.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(inputFocused ? 0.55 : 0), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: inputFocused)
    }

    private var placeholder: String {
        if let tool = appState.lockedTool {
            return "Message \(tool) · “exit” to stop · “vox …” for commands"
        }
        return "Ask Vox · e.g. open chirp in kiro"
    }

    private func send() {
        let text = input
        input = ""
        appState.submit(text)
        inputFocused = true
    }
}

// MARK: - Siri orb

/// Swirling, blurred colour blobs inside a glass sphere. Swells with your voice,
/// swirls faster while working, turns warm when it needs a yes, and pulses a
/// ring in the result's colour.
struct SiriOrb: View {
    let level: Double
    let phase: HUDPhase
    let accent: Color
    let flash: Color?
    let flashID: UUID?
    /// Frames per second; the always-visible idle orb uses fewer to save battery.
    var fps: Double = 30

    @State private var flashStart = Date.distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let flashAge = context.date.timeIntervalSince(flashStart)
            let flashAmount = flash == nil ? 0 : max(0, 1 - flashAge / 1.2)
            Canvas { g, size in
                draw(in: &g, size: size, t: t, flashAmount: flashAmount)
            }
        }
        .onChange(of: flashID) { flashStart = Date() }
    }

    private var palette: [Color] {
        switch phase {
        case .confirm:
            return [Color(nsColor: .systemOrange), Color(nsColor: .systemYellow), Color(nsColor: .systemPink)]
        case .linked:
            return [Color(nsColor: .systemGreen), Color(nsColor: .systemTeal), accent]
        default:
            return [Color(red: 1.0, green: 0.33, blue: 0.62), Color(red: 0.58, green: 0.36, blue: 1.0),
                    Color(red: 0.2, green: 0.56, blue: 1.0), Color(red: 0.28, green: 0.9, blue: 1.0), accent]
        }
    }

    private func draw(in g: inout GraphicsContext, size: CGSize, t: Double, flashAmount: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) / 2
        let lvl = max(0, min(1, level))
        let speed = phase.speed
        let breathe = 1 + 0.025 * sin(t * 1.8) + lvl * 0.14
        let radius = r * 0.74 * CGFloat(breathe)
        let colors = palette
        let active = phase != .standby

        func circle(_ center: CGPoint, _ rad: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - rad, y: center.y - rad, width: rad * 2, height: rad * 2))
        }

        // Soft outer glow.
        g.drawLayer { glow in
            glow.addFilter(.blur(radius: r * 0.16))
            glow.fill(circle(c, radius * 1.02), with: .color(colors[1].opacity(0.28 + lvl * 0.45)))
        }

        // Sphere body: blurred blobs, clipped to the circle.
        g.drawLayer { sphere in
            sphere.clip(to: circle(c, radius))
            sphere.fill(circle(c, radius), with: .color(colors[colors.count - 1].opacity(0.18)))
            sphere.drawLayer { blobs in
                blobs.addFilter(.blur(radius: radius * 0.3))
                for (i, color) in colors.enumerated() {
                    let dir: Double = i % 2 == 0 ? 1 : -1
                    let angle = t * speed * (0.55 + 0.2 * Double(i)) * dir + Double(i) * 1.9
                    let distance = radius * CGFloat(0.34 + 0.1 * sin(t * 0.8 + Double(i)) + lvl * 0.18)
                    let blobR = radius * CGFloat(0.55 + 0.08 * sin(t * 1.2 + Double(i) * 2))
                    let p = CGPoint(x: c.x + CGFloat(cos(angle)) * distance, y: c.y + CGFloat(sin(angle)) * distance)
                    blobs.fill(circle(p, blobR), with: .color(color.opacity(active ? 0.95 : 0.75)))
                }
            }
            // Specular highlight, top-left: the glass.
            let highlight = CGRect(x: c.x - radius * 0.62, y: c.y - radius * 0.9, width: radius * 1.1, height: radius * 0.8)
            sphere.fill(Path(ellipseIn: highlight), with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)]),
                startPoint: CGPoint(x: highlight.midX, y: highlight.minY),
                endPoint: CGPoint(x: highlight.midX, y: highlight.maxY)))
        }

        // Glass rim.
        g.stroke(circle(c, radius), with: .linearGradient(
            Gradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.08)]),
            startPoint: CGPoint(x: c.x, y: c.y - radius), endPoint: CGPoint(x: c.x, y: c.y + radius)),
            lineWidth: 1)

        // Result ripple.
        if flashAmount > 0, let flash {
            let ripple = radius * (1 + CGFloat(1 - flashAmount) * 0.28)
            g.stroke(circle(c, ripple), with: .color(flash.opacity(flashAmount * 0.9)), lineWidth: 2.5)
        }
    }
}

// MARK: - Idle orb

struct OrbView: View {
    @ObservedObject var appState: AppState
    let open: () -> Void
    @AppStorage(HUDTheme.storageKey) private var themeRaw = HUDTheme.fallback.rawValue
    @State private var hovering = false

    var body: some View {
        let accent = HUDTheme.from(themeRaw).accent
        ZStack {
            Circle()
                .fill(.clear)
                .glassSurface(Circle(), interactive: true)
            SiriOrb(level: appState.level, phase: HUDPhase.from(appState), accent: accent,
                    flash: nil, flashID: nil, fps: 12)
                .padding(6)
            if !appState.wakeEnabled {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: 60, height: 60)
        .frame(width: 72, height: 72)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .help("Vox — click to open, or say “\(appState.wakeName)”")
    }
}

// MARK: - Components

/// Red / yellow / green, like every Mac window. Glyphs appear on hover.
struct TrafficLights: View {
    let close: () -> Void
    let minimize: () -> Void
    let zoom: () -> Void
    var zoomed = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(red: 1.0, green: 0.37, blue: 0.34), "xmark", "Hide (Esc)", close)
            light(Color(red: 1.0, green: 0.74, blue: 0.18), "minus", "Hide", minimize)
            light(Color(red: 0.16, green: 0.79, blue: 0.25),
                  zoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                  zoomed ? "Restore size" : "Fill the screen", zoom)
        }
        .onHover { hovering = $0 }
    }

    private func light(_ color: Color, _ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .opacity(hovering ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }
}

struct EmptyHint: View {
    let text: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
            if let hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Status capsule under the orb.
struct PhasePill: View {
    let phase: HUDPhase
    let accent: Color

    private var color: Color {
        switch phase {
        case .confirm: return HUDPalette.warning
        case .linked: return HUDPalette.success
        default: return accent
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: phase.symbol)
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.pulse, isActive: phase == .processing || phase == .listening)
            Text(phase.label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .glassSurface(Capsule(), tint: color.opacity(0.15))
        .contentTransition(.opacity)
    }
}

/// Round glass button with an SF Symbol.
struct GlassIconButton: View {
    let symbol: String
    var help: String = ""
    var size: CGFloat = 30
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Capsule glass button: "+ claude".
struct GlassCapsuleButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .accentColor
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.clear), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassSurface(Capsule(), tint: prominent ? nil : tint.opacity(hovering ? 0.18 : 0.06), interactive: true)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// A Mac keyboard key.
struct KeyCap: View {
    let label: String
    var symbol: String? = nil

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            } else {
                Text(label).font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 22, minHeight: 22)
        .padding(.horizontal, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 0.5, y: 1)
    }
}

/// iOS alert-style confirmation.
struct ConfirmBar: View {
    let question: String
    let accent: Color
    var compact = false
    let yes: () -> Void
    let no: () -> Void

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            if !compact {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HUDPalette.warning)
            }
            Text(question)
                .font(.system(size: compact ? 12 : 14, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 5)
                .frame(maxWidth: compact ? 320 : 380)
            HStack(spacing: 10) {
                // No Return shortcut on Yes: Return also submits the command line.
                GlassCapsuleButton(title: "Cancel", tint: .secondary, action: no)
                GlassCapsuleButton(title: "Yes, do it", tint: HUDPalette.warning, prominent: true, action: yes)
            }
            if !compact {
                Text("or say “yes” / “no”")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(compact ? 12 : 20)
        .glassSurface(RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

/// Sidebar row: iOS-Settings-style icon tile, name, state. Click to talk to it.
struct SessionRow: View {
    let tool: String
    let active: Bool
    let accent: Color
    var select: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background((active ? HUDPalette.success : accent).gradient,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(tool).font(.system(size: 13, weight: .medium))
                    Text(active ? "Talking" : "Running")
                        .font(.system(size: 11))
                        .foregroundStyle(active ? HUDPalette.success : .secondary)
                }
                Spacer()
                if active {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HUDPalette.success)
                        .symbolEffect(.variableColor.iterative)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(active ? 0.1 : (hovering ? 0.06 : 0)),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(active ? "Talking to \(tool)" : "Talk to \(tool)")
    }
}

struct HistoryRow: View {
    let item: HistoryItem
    let accent: Color

    var body: some View {
        let color = HUDPalette.color(for: item.kind, accent: accent)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.spoken ? "mic.fill" : "keyboard.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.command)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !item.reply.isEmpty {
                    Text(item.reply)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

/// iOS widget: circular gauge with a symbol and a caption.
struct RingWidget: View {
    let value: Double
    let symbol: String
    let caption: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, value)))
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.15), value: value)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 54, height: 54)
            Text(caption)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .frostedCard()
    }
}

struct HintTicker: View {
    let wakeName: String
    let accent: Color

    static let hints = [
        "open chirp in kiro", "run freebuff in vox", "what time is it", "search youtube for lofi",
        "set a timer for 10 minutes", "remind me to stretch in an hour", "close tab", "dark mode",
        "what's 15 percent of 80", "open downloads", "play", "next song", "lock screen",
        "create a note called ideas", "directions to bole airport", "battery", "help"
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 4)) { context in
            let index = Int(context.date.timeIntervalSinceReferenceDate / 4) % Self.hints.count
            VStack(alignment: .leading, spacing: 6) {
                Text("“\(wakeName), \(Self.hints[index])”")
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))
                Text("Say “help” for everything")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
        }
    }
}

/// One running tool: a little Mac window with a live terminal and a command field.
struct TerminalTile: View {
    let screen: SessionScreen
    let linked: Bool
    let accent: Color
    var fontSize: CGFloat = 11
    var expanded = false
    let focus: () -> Void
    var toggleExpand: () -> Void = {}
    let openInTerminal: () -> Void
    let unlink: () -> Void
    let kill: () -> Void
    var send: (String) -> Void = { _ in }
    var press: (String) -> Void = { _ in }

    static let titleHeight: Double = 40
    static let barHeight: Double = 46

    @State private var command = ""
    @FocusState private var commandFocused: Bool

    /// (label, tmux key, help)
    static let keys: [(String, String, String)] = [
        ("⏎", "Enter", "Enter"), ("esc", "Escape", "Escape"), ("↑", "Up", "Up arrow"), ("↓", "Down", "Down arrow"),
        ("⇥", "Tab", "Tab"), ("⌃C", "C-c", "Interrupt (Ctrl-C)")
    ]

    private var status: Color { screen.exited ? HUDPalette.error : (linked ? HUDPalette.success : accent) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            titleBar
            ScrollView([.vertical, .horizontal]) {
                Text(screen.text.isEmpty ? "Starting…" : screen.text)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .defaultScrollAnchor(.bottomLeading)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 8)
            commandBar
        }
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(linked ? AnyShapeStyle(HUDPalette.success.opacity(0.8)) : AnyShapeStyle(HUDPalette.hairline),
                                    lineWidth: linked ? 1.5 : 0.75))
        .shadow(color: linked ? HUDPalette.success.opacity(0.3) : .black.opacity(0.18), radius: linked ? 16 : 12, y: 6)
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Circle().fill(status.gradient).frame(width: 9, height: 9)
            Text(screen.tool)
                .font(.system(size: 13, weight: .semibold))
            Text(screen.exited ? "Exited" : (linked ? "Talking" : "Click to talk"))
                .font(.system(size: 11))
                .foregroundStyle(screen.exited ? HUDPalette.error : .secondary)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer()
            if linked {
                TileButton(symbol: "eject.fill", help: "Stop talking to \(screen.tool)", action: unlink)
            }
            TileButton(symbol: expanded ? "square.grid.2x2" : "arrow.up.left.and.arrow.down.right",
                       help: expanded ? "Back to all terminals" : "Expand this terminal", action: toggleExpand)
            TileButton(symbol: "macwindow", help: "Open in Terminal", action: openInTerminal)
            TileButton(symbol: "xmark", help: "Kill \(screen.tool)", tint: HUDPalette.error, action: kill)
        }
        .padding(.horizontal, 12)
        .frame(height: Self.titleHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggleExpand)
        .onTapGesture(perform: focus)
    }
}

/// Small round button in a terminal's title bar.
struct TileButton: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? AnyShapeStyle(tint ?? .primary) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(hovering ? 0.12 : 0.05), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

extension TerminalTile {
    /// Type a command for this tool and press Return; keycaps for TUIs.
    var commandBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                TextField("", text: $command, prompt: Text("Command for \(screen.tool)…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($commandFocused)
                    .disabled(screen.exited)
                    .onSubmit {
                        let text = command
                        command = ""
                        if text.trimmingCharacters(in: .whitespaces).isEmpty {
                            press("Enter")
                        } else {
                            send(text)
                        }
                        commandFocused = true
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(commandFocused ? 0.6 : 0), lineWidth: 1))
            ForEach(Self.keys, id: \.1) { key in
                Button { press(key.1) } label: { KeyCap(label: key.0) }
                    .buttonStyle(.plain)
                    .help(key.2)
                    .disabled(screen.exited)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.barHeight)
    }
}

/// Activity log, as a glass sheet.
struct LogOverlay: View {
    let log: [LogLine]
    let accent: Color
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "list.bullet.rectangle.portrait")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                GlassIconButton(symbol: "xmark", help: "Close", size: 26, action: close)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(log) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.date, format: .dateTime.hour().minute().second())
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text(line.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(line.kind == .info ? AnyShapeStyle(.primary)
                                                     : AnyShapeStyle(HUDPalette.color(for: line.kind, accent: accent)))
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                        }
                    }
                }
                .onAppear { if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(HUDPalette.hairline, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }
}
