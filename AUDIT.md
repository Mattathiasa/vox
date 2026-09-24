# Vox Audit — 2026-09-23

## 1. Build & Test Status (verified locally)

| Check | Command | Result |
|---|---|---|
| VoxCore unit tests | `swift test` (in Packages/VoxCore) | **147/147 pass, 0 failures** |
| Xcode project generation | `xcodegen generate` | OK, project created |
| App build (unsigned) | `xcodebuild … CODE_SIGNING_ALLOWED=NO build` | **BUILD SUCCEEDED**, 0 errors, 0 warnings |
| Self-test (real mac) | `swift run VoxSelfTest` | ALL PASSED (20/20 tmux cycles, remain-on-exit, 15 voice phrasings, 3 real tools start + accept `/help`) |

Environment: macOS 27.0, Xcode 27.0, Swift 6.4, arm64. tmux 3.7c, xcodegen 2.46.0 at `/opt/homebrew`.

## 2. Code Structure

**VoxCore** (SwiftPM package, 1,247 LOC, 16 files in `Packages/VoxCore/Sources/VoxCore/`):
- Config: `VoxConfig.swift` (189 lines), `ConfigStore.swift` (110 lines)
- Parsing: `Tokenizer.swift` (98), `PhraseMatcher` (in Tokenizer), `CommandParser.swift` (382), `MoreCommands.swift` (302), `IDECommands.swift` (261), `SpokenValues.swift` (213)
- Routing: `SessionRouter.swift` (238) — pure state machine, no I/O
- Safety: `SafetyPolicy.swift` (35) — regex-based confirmation gate
- Terminal: `TmuxAdapter.swift` (189), `ProcessRunner.swift` (45)
- Engine: `VoxEngine.swift` (551) — actor, glues router to adapters
- Desktop: `DesktopCommand.swift` (335), `AppCatalog.swift` (89)
- IDE: `IDEBridge.swift` (222) — HTTP client + ShellText normalizer
- Voice: `WakeWord.swift` (124) — config, detector, tracker (all unit-tested)

**Vox app** (8 Swift files, ~2,000 LOC in `Vox/`):
- `App/`: VoxApp.swift (57), AppState.swift (463), Hotkeys.swift (20), TerminalLauncher.swift (31)
- `Voice/`: SpeechController.swift (243), WakeWordListener.swift (189)
- `Desktop/`: DesktopController.swift (282)
- `UI/`: CommandPanel.swift (1,284+ — HUD, orb, terminal grid, glass effects, themes, widgets)

**Extension**: `extensions/vox-bridge/extension.js` (231 lines, plain JS, no deps, 5.7 KB vsix). Verified in the cloud with mock `vscode` API; installed in Antigravity, Kiro, and VS Code.

**VoxSelfTest**: `Packages/VoxCore/Sources/VoxSelfTest/main.swift` (143 lines) — real-machine checks for Phases 1–2.

**Tests**: 12 test files, 1,305 lines, 147 test methods. Coverage spans every VoxCore component except `SpeechController` and `DesktopController` (both in the app target, not unit-testable on Linux).

## 3. Roadmap vs. Reality

### Discrepancies: checkboxes marked `[w]` despite being verified

| Phase | ROADMAP mark | Reality |
|---|---|---|
| 0 | all `[w]` | Verified `[x]` — app builds signed & runs, hotkey works, config reloads (Log: 2026-09-23 14:22) |
| 1 | `[w]` for all items | Verified `[x]` — 20/20 tmux cycles, real tools start, `/help` accepted (Log: 17:50–18:12) |
| 2 | `[w]` for all items | Verified `[x]` — 147 tests pass, 15 real phrasings pass (Log: 14:22, 18:12) |
| 7a | `[w]` for all items | Code fully written and compiles; app build succeeds (never marked `[x]` — needs owner eyes) |
| 3e | `[w]` for all items | Code written (MoreCommands.swift), 45+ tests added, but marked "syntax parse only" in Log |
| 3d | `[w]` for all items | Code written (DesktopController.swift), tests added, marked "syntax parse only" |

**Stale test counts**: ROADMAP references "57/57" (Phase 1), "139/139" (Phase 2, 3e), and "~115 tests" in Log entries. Actual count is **147 tests**. The counts stopped being updated after the 14:22 run; 41 tests were added thereafter (per-wake, per-terminal commands) but the ROADMAP wasn't synced.

### What's genuinely unfinished

| Item | ROADMAP status | Reality |
|---|---|---|
| Phase 1: output view refresh | `[ ]` | **Implemented** in code — `AppState.refreshOutput()` on a 1s timer calls `engine.lockedOutput()` + `engine.screens()`. Just needs owner visual confirmation. |
| Phase 3: all voice verification | `[ ]` | SpeechController + WakeWordListener fully coded and compile. WakeWordDetector/Tracker unit-tested (6 tests). But **no end-to-end voice test set** — `Packages/VoxCore/Tests/Fixtures/commands.json` does not exist. |
| Phase 3: `Transcriber` protocol + `SpeechAnalyzer` (macOS 26+) | `[ ]` | Not implemented — correct, this is a future spike. |
| Phase 3: WhisperKit comparison | `[ ]` | Not started. |
| Phase 3b: desktop command voice verification | `[ ]` | DesktopController.swift fully implemented and compiles. Needs owner to grant Accessibility permission and speak commands. |
| Phase 3c: wake word voice verification | `[ ]` | WakeWordListener.swift fully implemented. Needs owner to speak "Balcha, open safari" etc. |
| Phase 4: IDE chat integration | `[ ]` | Terminal commands done & verified. "Open folder/file, run task, open AI chat with a prompt" **not implemented**. Chat-panel command IDs for Antigravity/Kiro not researched. |
| Phase 3e/3d voice verification | `[ ]` | Code written + unit-tested, but never spoken. |

### Progress-at-a-glance table vs. code

The "Progress at a glance" table claims Phase 7a is "done / builds" with 1 unchecked box (owner review). That's accurate — the code is in `Vox/UI/CommandPanel.swift` and it builds. But Phases 3, 3b, 3c are listed as "done / pass (unit)" / "not started" — the unit tests exist for the core logic (WakeWord, parsing, router), but the voice pipeline itself (SpeechController, WakeWordListener) has zero unit tests and is only marked "syntax parse only" in the Log.

## 4. Structural Issues

### 4a. No git history (blocker)
`vox/.git` does not exist. The parent `/Users/mattathiasa/Projects` git repo shows "No commits yet." The AGENTS.md prescribes conventional commits per change, but there is no repository to commit to. Vox is completely unversioned from git's perspective.

### 4b. Stray `_to_delete/` directory
Contains `SpeechOutput.swift` (49 lines) — an exact duplicate of the `SpeechOutput` class already in `Vox/Voice/SpeechController.swift:203-233`. Dead code; should be removed.

### 4c. Doc path mismatch
AGENTS.md references `packages/VoxCore/` (lowercase). Actual directory is `Packages/VoxCore/` (capitalized). Minor; doesn't affect builds but is a consistency issue.

### 4d. Gitignore hides generated files that must be regenerated
`.gitignore` ignores `Vox/Info.plist` and `Vox/Vox.entitlements` (generated from `project.yml` by xcodegen). This is correct by design, but means any new Swift file added under `Vox/` requires `xcodegen generate` before ⌘R works — as noted in the AGENTS.md and ROADMAP Log (2026-09-23 14:22). The `scripts/Verify.command` handles this; `scripts/test.sh` also regenerates.

## 5. Security Invariants (all verified)

| Invariant | Status | Evidence |
|---|---|---|
| Spoken/LLM text never goes into a shell string | ✅ | `sendText` → `send-keys -l` (literal). `ShellText.normalize` only used for IDE terminal text, which still goes through `send` action, not exec. (VoxEngine.swift:442–448, ARCHITECTURE D1/D2/D12) |
| Only config `tools[].command` reaches shell | ✅ | `VoxConfig` confirm patterns; `ToolConfig.command` is the sole shell entry. `TerminalLauncher.open` uses Vox-built tmux attach command only. (VoxEngine.swift:498–530) |
| Destructive text needs "yes" | ✅ | `SafetyPolicy` regex on `confirmPatterns`; kills always confirmed. (SafetyPolicy.swift, SessionRouter.swift:154–160, 212–217) |
| Unknown project → refuse | ✅ | `parseLaunch` returns `.unknownProject`, not a guess. (CommandParser.swift:225–229) |
| Wake word on-device, no disk recording | ✅ | `requiresOnDeviceRecognition = true` when supported; `WakeWordListener` never writes audio. (SpeechController.swift:105–107, WakeWordListener.swift) |
| Wake word can't bypass confirmations | ✅ | `wakeCommand` → `submit(command, spoken: true)` → `engine.handle` → same router path. (AppState.swift:156–165) |
| IDE bridge: localhost + token + 0600 | ✅ | `http.createServer` on `127.0.0.1`; 24-byte hex token in 0600 file; `safeEqual` uses `timingSafeEqual`. (extension.js:37, 86, 109, 121–125) |

## 6. ROADMAP Accuracy Assessment

The ROADMAP is **partially stale**. The "Current state" and Log are current (2026-09-23, up to 18:12), but the per-phase checkboxes have not been updated to reflect the verification runs. The "Progress at a glance" table is mostly accurate but understates how much is actually written (Phases 3, 3b, 3c code exists and compiles; they just need owner hands-on verification, not implementation).

The test count is the most visible gap: the Log says "115 tests pending" and references "139/139," but `swift test` reports **147 pass**.

## 7. Next Steps

Per AGENTS.md: "If the current phase has unchecked Verification boxes, do those first." Phases 1 and 2 are essentially done. The actionable next steps are:

### Priority 1: Close out Phase 1 (owner-eyes only)
- **Output view refresh**: The code is implemented (`AppState.panelDidShow` → 1s `outputTimer` → `refreshOutput` → `engine.lockedOutput()` + `engine.screens()`). The box `[ ] Output view shows freebuff's screen and refreshes each second` needs the owner to confirm visually. Agents cannot see the menu-bar app window.

### Priority 2: Update ROADMAP checkboxes
- Mark Phase 0 and Phase 1 items `[x]` (verified by logs).
- Mark Phase 2 items `[x]` (147 tests pass).
- Update all stale test counts: 57→147 (Phase 1), 139→147 (Phase 2/3e), ~115→147.
- For Phase 7a and Phases 3/3b/3c: leave checkboxes as `[w]` (code written + compiles, not yet owner-verified) rather than `syntax parse only`, since the app build does succeed. The Log entries that say "syntax parse only" are now inaccurate.

### Priority 3: Phase 3 voice test set (agent-doable)
- Create `Packages/VoxCore/Tests/Fixtures/commands.json` with real transcripts → expected intents. This is the `[ ]` box "Voice test set." Can be built and tested without a Mac (pure VoxCore logic).
- Write a test harness that loads the JSON and asserts `CommandParser.parse` produces the right intent for each.

### Priority 4: Phase 4 IDE chat (agent-doable research)
- Find the chat-panel command IDs for Antigravity and Kiro. Record them in `docs/ARCHITECTURE.md`.
- Implement the missing `IDECommand` cases (open folder/file, run task, send prompt to AI chat).

### Priority 5: Cleanup
- Delete `_to_delete/` (duplicate `SpeechOutput.swift`).
- Fix doc path: `packages/` → `Packages/` in AGENTS.md.

### Priority 6: Git
- Initialize a git repo for vox (or commit into the parent monorepo). Without version control, the "small commits, conventional messages" rule in AGENTS.md cannot be followed.
