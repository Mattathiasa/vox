// Everything the landing page says, in one place. Keep it honest: update STATUS/STATS as things are verified.

export const REPO = "https://github.com/Mattathiasa/vox";
export const RELEASES_URL = `${REPO}/releases`;
export const LATEST_MAC = `${REPO}/releases/latest/download/Vox-mac.zip`;
export const LATEST_WIN = `${REPO}/releases/latest/download/Vox-Windows.zip`;
export const API = "https://api.github.com/repos/Mattathiasa/vox";

export const SAYINGS = [
  "run claude in chirp and add tests",
  "tell kilo to write the README",
  "open Antigravity with 3 terminals running claude, freebuff and npm run dev",
  "kill freebuff",
  "what's 15 percent of 80",
  "search youtube for lofi beats",
  "set a timer for 25 minutes",
];

export const WORKS_WITH = ["Claude Code", "Kilo Code", "Freebuff", "Codex", "Gemini CLI", "opencode", "Antigravity", "Kiro", "VS Code", "Safari", "Steam"];

export const STATS = [
  { value: "184", label: "Swift tests" },
  { value: "95", label: "shared grammar conversations, Mac ⇄ Windows" },
  { value: "3", label: "platforms: Mac, Windows, phone" },
  { value: "0", label: "shell strings built from speech" },
];

export const FEATURES = [
  { key: "wake", size: "wide", title: "Just say “Balcha”", text: "An always-on wake word, transcribed on-device on the Mac. No push-to-talk, no cloud. Or hold ⌥Space, or type." },
  { key: "agents", size: "tall", title: "AI agents in real terminals", text: "Claude Code, Kilo, Freebuff, Codex… start in the right project, get your prompt typed in, and keep working when you look away. Watch them all live, resize, and type straight into any of them." },
  { key: "phone", size: "", title: "Your phone is the remote", text: "Every agent's screen, live typing, one-tap “yes”, and a mic button. From the couch, or anywhere through Tailscale." },
  { key: "safe", size: "", title: "Asks before anything risky", text: "git push, rm, deploy, force, and every kill wait for your “yes”. Spoken words are typed, never executed." },
  { key: "ide", size: "", title: "Drives your IDE's terminals", text: "“Open Antigravity with 3 terminals, run claude in the first.” A small extension targets terminal N exactly." },
  { key: "desktop", size: "wide", title: "And the rest of your computer", text: "Open and close apps, search the web, type and press shortcuts, media and volume, timers and reminders, dark mode, quick math, battery, clipboard, all by voice." },
];

export const PIPELINE = [
  { title: "Hear", text: "Wake word + speech-to-text: on-device on the Mac, the browser's recognizer on phone and Windows." },
  { title: "Understand", text: "A predictable rule-based grammar and state machine. An LLM (on-device or Claude) only helps when the rules miss." },
  { title: "Check", text: "Safety policy: risky words and every kill need a “yes”. Unknown tools and folders are refused, never guessed." },
  { title: "Act", text: "tmux (Mac) or ConPTY (Windows) terminals, desktop actions, IDE terminals, streamed live to the HUD and your phone." },
];

export const COMMANDS = [
  { group: "Agents", items: ["run claude in chirp and add tests", "tell kilo to write the README", "switch to freebuff", "interrupt", "restart claude", "what's running", "kill freebuff", "exit"] },
  { group: "IDE", items: ["open antigravity with 3 terminals", "run claude in the first, freebuff in the second", "in terminal 2 run npm run dev", "ask kiro to explain this file", "close the terminals"] },
  { group: "Apps", items: ["open safari", "switch to notes", "close slack", "hide discord", "open chirp in kiro", "open downloads"] },
  { group: "Web", items: ["search for swift concurrency", "search youtube for lofi beats", "play daft punk on youtube", "go to github dot com", "directions to bole airport"] },
  { group: "Keys & typing", items: ["type hello world and press enter", "press command shift t", "close tab", "new tab", "copy", "paste", "undo", "scroll down", "lock screen"] },
  { group: "Media", items: ["play", "pause", "next song", "volume up", "mute", "set volume to 30"] },
  { group: "Ask", items: ["what time is it", "what's the date", "battery", "what's 12 times 8", "15 percent of 80", "read clipboard", "what apps are open"] },
  { group: "Do", items: ["set a timer for 5 minutes", "remind me to stretch in an hour", "create a note called groceries", "dark mode", "turn off the screen"] },
];

export const PLATFORMS = {
  columns: ["Mac", "Windows", "Phone"],
  rows: [
    ["Wake word “Balcha”", "✓ on-device", "later", "—"],
    ["Push-to-talk / mic button", "✓ ⌥Space", "✓ in window", "✓"],
    ["Run & drive AI agents", "✓ tmux", "✓ ConPTY", "✓ remote"],
    ["Live terminals + direct typing", "✓", "✓", "✓"],
    ["Open/close apps, web, keys, media", "✓", "✓", "✓ remote"],
    ["IDE terminals (Antigravity, Kiro, VS Code)", "✓", "later", "✓ remote"],
    ["LLM fallback", "✓ Apple / Claude", "later", "—"],
    ["Spoken replies", "✓", "✓", "✓"],
  ],
};

export const SECURITY = [
  { title: "Speech never becomes code", text: "Only commands from your own config file execute. Voice and LLM output are typed as keystrokes (tmux send-keys -l) or passed to PowerShell as data in environment variables." },
  { title: "Yes before anything risky", text: "push, delete, rm, deploy, force, publish, reset --hard, and every kill are held until you say or tap “yes”." },
  { title: "Nothing open to your Wi-Fi", text: "The phone server binds to localhost. Tailscale Serve adds HTTPS inside your private tailnet. Home Wi-Fi access is an explicit opt-in." },
  { title: "Pairing you can't brute-force", text: "~100-bit codes, constant-time comparison, sent only in the URL fragment (never to a server), and lockout after 10 wrong tries." },
  { title: "Private by default", text: "Mac speech recognition is on-device and audio is never written to disk. No accounts, no telemetry, no servers of ours." },
  { title: "Open source", text: "Every line is on GitHub under the MIT license, with the security rules written down in AGENTS.md and tested." },
];

export const ROADMAP = [
  { when: "Now", items: ["Mac app, phone remote, Windows agent (beta)", "Browser demo running the real grammar", "Unsigned builds on GitHub Releases"] },
  { when: "Next", items: ["First-run setup wizard (permissions, tool picker)", "Windows: IDE terminals + on-device wake word", "Bundled Node runtime for a one-click Windows installer"] },
  { when: "Later", items: ["Signed + notarized Mac builds", "SpeechAnalyzer / Whisper backends for better accuracy", "Push notifications when an agent finishes"] },
];

export const FAQ = [
  { q: "Is Vox free?", a: "Yes, free and open source under the MIT license. You bring your own AI agents (Claude Code, Kilo, etc.), which have their own plans." },
  { q: "Why does macOS say it can't verify the developer?", a: "The beta isn't notarized yet (that needs Apple's paid developer program). Open it once, then System Settings → Privacy & Security → Open Anyway. Or build it from source with your own free Apple ID." },
  { q: "Does it record me or send my voice anywhere?", a: "On the Mac, speech is recognized on-device and audio is never saved. The phone and Windows use the browser's recognizer, which may use Apple, Google or Microsoft servers." },
  { q: "Can someone on my Wi-Fi control my computer?", a: "No. By default the phone server only listens on your computer itself; you reach it through Tailscale, which only your devices can join. Even then every request needs your pairing code." },
  { q: "Which AI agents work?", a: "Any CLI you can start in a terminal: add it to the config with a name, spoken aliases and the command. Claude Code, Kilo, Freebuff, Codex, Gemini CLI and opencode are set up out of the box." },
  { q: "Do I need Tailscale?", a: "Only for the phone away from home, or for the mic button on iPhone (Safari needs HTTPS). At home you can turn on Wi-Fi access instead and use the keyboard's dictation mic." },
  { q: "Does it work offline?", a: "Mostly. Agents, apps, keys, timers and on-device speech work offline on the Mac; the agents themselves may need the internet." },
  { q: "Why is the wake word “Balcha”?", a: "It's the maker's choice, and it's configurable. Because it isn't an English word, Vox keeps a list of its common mishearings." },
];

// Shown when the GitHub Releases API isn't reachable (or before the first release). Mirrors CHANGELOG.md.
export const CHANGELOG_FALLBACK = [
  {
    tag: "v0.1.0", date: "2026-09-24", title: "First public beta",
    notes: [
      "Mac: menu-bar app with the “Balcha” wake word, push-to-talk, glass HUD with live agent terminals and direct typing",
      "Agents: run, talk to, interrupt, restart and kill CLI coding agents in tmux; safety confirmations",
      "Desktop: apps, web, keys, media, volume, timers, reminders, notes, quick answers, dark mode",
      "IDE: Vox Bridge extension for Antigravity, Kiro and VS Code terminals",
      "Phone remote: installable web app with live terminals, typing, confirmations and voice; Tailscale HTTPS",
      "Windows (beta): Node.js agent with the same grammar, native ConPTY terminals and PowerShell desktop control",
      "LLM fallback (Apple on-device or Claude) for commands the rules miss",
    ],
  },
];
