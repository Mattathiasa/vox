# Vox for Windows

Voice and phone control for your gaming PC: start `claude`, `kilo`, `freebuff` (any CLI in your config)
in native Windows terminals, see them live, type into them, open apps and games, media keys, volume,
timers, quick answers. Same phone web app as the Mac version.

## Install (once)

1. Install Node.js 20+: `winget install OpenJS.NodeJS.LTS`
2. Copy this folder to the PC (e.g. `C:\Users\<you>\Vox`); keep `public\` (or `..\web\remote`) next to it.
3. Double-click **Install-Vox.cmd**. It installs dependencies and adds **Vox** to the Start menu.
4. Start **Vox**. A window opens at `http://localhost:7788` (hold the mic button and talk, or type).

Config: `%APPDATA%\Vox\config.json`: `tools` (name, aliases, command, defaultDirectory), `projects`,
`apps` (spoken name → exe, shortcut or URI such as `steam://open/main`), `remote.allowLAN`.

## Phone

- **Anywhere, with voice (recommended):** install Tailscale on the PC and phone, run **Remote-Tailscale.cmd**,
  then in the Vox window: ⋯ → *Pair a phone* and scan the QR code. Add to Home Screen for an app icon.
- **Home Wi-Fi only:** set `"remote": { "allowLAN": true }` in the config and restart. Plain http, so voice
  only works through your phone keyboard's dictation mic.

## Safety

Same rules as the Mac app: tools start only from `tools[].command` in your config; spoken text is typed,
never run as a script (PowerShell gets it through environment variables); anything matching the confirm
patterns (push, delete, rm, force…) and every kill needs a "yes"; the phone needs the pairing code, and
10 wrong codes lock that device out for a minute.

## Voice on Windows

The window uses the browser's speech recognition (Edge/Chrome). That sends audio to Microsoft/Google for
recognition, unlike the Mac's on-device recognizer. The always-on "Balcha" wake word is not on Windows yet.

## Develop

`npm test` runs everything that doesn't need Windows (grammar parity with the Mac, router, server,
real pseudo-terminals via bash). `node src/main.js --demo` runs on any OS with a fake desktop.
