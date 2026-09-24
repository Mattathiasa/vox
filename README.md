# Vox

**Talk to your AI coding agents.** Say "Balcha, run claude in chirp and add tests": Vox starts Claude Code
in that project, types the prompt, and shows every agent's terminal live on your Mac, your Windows PC or your phone.
Risky things (git push, rm, deploy, killing an agent) wait for your "yes".

[![CI](https://github.com/Mattathiasa/vox/actions/workflows/ci.yml/badge.svg)](https://github.com/Mattathiasa/vox/actions/workflows/ci.yml)
· **[Try the live demo](https://mattathiasa.github.io/vox/demo/)** (real grammar, simulated computer)
· **[Landing page](https://mattathiasa.github.io/vox/)**
· **[Downloads](https://github.com/Mattathiasa/vox/releases/latest)** (beta, unsigned)

| | |
|---|---|
| **Mac** | SwiftUI menu-bar app, wake word "Balcha" (on-device), agents in tmux, glass HUD with live terminals, IDE terminals via the Vox Bridge extension |
| **Phone** | Installable web app: live terminals, typing, confirmations, voice; reach it anywhere through Tailscale (HTTPS) |
| **Windows** | Node.js agent: same grammar, agents in native ConPTY terminals, PowerShell desktop control ([windows/README.md](windows/README.md)) |

**Status:** beta. See [ROADMAP.md](ROADMAP.md) for what's verified; design in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build from source: Mac (macOS 14+, Xcode 26+)

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

## Phone remote

Vox → Settings → Phone → turn on. For voice and use away from home, install Tailscale on the Mac and phone,
run `scripts/Remote-Tailscale.command`, then scan the QR code. Protocol and security: ARCHITECTURE "Remote protocol".

## Windows

`scripts/Package-Windows.command` (or a release zip) → copy to the PC → `Install-Vox.cmd`. Details in [windows/README.md](windows/README.md).

## Development

```bash
scripts/test.sh                 # Swift tests (incl. grammar parity) + app build
(cd windows && npm test)        # Windows agent: grammar parity, HTTP, pseudo-terminals
(cd site && npm run dev)        # landing page + browser demo
node scripts/embed-web.mjs      # after editing web/remote (Mac serves an embedded copy)
```

Releases: push a `v*` tag; GitHub Actions builds `Vox-mac.zip` and `Vox-Windows.zip`. The landing page deploys from `main`.

MIT License · by [Mattathias Abraham](https://github.com/Mattathiasa)
