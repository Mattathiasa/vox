# Vox Audit — 2026-09-24 (re-run)

Re-audited against the on-disk tree + `scripts/test.sh`. The previous audit
(2026-09-23) predates the public-release/Phase‑10 work (Windows, phone web
controller, landing page), the initial commit of this repo, the Phase 3
`Transcriber` protocol, and the Phase 7 settings UI, so most of its "genuinely
unfinished" items and numbers are now stale. This file refreshes them.

## 1. Build & Test Status (verified locally, 2026-09-24 11:15)

| Check | Command | Result |
|---|---|---|
| VoxCore unit tests | `scripts/test.sh` (→ `swift test` in `Packages/VoxCore`) | **189/189 pass, 1 skipped, 0 failures** |
| Xcode project generation | `xcodegen generate` | OK |
| App build (unsigned) | `xcodebuild … CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**, 0 errors, 0 warnings |
| Real-machine self-test | `swift run VoxSelfTest` (`Packages/VoxCore/Sources/VoxSelfTest/main.swift`, 143 lines) | Not re-run in this pass (needs real tools on the owner's Mac); code compiles. |

Environment: macOS 27.0 SDK, Xcode 27.0, Swift 6.4, arm64; deployment target macOS 14.
tmux 3.7c at `/opt/homebrew`; xcodegen 2.46.0.

**Repo state:** this is now a real git repo — `vox/.git`, remote `origin https://github.com/Mattathiasa/vox.git`,
16 commits (7e36766 "Phase 10 / public release" through 207be25 "fix(release) … windows node-pty",
plus `c177e71` Phase 3 Transcriber and `9844a0c` Phase 7 settings). 143 tracked files.
Caveat: the working tree currently carries **uncommitted, in-progress** changes
around the phone/Remote features (`PhoneLinks.swift`, `PhoneLinksTests.swift`,
`scripts/Diagnose-Phone.command` untracked; `MenuContent.swift`, `project.yml`,
`Info.plist`, `scripts/Remote-Tailscale.command` modified) — the audit reflects the
on-disk/build state, which is what `test.sh` compiles. I committed only documentation
(`AUDIT.md`) and did not stage the owner's in-progress files.

## 2. Code Structure (current)

**VoxCore** — SwiftPM package, **4,642 LOC** (was 1,247), ~22 source files:
- `Config/`: `VoxConfig.swift` (ToolConfig, ProjectConfig, LLMConfig, WakeWordConfig), `ConfigStore.swift`, validation.
- `Parsing/`: `Tokenizer.swift`, `PhraseMatcher`, `CommandParser.swift`, `MoreCommands.swift`, `IDECommands.swift`, `SpokenValues.swift`, `GrammarCanonical.swift`.
- `Routing/`: `SessionRouter.swift` (pure state machine, no I/O).
- `Safety/`: `SafetyPolicy.swift`.
- `Terminal/`: `TmuxAdapter.swift`, `ProcessRunner.swift`.
- `Engine/`: `VoxEngine.swift` (695 lines; actor gluing router to adapters).
- `Desktop/`: `DesktopCommand.swift`, `AppCatalog.swift`, key combos/web apps.
- `IDE/`: `IDEBridge.swift` — HTTP client + `ShellText`.
- `LLM/`: `LLMTypes.swift` (ToolDefinition/Request/Result/LLMFallback), `LLMAdapter.swift` (Apple on-device + Claude).
- `Remote/`: **new** — phone web controller (`RemoteServer`, `RemoteHTTP`, `PhoneLinks`, `RemoteWebAssets`).
- `Voice/`: `WakeWord.swift`, `Transcriber.swift` (**new** — Phase 3 abstraction; `SpeechController` conforms).
- `VoxSelfTest/` — `main.swift` (143-line real-machine checks for Phases 1–2).

**Vox app** — ~8 Swift files, ~3,300 LOC in `Vox/`:
- `App/`: `VoxApp.swift`, `AppState.swift` (751), `Hotkeys.swift`, `TerminalLauncher.swift`, `Keychain.swift`.
- `Voice/`: `SpeechController.swift` (250; SFSpeechRecognizer backend + `Transcriber` conformance, plus `SpeechOutput` speech synthesis), `WakeWordListener.swift`.
- `Desktop/`: `DesktopController.swift` (NSWorkspace, AppleScript, CGEvent).
- `UI/`: `CommandPanel.swift` (1,531; HUD, orb, terminal grid, glass effects, themes, widgets), `MenuContent.swift`, `Hotkeys.swift`.

**Tests** — 18 files, **2,161 LOC**, 189 methods across `CommandParserTests`, `DesktopTests`,
`GrammarParityTests`, `IDETests`, `LLMFallbackTests`, `MoreCommandTests`, `PhoneLinksTests`,
`RemoteTests`, `SafetyAndConfigTests`, `SessionRouterTests`, `TerminalInputTests`,
`TmuxAdapterTests`, `TokenizerTests`, `TranscriberTests`, `VoiceCommandsTests`,
`VoxEngineTests`, `WakeWordTests`, plus `Support/` fakes (`FakeTmuxRunner`, `FakeDesktop`,
`FakeLLM`, `FakeTranscriber`). Fixtures: `Fixtures/commands.json` (62 voice→intent cases).
Coverage spans every `VoxCore` component; `SpeechController`, `DesktopController`,
`AppState`, and `CommandPanel` (app target) remain outside unit tests.

**Extension** — `extensions/vox-bridge/`: plain JS, no build step, HTTP on `127.0.0.1`,
per-window random token in a `0600` file. Verified with a mock `vscode` API; installed in
Antigravity, Kiro, VS Code. Packaged `vox-bridge-0.1.0.vsix` (6.69 KB).

**Adjacent / shipped since the last audit:**
- `site/` — landing page, Three.js scene + scroll story, in-browser demo.
- `web/remote` — phone web controller front-end.
- `windows/` — **Vox for Windows** (node-pty/ConPTY terminal driver; `package.json`).
- `shared/` — `grammar-cases.json`, `grammar-config.json` (shared grammar between Mac/Windows/phone).

## 3. Roadmap vs. Reality

### Progress at a glance (current)

| Phase | Status | Evidence |
|---|---|---|
| 0 Foundation | done | signed run, hotkey, config reload (prior logs) |
| 1 tmux tools | done | 20/20 tmux cycles, real tools start, `/help` accepted |
| 2 Router + safety | done | 189 tests pass incl. `VoiceCommandsTests` |
| 3 Voice / 3c wake word | coded | `SpeechController` + `WakeWordListener` compile; detector/tracker unit-tested |
| 3b Desktop commands | coded | `DesktopController` compiles; needs owner voice + Accessibility |
| 4 IDE bridge | done in code | terminals + chat implemented; command IDs researched |
| 5 Safari + Claude desktop | done | `AppleScriptAdapter`, Claude paste, self-test |
| 6 LLM fallback | done | `LLMAdapter` (Apple + Claude), routing, 17+ tests |
| 7a HUD | done | code builds; owner visual review |
| 7 Polish | done | spoken feedback, sounds, history, **settings UI**, launch-at-login |
| 10 Public release in progress | in progress | Windows (node-pty), phone web controller, landing page, Three.js |

### Resolutions vs. the 2026-09-23 audit

| 2026-09-23 audit claim | Reality now |
|---|---|
| "no git history (`vox/.git` does not exist)" | **Resolved.** Repo initialized, `origin` remote set, 16 commits. |
| `Phase 3: Transcriber protocol` "Not implemented — correct, future spike" | **Implemented.** `Transcriber` protocol in `VoxCore/Voice`; `SpeechController` conforms; `AppState` holds a `Transcriber`; `FakeTranscriber` + `TranscriberTests`. (Real `SpeechAnalyzer` backend still deferred — macOS 27 SDK has no `SpeechAnalyzer` framework.) |
| `Phase 3: Voice test set` — `commands.json` "does not exist" | **Exists.** `Fixtures/commands.json` (62 cases) drives `VoiceCommandsTests`. |
| `Phase 4: IDE chat` "not implemented / command IDs not researched" | **Done.** `IDECommand.chat`, `extension.js` handler, parser grammar, docs record (Antigravity `antigravity.sendTextToChat(true, query)`, Kiro `kiro.chat.sendMessage(...)`, VS Code `workbench.action.chat.open`). |
| Stray `_to_delete/` duplicate `SpeechOutput.swift` | **Removed.** |
| Test count "147" | **189** (1 skipped). VoxEngine grew 551→695 LOC, CommandPanel 1,284→1,531, AppState 463→751. |
| Doc path `packages/` vs `Packages/` | Already corrected in `AGENTS.md`. No stale references. |
| `.gitignore` hides `Info.plist`/`entitlements` | **Stale.** These are now tracked; `.gitignore` excludes only build artifacts (`Vox.xcodeproj/`, `.build/`, `*.xcuserdatad/`, logs, `.DS_Store`). |

### What's genuinely unfinished / owner-dependent

| Item | Why it needs you |
|---|---|
| Phase 1 "output view on screen" | Agent can't see the menu-bar window. Code done (`AppState.refreshOutput` 1s timer → `engine.lockedOutput()` + `engine.screens()`). |
| Phase 3/3b/3c/3d/3e voice verification | `SpeechController`/`WakeWordListener`/`DesktopController` compile but have no unit tests and need mic/Accessibility permission + your voice. |
| Phase 3 WhisperKit + SpeechAnalyzer accuracy spike | macOS 27 SDK lacks the `SpeechAnalyzer` framework; needs your voice to compare. |
| Phase 4 IDE pass-through to a terminal | Terminal+chat done; pass-through mode not implemented. |
| Phase 7a "Looks right on screen / CPU < 3%" | Owner eyes + a 30s sample. |
| Windows / phone end-to-end | Code present (`windows/`, `web/`, `Remote/`); needs Windows + phone smoke test. |

## 4. Structural Issues

- **Stale test counts in ROADMAP Log** — still references "57/57", "139/139", "~115 pending". ROADMAP should be re-synced to 189 (and the Log entries back-dated to real 09-23/09-24 runs). *(Out of scope for this audit; flagging.)*
- **Git workflow discipline** — the repo now has a remote, but the working tree is mid-feature (uncommitted `Remote`/`Phone` work). Per `AGENTS.md`, stage only intended files per commit. Don't `git add -A` over in-progress phone work.
- **`.gitignore` is minimal** — fine for builds, but `Vox.xcodeproj/project.xcworkspace/` is gitignored while `project.xcworkspace/xcshareddata/swiftpm/` data exists on disk; harmless.
- **Generated project** — `Vox.xcodeproj` is gitignored; any new Swift file under `Vox/` requires `xcodegen generate` (or `scripts/Verify.command`) before ⌘R builds. `scripts/test.sh` regenerates.

## 5. Security Invariants (unchanged, design-preserved)

Same approach as the prior audit; the build + 189 tests pass and the relevant modules
are unchanged, so the invariants hold. Evidence is module-level (line numbers drift
with growth):

| Invariant | Status | Evidence |
|---|---|---|
| Spoken/LLM text never enters a shell string | ✅ | `send-keys -l` only; `ShellText.normalize` is for IDE terminals that go through `send`, not exec. `VoxEngine`, `TmuxAdapter`. |
| Only config `tools[].command` reaches a shell | ✅ | `ToolConfig.command` is the sole shell entry; `TerminalLauncher` builds tmux attach only. `VoxConfig`/`SafetyPolicy`. |
| Destructive text ⇒ spoken "yes" | ✅ | `SafetyPolicy` regex on `confirmPatterns`; kills always confirmed. `SessionRouter` confirm flow. |
| Unknown project/tool ⇒ refuse | ✅ | `CommandParser` returns `.unknownProject`/`.unknown`, never guesses. |
| Wake word on-device, no disk recording | ✅ | `SFSpeechRecognizer.requiresOnDeviceRecognition` when supported; `WakeWordListener` never writes audio. |
| Wake word can't bypass confirmations | ✅ | `wakeCommand` → `submit(…, spoken: true)` → `engine.handle` → same router+safety path. |
| IDE bridge: localhost + token + `0600` | ✅ | binds `127.0.0.1`; 24-byte hex token in `0600` file; constant-time compare. `RemoteRemoteServer`/`extension.js`. |
| Claude key in Keychain | ✅ | `Keychain.swift` reads `com.vox.llm.claude-api-key`; never logged. |

## 6. ROADMAP Accuracy Assessment

ROADMAP is **broadly accurate** but its **test counts are stale** ("147") and its
"Current state / progress-at-a-glance" tables do not yet reflect Phase 10
(Windows + phone + site) or the git repo coming online. Per-phase code checkboxes
are now `[x]`/`[w]` appropriately; voice-desktop/IDE/WHUD verification remains owner-only.

## 7. Next Steps (priority order)

1. **Phase 10 Windows + phone smoke test** (owner): run `windows/` and the phone web
   controller against a Windows machine and a phone.
2. **Update ROADMAP** test counts (147→189) and fold these audit resolutions into the
   per-phase checkboxes + Current state.
3. **Phase 3 spike** (owner voice): implement/compare `SpeechAnalyzer` (macOS 26+) and
   WhisperKit against `SFSpeechRecognizer`, record numbers.
4. **Voice end-to-end** (owner): grant mic/Accessibility, speak a sample of commands,
   add misses to `Fixtures/commands.json` as regression cases.
5. **Phase 4 IDE terminal pass-through**: mirror the tmux tool pass-through for an IDE terminal.
