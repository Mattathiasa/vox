# Build Vox for Windows: full parity with the Mac app

You are a coding agent working **on the owner's Windows 11 PC** in the Vox repo
(`https://github.com/Mattathiasa/vox`). Your job: turn `windows/` from a Node agent + browser page into a
**complete Windows desktop app** that does everything the macOS app does. You can run real Windows
here (ConPTY, PowerShell, the tray, the mic), so **verify every step on this machine**. Don't just write code.

---

## 0. Read first (in this order, before writing any code)

1. `AGENTS.md`: rules, security invariants, the **two-grammars rule**, git rules. They all apply to you.
2. `ROADMAP.md`: "Current state", Phase 8 (phone), **Phase 9 (Windows)**, and the newest Log entries.
3. `docs/ARCHITECTURE.md`: the router/engine design, the **Remote protocol** table, decisions D1–D18.
4. `windows/README.md`, then all of `windows/src/*.js` and `windows/test/*.js`.
5. The Mac app you are matching: `Vox/UI/CommandPanel.swift` (HUD), `Vox/UI/MenuContent.swift`
   (menu, Settings, Connect Phone), `Vox/App/AppState.swift`, `Vox/Voice/*`, `Vox/Desktop/DesktopController.swift`,
   and in VoxCore: `Desktop/DesktopCommand.swift`, `IDE/IDEBridge.swift`, `Parsing/IDECommands.swift`,
   `LLM/*`, `Voice/WakeWord.swift`, `Safety/SafetyPolicy.swift`.
6. `web/remote/` (the phone app, which is also today's Windows window) and `extensions/vox-bridge/`.

Then write a short plan into ROADMAP.md as **Phase 11: Windows desktop app** using the milestones below.
Mark items `[~]` when you start, `[x]` only when verified on this PC, `[w]` if written but not verifiable.

## 1. Owner's rules (non-negotiable)

- **Never add `Co-authored-by` trailers** (or any "Claude" attribution) to commits. Conventional messages
  (`feat(windows): …`, `fix(win-voice): …`), small commits, ROADMAP.md updated in the same commit.
- Never claim a check you didn't run. The Log entry for each milestone says **how you verified it**.
- Security invariants from AGENTS.md hold everywhere:
  1. Spoken or LLM text is **never** put in a command string. It reaches terminals only as keystrokes (PTY writes),
     and reaches PowerShell only through environment variables or stdin.
  2. Only `tools[].command` from the user's config gets *executed*. Everything else is typed.
  3. Confirm patterns (push, rm, delete, deploy, force, reset --hard…) and **every kill** need a "yes".
  4. Unknown tool/project → refuse and say so. Never guess.
  5. Local servers bind `127.0.0.1` and check a secret (constant-time). LAN only when the owner opts in.
  6. Audio is never written to disk. The wake word runs **on-device**.
- **Two grammars:** any parser/router change here needs the same change in Swift (`Packages/VoxCore`) plus a case
  in `shared/grammar-cases.json`. You can't run Swift on Windows, so write the Swift change carefully and let
  CI (`.github/workflows/ci.yml`, macos-26) verify it. Say so in the Log.
- `web/remote/` is shared with the Mac (embedded into the app). After editing it run
  `node scripts/embed-web.mjs` (a test fails if the embedded copy is stale).
- Don't break the phone app or the Remote protocol: the Mac and the phone must keep working unchanged.

## 2. Architecture decisions (already made, don't relitigate without evidence)

| Area | Decision | Why |
|---|---|---|
| Shell | **Electron** app in `windows/desktop/` (tray, global hotkey, frameless always-on-top HUD, settings window, notifications, launch at login, installer) | Fastest path to a native-feeling Windows app while reusing all the tested JS |
| Engine | Keep `windows/src` (grammar, router, safety, engine, ConPTY terminals, PowerShell desktop) as the core. Run it as a **child process on the bundled `node.exe`**, not inside Electron | node-pty stays on the Node ABI (no electron-rebuild pain), and the agent can crash/restart without taking the UI down |
| UI ↔ engine | The existing Remote protocol over `http://127.0.0.1:<port>` with the pairing token, **plus** a new localhost WebSocket for raw terminal streams | One protocol for the HUD, the phone and tests |
| Terminals in the HUD | **xterm.js** (`@xterm/xterm` + fit addon) attached to the raw PTY byte stream | Real terminal: colours, cursor, TUI apps like Claude Code render properly; typing goes straight in |
| Voice | **On-device**: mic captured in the renderer (`getUserMedia` + AudioWorklet → 16 kHz mono PCM) → engine → **sherpa-onnx** (keyword spotting for "Balcha" + streaming ASR). No Web Speech API in Electron | Matches the Mac's on-device privacy. Electron's `webkitSpeechRecognition` is expected not to work (no Google key). **Verify that in the spike** |
| Spoken replies | `speechSynthesis` in the renderer (Windows SAPI voices), same "what to say" policy as the Mac/web `speak()` | Offline, no dependency |
| LLM fallback | Port VoxCore `LLM/*`: Claude API (key stored with Electron `safeStorage`), optional local Ollama if running. Output must map to a known intent via the same validation. Never executed as a shell | Parity with the Mac's Apple on-device / Claude options |
| IDE terminals | Make `extensions/vox-bridge` cross-platform (bridge file dir: `%APPDATA%\Vox\bridges` on Windows) and port `IDEBridge.swift` to JS | "Open Antigravity with 3 terminals running claude, freebuff and npm run dev" must work on Windows |
| Packaging | `electron-builder` → NSIS installer **Vox-Setup.exe** (per-user, no admin) + keep **Vox-Windows.zip** (portable). Unsigned (SmartScreen: More info → Run anyway) | The owner has no code-signing cert. Don't rename existing release assets the landing page links to |

If a spike proves a decision wrong (e.g. sherpa-onnx has no working Windows prebuilt), pick the documented
fallback, record the evidence in `docs/ARCHITECTURE.md` as a new decision (D19+), and continue.

## 3. Milestones (do them in order; each ends with a verification gate)

### W0: Baseline on real Windows (before any new feature)
- `cd windows && npm ci && npm test`: all green.
- Run `Install-Vox.cmd` from a clean checkout. Then check: "run claude" starts Claude Code in `D:\Projects`
  (or `%USERPROFILE%\Projects`), "open steam", "set volume to 30", "what's 12 times 8", "type hello and press enter" in Notepad.
- Tick the unverified Phase 9 boxes in ROADMAP.md that you actually verified. Fix what's broken first.
- **Spikes (throwaway, report results in the Log):**
  (a) Electron + `webkitSpeechRecognition`: does it work? (expected: no)
  (b) `sherpa-onnx-node` (or its WASM build) on this PC: keyword-spot "balcha" from mic PCM, and transcribe a sentence;
      measure latency and CPU. Candidate models: a small English streaming zipformer + the KWS model; document which.
      Fallbacks, in order: Vosk (`vosk-koffi`), then `Windows.Media.SpeechRecognition` via a tiny helper.
  (c) Electron `backgroundMaterial: "acrylic"` / Mica on this Windows build.

### W1: Desktop shell
- `windows/desktop/` Electron app: `main.js` spawns the engine (`node.exe src/main.js --no-window` with an env var
  telling it to print its port/token on stdout, or reading `%APPDATA%\Vox\remote-token`), restarts it if it dies,
  kills its terminals on quit (the engine already handles signals).
- **Single instance** lock; **tray icon** (idle / listening / busy / needs-OK states) with menu:
  Show Vox · Connect Phone… · Listen for "Balcha" (toggle) · Settings… · Open config · Reload config · Quit.
- **Launch at login** (`app.setLoginItemSettings`), toggle in Settings + tray.
- Replace the Edge `--app` window from `main.js`/`Start-Vox.cmd` with the Electron app. Keep `--no-window` for headless.

### W2: The HUD (parity with `CommandPanel.swift`)
- Frameless, always-on-top, rounded, Acrylic/Mica glass window. Show it with the hotkey or the tray.
  Hide on Esc or focus loss (unless a terminal is pinned). Remember size/position; maximize toggle.
- Contents, matching the Mac HUD: status header (Ready / Needs attention), wake-word pill, orb (idle, listening
  with mic level, busy, needs-OK, linked), command field, **confirm bar** (Yes / No, also answerable by voice),
  reply banner, history strip (🎙 / ⌨ / 📱 badges), activity log, and a **terminal grid** (1–4 tiles, resizable,
  focus one full-size).
- **Terminal tiles = xterm.js** on a new endpoint: `GET /api/tools/<tool>/stream` upgraded to WebSocket
  (localhost only; first message must be `{ "token": … }`, never in the URL). Server sends raw PTY output
  (initial screen snapshot first). Client keystrokes go back as `{ "type": "input", "data": … }` through the **same**
  path as `/type` (literal keystrokes, never a command). Resize → `{ "type": "resize", cols, rows }` → `engine.fit`.
  Clicking a tile focuses it and typing goes straight in, like a normal terminal (Ctrl+C / Ctrl+V handled sensibly:
  copy when there's a selection, otherwise send ^C).
- Accent colour setting (same themes as the Mac's `HUDTheme`), light/dark following Windows.
- Add the WebSocket route to the Remote protocol table in `docs/ARCHITECTURE.md`. Tests: auth required,
  bad token closes the socket, input reaches the PTY, output arrives, resize applies.

### W3: Hotkey and push-to-talk
- Global hotkey (default **Alt+Space**, configurable; if registration fails (PowerToys Run uses it) fall back to
  **Ctrl+Alt+Space** and tell the user). **Tap** = show the HUD for typing. **Hold** = talk; release = send
  (needs key-up: use `uiohook-napi`, or if that's unreliable, tap-to-talk that ends on silence via VAD).
- Voice pipeline: renderer captures the mic → engine ASR (sherpa-onnx) → partial transcript shown live in the HUD →
  final text → `perform(text, spoken: true)` → spoken replies. Mic permission handled with a clear message.
- Tests: the audio-frame → transcript plumbing with a recorded fixture WAV (committed, a few seconds, your own voice,
  or generated with SAPI TTS), the hold/tap state machine (pure function, unit-tested).

### W4: Always-on wake word "Balcha"
- Port `WakeWordTracker`/`WakeWordDetector` timing rules from `Voice/WakeWord.swift` (silence timeout, command
  timeout, "Balcha" then pause then command, and "Balcha <command>" in one breath). Use config `wakeWord.phrases`
  (mishearings) for both the KWS keywords and text matching. `web/remote/wake.js` has JS versions of the matching
  helpers. Reuse them, don't fork them.
- On-device only, low CPU when idle (report % CPU idle and while listening in the Log), never records to disk,
  pauses while Vox is speaking, respects the tray toggle, and survives sleep/resume and mic unplug/replug.
- A wake-word command goes through the same router and safety policy (a bare "yes"/"no" answers a pending question).

### W5: Desktop parity (every `DesktopCommand` case)
Make `windows/src/desktop-win.js` + `engine.js` handle **all** of these on Windows, each verified by hand on this PC
and covered by a test with a fake desktop:
- apps: open, focus, **quit**, **hide (minimize)**, "what apps are open", open folder, open project in an IDE
- web: open URL, search, site search (YouTube, GitHub, Amazon, Wikipedia, Maps, Images, Reddit, Stack Overflow)
- keys & typing: type text, key combos (map "command" → Ctrl sensibly; Windows key), common shortcuts
- media keys, volume up/down/mute/unmute/**set N**
- answers: time, date, battery, clipboard, math
- timers, **reminders** (Windows toast at the time; survive an app restart), cancel timers
- **notes**: "create a note called groceries" → a `.md` in `Documents\Vox Notes`, opened in the default editor
- system: dark mode on/off/toggle (registry `AppsUseLightTheme` + `SystemUsesLightTheme`), screen off, lock
- send a message to an app (clipboard paste + Enter, restoring the clipboard: already written, verify it)
- Safari-only commands: reply clearly that they're Mac-only (keep that)
- Games: "open <game>" via the Start-menu/Steam catalog (`apps-win.js`); verify with a real Steam game shortcut.

### W6: IDE terminals (Antigravity, Kiro, VS Code, Cursor)
- `extensions/vox-bridge/extension.js`: write the bridge file to `%APPDATA%\Vox\bridges\` on Windows (keep the
  macOS path on Mac), owner-only file permissions (on Windows: inside the user profile is enough; document it).
- Port `IDE/IDEBridge.swift` + the engine side to JS: find the bridge file, open N terminals side by side, run a
  **configured tool** in terminal N, send typed text to terminal N, list/focus/close. Same safety rules.
- `windows/Install-IDE-Bridge.cmd`: installs the `.vsix` into each IDE found (`code`, `antigravity`, `kiro`,
  `cursor` CLIs).
- Verify: "open antigravity with 3 terminals running claude, freebuff and npm run dev" on this PC.

### W7: LLM fallback
- Port `LLMAdapter`/`LLMTypes`: when the rules miss, ask the LLM for a structured intent, **validate it against the
  same allowed actions**, and run it through router + safety. Providers: Claude (API key via `safeStorage`) and
  Ollama (if `http://127.0.0.1:11434` answers). Off by default; toggle + provider in Settings.
- Tests with a fake LLM, including hostile outputs (shell strings, unknown tools): they must be refused.

### W8: Settings + phone
- Settings window (tabs like the Mac): General (hotkey, wake word, launch at login, accent, spoken replies),
  Tools, Projects, Apps, **Phone** (same as the Mac's new Connect Phone window: enable, allow home Wi-Fi,
  QR code, live reachability checks, Tailscale status and a "Turn on HTTPS link" button that runs
  `tailscale serve --bg <port>` with fixed args, Windows Firewall hint), LLM.
- Edits write `%APPDATA%\Vox\config.json` through `config.js` validation and hot-reload the engine.
- "Connect Phone…" in the tray opens the Phone tab directly.

### W9: Packaging, release, website
- `electron-builder` NSIS per-user installer **Vox-Setup.exe** (Start menu + desktop shortcut, uninstaller, launch at
  login option) that bundles the engine + `node.exe` + prebuilt node-pty + speech models (or downloads models on first
  run from a pinned URL with SHA-256 check: say which, and why, given the size).
- Update `.github/workflows/release.yml` (windows job) to build and upload **both** `Vox-Setup.exe` and
  `Vox-Windows.zip`, with SHA-256s in the notes. Update `site/src/data.js` + the Download section + README +
  `windows/README.md` + CHANGELOG. CI must stay green on macOS, Windows and Linux.
- Smoke test the installer on this PC: fresh install, first run, uninstall leaves no running processes.

### W10: Final verification (the "done" bar)
All of these on this PC, recorded in the Log with what you did:
- [ ] Install from `Vox-Setup.exe`; Vox starts at login; tray icon shows state.
- [ ] Alt+Space (or fallback) opens the HUD; hold-to-talk "run claude in <project> and add tests" starts Claude Code
      in the right folder, the prompt is typed in, and the tile shows it live with colours.
- [ ] Click a tile and type into it like a normal terminal (arrows, Tab, Ctrl+C, paste).
- [ ] "Balcha, open steam" from across the room with the HUD hidden; "Balcha, kill claude" → asks → "yes" kills it.
- [ ] Every W5 command works by voice.
- [ ] IDE command with 3 terminals works in Antigravity or VS Code.
- [ ] Phone (Tailscale HTTPS) shows the same terminals, types into them, and its "Balcha" hands-free mode works.
- [ ] `npm test` (engine + desktop), the parity tests, and CI on all three OSes are green.
- [ ] Idle CPU with the wake word on is reported, and it's reasonable (target: under ~3% on this PC).

## 4. How to work

- Before each milestone: re-read the relevant Mac code so behaviour and wording match (replies, confirmations,
  what is spoken aloud). Same user, same words, same safety.
- Logic goes in `windows/src` (plain ESM, `node --test`). The Electron layer stays thin (windows, tray, hotkey,
  IPC). Pure state machines (hotkey tap/hold, wake-word timing, HUD visibility) get unit tests.
- Add a Playwright `_electron` smoke test (`windows/desktop/test/`) that launches the app with a demo config, opens the
  HUD, runs a command, and types into an xterm tile. Keep `node src/main.js --demo` working on Linux for the cloud.
- Keep dependencies few and well known. Pin versions. No telemetry.
- When blocked by something only the owner can do (Tailscale sign-in, a Windows permission prompt, a real game),
  finish everything else, then list exactly what he needs to click.
- End of each milestone: update ROADMAP.md "Current state" + Log, commit, push to `main`, check CI.

Start with W0 now.
