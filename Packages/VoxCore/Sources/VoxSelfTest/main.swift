import Foundation
import VoxCore

// Phase 1/2 checks on the real Mac: real tmux, the owner's config, the owner's tools.
// Uses its own session names (vox-selftest-*), so it never touches sessions Vox started.

var failures = 0

func check(_ ok: Bool, _ label: String) {
    print((ok ? "PASS  " : "FAIL  ") + label)
    if !ok { failures += 1 }
}

func wait(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

print("===== Vox self-test \(Date()) =====")

let config: VoxConfig
do {
    config = try ConfigStore.load(from: ConfigStore.defaultURL)
    print("config: \(config.tools.map(\.name).joined(separator: ", "))")
} catch {
    print("FAIL  config: \(error)")
    exit(1)
}

guard let tmuxPath = TmuxAdapter.locate(configured: config.tmuxPath) else {
    print("FAIL  tmux not found")
    exit(1)
}
let tmux = TmuxAdapter(tmuxPath: tmuxPath, shell: config.shell)
let projectsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").path

// 1. Launch + literal typing + Enter + right folder, 20 cycles, with a plain shell.
print("\n--- 1. tmux round trip (20 cycles) ---")
let shellSession = "vox-selftest-shell"
var cyclesOK = 0
for i in 1...20 {
    try? tmux.kill(session: shellSession)
    do {
        try tmux.start(session: shellSession, command: "exec /bin/zsh -f", directory: "~/Projects")
        wait(0.5)
        try tmux.type(session: shellSession, text: "echo VOX_OK_\(i) $PWD")
        wait(0.15)
        try tmux.submit(session: shellSession)
        wait(0.6)
        let screen = try tmux.capture(session: shellSession, lines: 50)
        if screen.contains("VOX_OK_\(i) \(projectsDir)") {
            cyclesOK += 1
        } else if cyclesOK == i - 1 {
            print("cycle \(i) screen:\n\(screen)")
        }
    } catch {
        print("cycle \(i): \(error)")
    }
}
try? tmux.kill(session: shellSession)
check(cyclesOK == 20, "launch, type, Enter, correct folder: \(cyclesOK)/20 cycles")

// 2. A program that exits: session kept, pane reported dead, last output visible.
print("\n--- 2. remain-on-exit ---")
let exitSession = "vox-selftest-exit"
try? tmux.kill(session: exitSession)
do {
    try tmux.start(session: exitSession, command: "echo VOX_BYE; exit 3", directory: "~/Projects")
    wait(1.5)
    check(tmux.hasSession(exitSession), "session still exists after the program exited")
    check(tmux.isPaneDead(exitSession), "Vox can tell the program exited")
    let screen = (try? tmux.capture(session: exitSession)) ?? ""
    check(screen.contains("VOX_BYE"), "the exited program's last output is still visible")
} catch {
    check(false, "start exiting program: \(error)")
}
try? tmux.kill(session: exitSession)

// 3. What "Balcha, run X" turns into (router), for phrasings speech-to-text produces.
print("\n--- 3. voice phrasings -> launch in ~/Projects ---")
let phrasings: [(String, String)] = [
    ("run claude", "claude"), ("Run Claude.", "claude"), ("run claude code", "claude"), ("run cloud code", "claude"),
    ("start claude", "claude"), ("open claude", "claude"),
    ("run freebuff", "freebuff"), ("run free buff", "freebuff"), ("Run free buff.", "freebuff"), ("start freebuff", "freebuff"),
    ("run kilo", "kilo"), ("Run Kilo.", "kilo"), ("run kilo code", "kilo"), ("start kilo", "kilo"), ("launch kilocode", "kilo")
]
for (phrase, tool) in phrasings {
    guard config.tool(named: tool) != nil else { continue }
    var router = SessionRouter(config: config)
    let actions = router.handle(phrase)
    let expected = RouterAction.launch(tool: tool, directory: config.tool(named: tool)?.defaultDirectory, initialPrompt: nil)
    check(actions == [expected], "“\(phrase)” -> \(actions.first.map { "\($0)" } ?? "nothing")")
}

// 4. The real tools, started exactly as Vox starts them.
print("\n--- 4. real tools ---")
for name in ["freebuff", "claude", "kilo"] {
    guard let tool = config.tool(named: name) else {
        check(false, "\(name) is in config.json")
        continue
    }
    let session = "vox-selftest-\(name)"
    try? tmux.kill(session: session)
    do {
        try tmux.start(session: session, command: tool.command, directory: tool.defaultDirectory)
    } catch {
        check(false, "\(name) starts: \(error)")
        continue
    }
    wait(8)
    let dead = tmux.isPaneDead(session)
    let path = tmux.currentPath(session: session) ?? "?"
    let screen = (try? tmux.capture(session: session, lines: 60)) ?? ""
    check(!dead, "\(name) still running after 8 s (command: \(tool.command))")
    check(path == projectsDir, "\(name) started in \(path)")
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    print("---- \(name) screen (last 20 lines) ----")
    print(lines.suffix(20).joined(separator: "\n"))
    print("----")

    // Does the tool's interface accept typed text + Enter? "/help" costs no AI credits.
    if !dead {
        let before = (try? tmux.capture(session: session, lines: 60)) ?? ""
        try? tmux.type(session: session, text: "/help")
        wait(0.3)
        try? tmux.submit(session: session)
        wait(3)
        let after = (try? tmux.capture(session: session, lines: 60)) ?? ""
        check(after != before && !tmux.isPaneDead(session), "\(name) accepted a typed command (/help) and Enter")
        let afterLines = after.split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        print("---- \(name) after /help (last 12 lines) ----")
        print(afterLines.suffix(12).joined(separator: "\n"))
        print("----")
        try? tmux.sendKey(session: session, key: "Escape")
        wait(0.3)
        try? tmux.sendKey(session: session, key: "Escape")
    }
    try? tmux.kill(session: session)
}

print("\n===== \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED") =====")
exit(failures == 0 ? 0 : 1)
