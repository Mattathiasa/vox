# Vox

A voice-controlled macOS menu-bar assistant for driving coding tools. Say
"run freebuff in chirp and add tests" and it starts freebuff in that project
and types the prompt. Everything you say after that goes straight to freebuff
until you say "exit".

**Status:** early. Phases 0–2 are written (typed commands, tmux, safety); voice is Phase 3.
See [ROADMAP.md](ROADMAP.md).

## Quick start (macOS 14+, Apple Silicon or Intel)

```bash
cd ~/Projects/vox
scripts/bootstrap.sh     # installs tmux + xcodegen, runs tests, generates Vox.xcodeproj
open Vox.xcodeproj       # set your Team under Signing & Capabilities, then Run
```

Then press **Option-Space** and type:

```
run freebuff in vox
explain what this project does      ← goes to freebuff
exit                                ← back to commands
what's running
kill freebuff                       ← asks for confirmation
```

Watch a tool in a real terminal: `tmux -L vox attach -t vox-freebuff`
(or click **Open in Terminal** in the panel).

## Config

`~/Library/Application Support/Vox/config.json` is created on first launch.
Add your tools (only these can ever be launched), projects, aliases for words
speech-to-text gets wrong, and the patterns that require confirmation.

## For AI agents

Start with [AGENTS.md](AGENTS.md).
