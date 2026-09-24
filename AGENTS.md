# Instructions for AI agents working on Vox

You are picking up work on **Vox**, a voice-controlled macOS assistant. Read this
file first, then [ROADMAP.md](ROADMAP.md), then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## How to pick up work

1. Read **"Current state"** in ROADMAP.md.
2. **Verification before new features.** If the current phase has unchecked
   *Verification* boxes, do those first. Stacking features on unverified code
   is how this project would rot.
3. Take the first open task in the current phase. Don't skip ahead a phase.
4. Mark it `[~]` and add a Log entry that says you started.
5. When done, set it to `[x]` (verified) or `[w]` (written, couldn't run),
   update "Current state", and finish your Log entry: what changed and **how you verified it**.

If you can't run Swift (e.g. you're in a Linux sandbox), say so in the Log and
use `[w]`. Never claim a check you didn't run.

## Commands

```bash
scripts/bootstrap.sh          # first time on a Mac: brew tmux+xcodegen, tests, generate project
scripts/test.sh               # before every commit: core tests + unsigned app build
(cd Packages/VoxCore && swift test)   # core tests only (also works on Linux)
xcodegen generate             # after ANY change to project.yml or added/removed app files
scripts/Verify.command        # double-clickable: tools + tests + app build, log in .logs/verify.log
                              # (agents without a macOS shell: ask the owner to double-click it, then read the log)
tmux -L vox ls                # Vox's sessions (separate tmux server)
tmux -L vox attach -t vox-freebuff    # watch a tool
```

## Layout

```
Packages/VoxCore/        Platform-independent logic. No AppKit/SwiftUI. Fully unit-tested.
  Sources/VoxCore/
    Config/              VoxConfig (Codable), ConfigStore (load/save/validate)
    Parsing/             Tokenizer, PhraseMatcher, CommandParser (text -> Intent)
    Routing/             SessionRouter: state machine (text -> [RouterAction])
    Safety/              SafetyPolicy: which text needs a spoken "yes"
    Terminal/            ProcessRunner, TmuxAdapter
    Engine/              VoxEngine (actor): executes RouterActions via adapters
    Desktop/             DesktopCommand, KeyCombo, WebAddress, AppCatalog, DesktopControlling protocol
    Voice/               WakeWordConfig, WakeWordDetector, WakeWordTracker (timing rules)
  Tests/VoxCoreTests/    XCTest. FakeTmuxRunner simulates tmux, FakeDesktop the GUI.
Vox/                     macOS app (thin): SwiftUI + AppKit only
  App/                   VoxApp (AppDelegate, hotkey), AppState, Hotkeys, TerminalLauncher
  Voice/                 SpeechController (push-to-talk), WakeWordListener (always-on)
  Desktop/               DesktopController: NSWorkspace, AppleScript (Notes), CGEvent typing
  UI/                    CommandPanel (non-activating NSPanel + view), MenuContent, SettingsView
project.yml              XcodeGen spec (Vox.xcodeproj is generated and gitignored)
scripts/                 bootstrap.sh, test.sh
web/remote/              Phone web app (PWA), served by the Mac app and the Windows agent
windows/                 Vox for Windows (Node.js agent): grammar port, ConPTY terminals, PowerShell desktop
shared/                  grammar-cases.json: phrases both the Swift and Node grammars must agree on
extensions/vox-bridge/   IDE extension (plain JS) + packaged .vsix; install with scripts/Install-IDE-Bridge.command
docs/ARCHITECTURE.md     Design, state machine, decisions log
```

## Rules

**Where code goes**
- Logic goes in `VoxCore` with tests. The app target only wires UI to `AppState` → `VoxEngine`.
- New app integrations are **adapters** (`TmuxAdapter`, later `IDEAdapter`,
  `AppleScriptAdapter`, `AccessibilityAdapter`). The router emits actions; the
  engine picks the adapter. The router must stay pure (no I/O).
- Never edit `Vox.xcodeproj` by hand. Edit `project.yml` and run `xcodegen generate`.
- **After adding or removing any file under `Vox/`, the project must be regenerated** before ⌘R works.
  Tell the owner to run `scripts/Verify.command` (it regenerates, tests and builds), not just ⌘R.
  The owner usually just presses ⌘R, so **prefer adding new app types to an existing file under `Vox/`**
  over creating a new one. (VoxCore files are fine: SwiftPM picks them up automatically.)
- Swift 5 language mode (see ARCHITECTURE decision D4). Don't switch to Swift 6
  strict concurrency as a drive-by change.

**Security invariants: never break these**
1. Spoken or LLM-produced text is **never** put into a shell command string.
   It reaches tools only as literal keystrokes (`send-keys -l`) or structured API messages.
2. Vox itself only ever *executes* commands from the user's config (`tools[].command`, in tmux) and fixed system
   tools (pmset). Text for the front app or an IDE terminal is *typed*, where the owner can see it, and
   anything matching `confirmPatterns` needs a "yes" first.
3. Anything matching `confirmPatterns`, and every kill, requires a spoken/clicked "yes".
4. Unknown project or tool → refuse and say so. Never guess.
5. Listening is push-to-talk (⌥Space) or the wake word ("Balcha", owner's explicit request 2026-09-23,
   toggle in the menu). The wake listener must stay on-device when supported, never record audio to
   disk, and never bypass confirmations: a wake-word command goes through the same router and safety policy as typed text.
6. Any local server binds `127.0.0.1` and checks a shared secret. **Exception (owner's decision 2026-09-24):**
   the phone remote (Phase 8) may bind all interfaces only when the owner turns on "Allow on home Wi-Fi";
   it is off by default, every `/api/*` call needs the pairing code (constant-time compare, lockout after
   repeated failures), and phone commands go through the same router and safety policy as voice.
   The pairing code never goes in a URL query string (only the `#pair=` fragment, which browsers don't send).
7. The Windows agent (Phase 9) follows the same rules: tools start only from config `tools[].command`;
   spoken text reaches PowerShell only through environment variables or stdin, never inside the script text.

**Two grammars (Mac Swift, Windows JS)**
- A grammar change on one side needs the same change on the other, plus a case in `shared/grammar-cases.json`.
  `node --test windows/test` runs anywhere (including the cloud); the Swift side runs in Verify.command.
- After editing `web/remote/`, run `node scripts/embed-web.mjs` (regenerates the Mac's embedded copy; a test fails if it's stale).

**Tests**
- Every parser/router behaviour change gets a test. Misheard phrasings from real use become test cases.
- `scripts/test.sh` must pass before you mark anything `[x]`.

**Git**
- Small commits, conventional messages (`feat(router): …`, `fix(tmux): …`, `docs: …`).
- **Do not add `Co-authored-by` trailers** to commits (owner's rule).
- Update ROADMAP.md in the same commit as the work it describes.

## Owner context

- Owner: Matty (Mattathias Abraham), full-stack engineer, Apple Silicon Mac.
- Tools he wants to drive: freebuff, Claude Code, Codex, Gemini CLI, opencode (terminal);
  Antigravity and Kiro (IDEs, both VS Code forks); Safari; Claude desktop app.
- Projects live in `~/Projects`.
