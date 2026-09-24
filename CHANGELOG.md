# Changelog

All notable changes to Vox. Versions follow [SemVer](https://semver.org); beta builds are unsigned.
The release workflow copies the section for a tag into its GitHub Release notes.

## v0.1.0 · 2026-09-24 · First public beta

### Mac
- Menu-bar app with the "Balcha" wake word (on-device), push-to-talk (⌥Space) and spoken replies
- Glass HUD: Siri-style orb, live terminal tiles for every agent, click-and-type live typing, key buttons, full-screen mode
- Run, talk to, interrupt, restart and kill CLI coding agents (Claude Code, Kilo, Freebuff, Codex, Gemini CLI, opencode) in tmux
- Desktop commands: apps, web and site search, typing and shortcuts, media and volume, timers, reminders, notes, quick answers, dark mode
- Vox Bridge extension: open and target terminals in Antigravity, Kiro and VS Code; IDE chat prompts
- LLM fallback (Apple on-device model or Claude) for commands the rules miss
- Settings: tools, projects, LLM, accent colour, phone remote with QR pairing

### Phone remote
- Installable web app for iPhone and Android: live terminals, line and live typing, confirmations, voice input, spoken replies
- Pairing code (constant-time compare, lockout), localhost-only server, Tailscale Serve for HTTPS anywhere

### Windows (beta)
- Node.js agent with the same grammar (95 shared test conversations), native ConPTY terminals, PowerShell desktop control
- Self-contained download (Node.js bundled), Install-Vox.cmd, Start menu + desktop shortcuts, Edge app window, Remote-Tailscale.cmd

### Known limitations
- Builds are unsigned: macOS needs "Open Anyway" once; Windows shows SmartScreen
- Windows: no wake word or IDE terminals yet
- Mac: tmux must be installed (`brew install tmux`)
