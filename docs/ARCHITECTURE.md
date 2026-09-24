# Vox architecture

## Pipeline

```
 push-to-talk ─► speech-to-text ─► SessionRouter ─► VoxEngine ─► adapters
 (Phase 3)        (Phase 3)        pure state      actor, does    TmuxAdapter      (Phase 1)
 typed text ──────────────────────► machine         the I/O       IDEAdapter       (Phase 4)
 (today)                                                          AppleScript/AX   (Phase 5)
                                  unknown ─► LLM fallback (Phase 6)
```

- **SessionRouter** decides. Text in, `[RouterAction]` out. No I/O, so every rule is unit-tested.
- **VoxEngine** does. It runs actions through adapters and tells the router to
  unlock when reality disagrees (a session died, tmux failed).
- **AppState** (app target) is the only thing the UI talks to.

## Router state machine

```
            "run freebuff" / "switch to claude" / "claude"
   ┌──────┐ ───────────────────────────────────────────► ┌──────────────────┐
   │ idle │                                               │ locked(freebuff) │──► text goes to
   └──────┘ ◄─────────────────────────────────────────── └──────────────────┘    freebuff as-is
       ▲        "exit" / "done" (WHOLE utterance only)          │
       │        engine: session died / launch failed            │ "vox switch to claude"
       │                                                         ▼
       │                                                 locked(claude)
       │
   any state ── destructive text or kill ──► pending confirmation
                "yes"/"do it" ──► actions released     anything else ──► "Cancelled."
```

Pass-through rules:
- In `locked`, text is **not** parsed as a command. "switch to the new API client"
  goes to the tool. Commands need the prefix: `vox …`, `hey vox …`, `computer …`.
- Exit phrases only count when they are the entire utterance, so
  "exit early if the list is empty" is still text for the tool.
- A pending confirmation swallows the next utterance whatever it is. "No, instead
  do X" cancels, and X is dropped. That's deliberate: say it again.

## Command grammar (idle, or after a prefix)

```
[prefix] [fillers] <launch-verb> [the] <tool> [<in|on|for> [the] <project> [project|repo|folder]] [<connector>] [prompt…]
[prefix] [fillers] <focus-verb> [the] <tool>
[prefix] [fillers] <kill-verb> [the] <tool>
[prefix] [fillers] <tool>                         # bare name = focus
list | sessions | status | what's running

[prefix] <open|launch|start|fire up|bring up> [the] <app name> [app] [and <desktop clause>]   # any Mac app
[prefix] <desktop clause>
<desktop clause>:
  create a note [called|titled|saying|…] <text>        -> Notes (AppleScript)
  search for | google | look up <query>                 -> Google in default browser
  go to | visit <web address>  ("github dot com")       -> default browser
  type <text> [and press <keys>]                        -> frontmost app (CGEvent, needs Accessibility)
  press | hit <keys>   ("command shift t", "enter")     -> frontmost app
  <named shortcut>     close tab/window, new tab, copy, paste, undo, save, scroll down, go back, reload,
                       full screen, minimize, zoom in, take a screenshot …  (KeyCombo.named, whole clause only)
  volume up/down, mute, unmute, set volume to <0-100>   -> AppleScript
  hide <app>                                            -> NSRunningApplication.hide

[prefix] <kill-verb> [the] <app> [app]     -> quit a Mac app (a tool name kills its tmux session instead)
[prefix] <focus-verb> [the] <app> [app]    -> bring a Mac app forward (a tool name locks onto the tool)
never mind | cancel | forget it            -> nothing ("OK.")
help | what can you do                     -> list of commands
```

- launch verbs: run, start, open, launch, fire up, spin up, boot up, start up
- focus verbs: switch to, go to, talk to, use, attach to, focus (on), back to
- kill verbs: kill, close, quit, stop, end, shut down, terminate
- connectors: and, then, and then, to, with, (and) tell it to, (and) ask it to, and have it, and say
- Tool and project phrases come from config names + aliases; the longest match wins.
- The prompt is cut from the **original** text (casing and symbols kept), not the normalized tokens.

Desktop commands:
- A tool name wins over an app with the same name ("open claude" = Claude Code in tmux);
  add "app" to mean the Mac app ("open the claude app"). "run" only ever launches tools.
- Desktop commands never change the router mode. While talking to a tool they need the prefix: "vox open safari".
- An unrecognized follow-up clause ("open safari and do a dance") is reported back, never guessed.
- Typed text that matches `confirmPatterns` needs a "yes" first.
- Named shortcuts only fire as a whole clause ("copy", "save and close tab"), never inside a longer sentence.

Spoken feedback (`speakFeedback`, default on): for voice commands only, Vox speaks confirmation
questions, warnings, errors and short info; successes are silent (Pop sound). The wake listener is
muted while Vox speaks and restarts with a fresh transcript afterwards, so Vox never hears itself.

## tmux usage

- Dedicated server: every call is `tmux -L vox …`. Vox never sees or touches your own sessions.
- Session name `vox-<tool>`; pane target `vox-<tool>:`; session target `=vox-<tool>` (exact match).
- Start: `new-session -d -s vox-x -x 200 -y 50 [-c dir] /bin/zsh -lc "<config command>" ; set-option -w -t vox-x: remain-on-exit on`
- Type: `send-keys -t vox-x: -l "<text>"`, wait `submitDelaySeconds` (0.15 s), then `send-keys -t vox-x: Enter`.
- Dead pane (`#{pane_dead}` = 1) → sending is refused and the router unlocks. Relaunch kills the dead session first.

## Why freebuff needs tmux

freebuff's CLI is interactive-only: no `--print`/headless flag, no prompt argument,
and piping stdin hangs because it wants a TTY (CodebuffAI/freebuff issue #947,
checked 2026-09-23). tmux gives it a real TTY that Vox can type into and read from.
If freebuff ever ships a headless mode, a `HeadlessCLIAdapter` would be simpler for one-shot prompts.

## IDE chat command IDs (Phase 4)

The Vox Bridge extension dispatches chat commands based on `vscode.env.appName`.
All send a spoken prompt to the IDE's AI chat input and submit it.

| IDE | Command | Parameters | Auto-submit | Source |
|---|---|---|---|---|
| VS Code | `workbench.action.chat.open` | `{ query: string }` | No (pre-fills only) | [VS Code source](https://github.com/microsoft/vscode/blob/234229df/src/vs/workbench/contrib/chat/browser/actions/chatActions.ts) |
| Antigravity | `antigravity.sendTextToChat` | `(showInChat: boolean, query: string)` | No (pushes text to chatbox) | [Google AI Developers Forum](https://discuss.ai.google.dev/t/antigravity-built-in-command-for-sending-a-query-via-a-chat-to-the-model/120211/) |
| Kiro | `kiro.chat.sendMessage` | `{ message: string, options?: { focus?, submit?, append? } }` | Yes (with `options.submit: true`) | [Kiro GitHub issue #7504](https://github.com/kirodotdev/Kiro/issues/7504), [kiro.dev](https://kiro.dev/docs/ide/chat/) |

After pre-filling the chatbox, Vox sends `workbench.action.chat.submit` (VS Code / Antigravity)
to trigger the response. Kiro's `kiro.chat.sendMessage` with `submit: true` handles both
in one call.

## IDE bridge actions (Phase 4)

The extension (`extensions/vox-bridge/extension.js`) supports these actions over
localhost HTTP with a per-window 0600 token file:

| VoxCore `IDECommand` | Extension action | VS Code API | Notes |
|---|---|---|---|
| `.openTerminals` | `openTerminals` | `vscode.window.createTerminal` | Splits side by side; `parentTerminal` for nested splits |
| `.send` | `send` | `terminal.sendText` | 1-based or "any" target |
| `.closeTerminals` | `closeTerminals` | `terminal.dispose()` | Disposes all Vox-created terminals |
| `.chat` | `chat` | IDE-specific (see table above) | Sends spoken prompt to AI chat |
| `.openFile` | `openFile` | `vscode.window.showTextDocument` | Path resolved relative to workspace |
| `.openFolder` | `openFolder` | `vscode.openFolder` | Opens in current/new window |
| `.runTask` | `runTask` | `vscode.tasks.fetchTasks` + `executeTask` | Matches task by name (case-insensitive) |

All chat and terminal text is treated like typed text: `confirmPatterns` require a "yes",
and the prompt is sent as structured data (not a shell command string) per
security invariant D9/D15.

## Remote protocol (Phase 8 phone remote, Phase 9 Windows)

One web app (`web/remote/`, plain HTML/CSS/JS, no build) talks to any Vox agent over HTTP. The Mac app
serves it from `VoxCore/Remote` (assets embedded by `scripts/embed-web.mjs`); the Windows agent serves it
from `windows/src/server.js`. Default port **7788**. The page polls; there are no push events.

| Method + path | Auth | Body | Returns |
|---|---|---|---|
| `GET /`, `/app.js`, `/style.css`, `/manifest.webmanifest`, `/icon.svg` | no | | web app files |
| `GET /api/ping` | no | | `{name, platform, version}` |
| `GET /api/state?lines=60` | yes | | `RemoteState`: `host, platform, version, lockedTool, pendingQuestion, busy, wake{enabled,name}, tools[], screens[{tool,text,exited}], history[{command,kind,reply,spoken,source}], log[{kind,text,time}]` |
| `POST /api/command` | yes | `{text, spoken?, source?}` | `{events:[{kind,message}]}` (same router + safety as voice) |
| `POST /api/confirm` | yes | `{yes}` | answers the pending question only ("Nothing to confirm." otherwise) |
| `POST /api/exit` | yes | | leave pass-through |
| `POST /api/tools/<tool>/launch\|kill\|focus` | yes | | as "vox run/kill/switch to <tool>" (kill asks) |
| `POST /api/tools/<tool>/send` | yes | `{text}` | text + Enter (confirm patterns apply) |
| `POST /api/tools/<tool>/type` | yes | `{text}` | literal keystrokes, no Enter (live typing) |
| `POST /api/tools/<tool>/key` | yes | `{key}` | one of `TmuxAdapter.allowedKeys` / `KEY_SEQUENCES` |
| `GET /api/pairing` | yes | | Windows only: `{urls, qrSvg, hint}` |

Auth: `Authorization: Bearer <pairing code>`. The code is 20 characters (~100 bits), stored in the Keychain
(Mac) or `%APPDATA%\Vox\remote-token` (Windows), compared in constant time; 10 failures from one address in
5 minutes → 429 for 60 s. Pairing links carry the code in the URL **fragment** (`#pair=`), which browsers
never send to a server; the page stores it in localStorage. Responses carry a strict CSP, `nosniff`,
`no-referrer`, `frame-ancestors 'none'`; no CORS headers, so other sites can't call the API.

Reachability: the listener binds loopback unless the owner turns on "home Wi-Fi". For the phone, Tailscale
Serve proxies `https://<device>.<tailnet>.ts.net` → `127.0.0.1:7788`, which gives HTTPS (needed for the
browser's microphone on iPhone) and restricts access to the owner's tailnet.

Voice on the phone uses the browser's Web Speech API (Safari: Apple servers or on-device; Chrome: Google).
Spoken replies use `speechSynthesis` on the phone; the Mac stays quiet for phone commands.

## Two grammars, one test list

The Windows agent is Node.js (owner's decision 2026-09-24: testable in the cloud, node-pty for ConPTY), so
the grammar exists twice: Swift (`VoxCore/Parsing`, `Routing`) and JavaScript (`windows/src/parser.js`,
`router.js`, a line-by-line port). `shared/grammar-cases.json` lists utterances (with state across steps)
and the exact router output in a one-line canonical form (`GrammarCanonical.swift` = `canonical.js`).
`GrammarParityTests.swift` and `windows/test/parity.test.js` both run it. Grammar changes: edit both, add a case.

## Decisions

| # | Decision | Why | Revisit if |
|---|---|---|---|
| D1 | Rule-based router first, LLM only for `.unknown` | Predictable, instant, testable. An LLM first adds ~1 s per command and "interprets" text meant for tools | Rules miss >10% of real commands after Phase 3 |
| D2 | tmux instead of scripting Terminal.app | Keystrokes via GUI go to whatever has focus; tmux targets a session directly and works hidden | Never, for CLI tools |
| D3 | Dedicated tmux socket `-L vox` | Isolation from the user's own tmux; server options can be set freely | — |
| D4 | Swift 5 language mode (tools 5.10) | The first version was written without a compiler; strict concurrency would multiply first-build errors | After Phase 3 is stable, migrate deliberately |
| D5 | XcodeGen, generated project gitignored | `.pbxproj` merges are painful, and AI agents can't edit them safely | — |
| D6 | Separate floating `NSPanel` instead of MenuBarExtra `.window` | SwiftUI can't open a MenuBarExtra window from code (the hotkey needs to) | Apple adds an API |
| D7 | Unknown project → refuse | Starting an agent with write access in the wrong repo is worse than asking | — |
| D8 | Exit phrases are whole-utterance only; commands need a prefix while locked | Otherwise prompts containing "switch to"/"exit" hijack the router | — |
| D10 | Desktop control behind a `@MainActor DesktopControlling` protocol, implemented in the app target | VoxCore stays AppKit-free and testable with `FakeDesktop` | — |
| D11 | Voice via `SFSpeechRecognizer` first, on-device when available | Works on macOS 14+, well documented; `SpeechAnalyzer` is macOS 26+ only | Accuracy on the owner's voice is poor → try SpeechAnalyzer / WhisperKit |
| D12 | Non-activating panel | The app you were in stays frontmost, so "type"/"press" go there, and listening doesn't steal focus | — |
| D13 | Wake word via the same SFSpeechRecognizer transcript, matched against configurable spellings | No extra dependency or account; "Balcha" isn't English so mishearings are expected and listed in config | False triggers or misses stay high → Porcupine/custom keyword model |
| D14 | IDE control through a localhost extension, not simulated keystrokes | Keystrokes go wherever focus is; the extension targets terminal N exactly and can split panes | — |
| D15 | Extension in plain JS, HTTP (not WebSocket), token in a 0600 file per window | No build step or npm deps to maintain; request/response is all Vox needs | Need push events from the IDE → WebSocket |
| D16 | Phone remote = web app + polling JSON API, not a native iOS/Android app | One codebase for iPhone, Android and the Windows window; no App Store; Add to Home Screen gives an icon | Need background push or wake word on the phone → native app |
| D17 | Tailscale Serve for remote access, loopback bind by default | Real HTTPS (mic on iPhone) and no open port on the Wi-Fi; nothing to host | Owner can't use Tailscale → self-signed cert + trust profile |
| D18 | Windows agent in Node.js with a ported grammar, guarded by shared test cases | Testable in the cloud; mature ConPTY (node-pty) and VT emulation (@xterm/headless); Swift on Windows lacks both | Drift keeps happening → compile VoxCore's parser to WASM and share it |
| D9 | No sandbox, not on the Mac App Store | Needs tmux, Apple Events to arbitrary apps, and Accessibility | — |

## Adding an adapter (Phase 4+ pattern)

1. Add a tool kind to config (e.g. `"kind": "ide"`) and keep old configs decoding (`decodeIfPresent`, default `"tmux"`).
2. Add `RouterAction` cases only if the existing ones can't express it. Prefer reusing `launch/focus/send/kill`.
3. Implement the adapter in `VoxCore` behind a protocol, with a fake for tests.
4. The engine picks the adapter by the tool's kind.
5. Update the grammar/decisions above and ROADMAP.md.
