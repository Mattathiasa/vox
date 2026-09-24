# Vox: portfolio entry

Copy these fields into the portfolio. Keep the **Status** line honest: update it as Phase 10 items land.

---

## 1. Title

**Vox: a voice assistant that runs your AI coding agents**

## 2. Short description

Say "Balcha, run Claude in my chirp project and add tests". Vox starts the agent in the right folder, types
the prompt for you, and shows every running terminal live, on your Mac, your Windows PC, or your phone.

*(One-liner for cards: Voice and phone control for AI coding agents and your desktop, on Mac and Windows.)*

## 3. Language / Tags

`Swift` `SwiftUI` `AppKit` `JavaScript` `Node.js` `macOS` `Windows` `Voice UI` `Speech Recognition`
`tmux` `ConPTY` `PWA` `Tailscale` `Developer Tools` `AI Agents` `Security`

## 4. Full tech stack

| Layer | Mac | Windows | Phone |
|---|---|---|---|
| App shell | SwiftUI + AppKit menu-bar app, non-activating `NSPanel` HUD (glass UI, Liquid Glass on macOS 26+) | Node.js 20 agent; UI = the web app in an Edge app window | Installable PWA (HTML/CSS/JS, no framework, no build) |
| Voice | `SFSpeechRecognizer` (on-device), always-on wake word "Balcha", `AVSpeechSynthesizer` replies | Web Speech API | Web Speech API + `speechSynthesis` |
| Command understanding | Rule-based parser + pure state-machine router (Swift package `VoxCore`), LLM fallback (Apple on-device model / Claude API) | Line-by-line JS port of the same grammar | — |
| Terminals for AI agents | tmux on a private socket (`send-keys -l`, `capture-pane`, `resize-window`) | ConPTY via `node-pty` + `@xterm/headless` screen emulation | Live terminal view, key bar, line and live typing |
| Desktop control | NSWorkspace, AppleScript, CGEvent, Accessibility | PowerShell (data only in env vars), Win32 `keybd_event`, registry | — |
| IDE control | VS Code extension ("Vox Bridge", plain JS) over localhost HTTP + token, for Antigravity, Kiro, VS Code | — | — |
| Networking | Network.framework HTTP server, bearer pairing code, lockout, CSP | Node `http` server, same protocol | Polling JSON API; Tailscale Serve for HTTPS anywhere |
| Build / test | SwiftPM, XcodeGen, XCTest (180+ tests), self-test harness against real tmux + real tools | `node --test`: grammar parity, HTTP, real pseudo-terminals | Playwright screenshots |
| Cross-platform consistency | `shared/grammar-cases.json`: 95 scripted conversations both grammars must produce identically | | |

## 5. Git repo

`https://github.com/Mattathiasa/vox`

## 6. Live display

Landing page: `https://mattathiasa.github.io/vox/` · Live demo: `https://mattathiasa.github.io/vox/demo/`
(GitHub Pages, deployed by `.github/workflows/pages.yml`; downloads come from GitHub Releases)

What a visitor can actually do there:
- **Try it:** the phone UI running against a simulated computer *in the browser*, powered by the real
  command grammar (the same JavaScript the Windows app uses). Type or say "run claude and fix the login bug"
  and watch the fake terminal respond; "kill claude" asks for confirmation, and so on.
- **Download:** `Vox-mac.zip` and `Vox-Windows.zip` (unsigned beta) from GitHub Releases, built by `.github/workflows/release.yml` on each `v*` tag.
- **Watch:** a 60–90 s screen recording of the real thing (voice → agents → phone).

## 7. Long description

Vox started from a simple frustration: AI coding agents like Claude Code, Kilo and Freebuff live in
terminals, and driving several of them means constant window-juggling and typing. I wanted to *talk* to
them, from across the room or from my phone, the way you'd talk to a colleague.

On the Mac, Vox is a menu-bar app that listens for its wake word, "Balcha". Commands go through a
predictable rule-based grammar ("run claude in chirp and add tests", "tell kilo to write the README",
"open Antigravity with 3 terminals running claude, freebuff and npm run dev", "set a timer for 10 minutes",
"what's 15 percent of 80") and fall back to an LLM only for what the rules miss. Agents run in tmux sessions,
so they get a real terminal, keep running when you look away, and appear as live, resizable tiles in a glass
HUD where you can type straight into them.

Anything that could hurt (git push, rm, deploy, force, killing an agent) needs a spoken or tapped "yes",
and spoken text never becomes a shell command: it's only ever typed as keystrokes into tools you allowed in
your config.

The same brain powers a phone web app and a Windows version for my gaming PC. The phone connects through
Tailscale over HTTPS with a pairing code, so it works from anywhere without opening ports. It shows every
agent's screen live and lets you answer confirmations. On Windows, a Node.js port of the grammar drives
native ConPTY terminals and PowerShell. A shared file of 95 scripted conversations keeps the Swift and
JavaScript grammars from drifting apart: both test suites must produce identical output.

**Status (be honest here):** Mac app: daily-driven core, 180+ tests. Phone remote and Windows app:
built and tested in CI-style runs; first real-hardware runs in progress.

## 8. Challenges

1. **Agents need a real terminal.** Freebuff and Claude Code are full-screen TUIs that refuse to run on a
   pipe. I used tmux on a private socket: literal keystrokes with `send-keys -l`, screen reads with `capture-pane`,
   and `resize-window` so each agent redraws to fit its HUD tile. On Windows there's no tmux, so I used
   ConPTY (`node-pty`) plus a headless xterm to rebuild the screen.
2. **Voice without injection.** A misheard sentence or a YouTube video in the background must not run
   `rm -rf`. Security invariants: spoken/LLM text is never put in a shell string (only config-defined
   commands execute); risky phrases and every kill need a "yes"; on Windows, spoken text reaches PowerShell
   only through environment variables, never inside the script.
3. **A wake word that isn't English.** "Balcha" gets transcribed a dozen ways. It's matched against a
   configurable list of mishearings on an on-device transcript, with silence/timeout rules in a
   clock-injected, unit-tested state machine.
4. **Typing into the right app.** The HUD is a non-activating panel, so "type hello and press enter"
   goes to the app you were using, not to Vox. Opening an app and typing into it is pipelined with a focus delay.
5. **IDE terminals.** Simulated keystrokes land wherever focus is. I wrote a VS Code extension that exposes
   the IDE's terminals over localhost (token-protected), so "run npm test in terminal 2" hits exactly terminal 2,
   in Antigravity and Kiro.
6. **Phone mic needs HTTPS.** iOS Safari blocks the microphone on `http://` LAN pages. Tailscale Serve gives
   a real certificate and keeps the server bound to localhost. Pairing codes travel in the URL fragment
   (never sent to servers), are compared in constant time, and brute-forcing locks the device out.
7. **Two platforms, one grammar.** Swift can't target Windows' terminals well, so the Windows agent is a
   JavaScript port. Drift was the risk, so both test suites replay the same 95-conversation fixture file.
8. **Building with AI agents, verified.** Much of Vox was built with AI coding agents working from a
   roadmap file. Every phase has explicit verification boxes, and nothing is marked done without a test run
   on real hardware (self-test harness: 20 tmux cycles, real agents started and driven).

---

Screenshots to capture for the portfolio: glass HUD with 3 live agent tiles; phone home screen (orb +
terminals); phone full-screen terminal with keycaps; confirmation sheet; Settings → Phone QR.
