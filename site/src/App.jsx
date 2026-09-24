import React, { useEffect, useState } from "react";

const REPO = "https://github.com/Mattathiasa/vox";
const RELEASES = `${REPO}/releases/latest`;
const MAC_ZIP = `${REPO}/releases/latest/download/Vox-mac.zip`;
const WIN_ZIP = `${REPO}/releases/latest/download/Vox-Windows.zip`;
const DEMO = `${import.meta.env.BASE_URL}demo/`;

const SAYINGS = [
  "Balcha, run claude in chirp and add tests",
  "Balcha, tell kilo to write the README",
  "Balcha, open Antigravity with 3 terminals running claude, freebuff and npm run dev",
  "Balcha, what's 15 percent of 80",
  "Balcha, kill freebuff … yes",
  "Balcha, search youtube for lofi beats",
  "Balcha, set a timer for 25 minutes",
];

const FEATURES = [
  { icon: "🎙", title: "Say “Balcha”", text: "An always-on wake word, recognized on-device on the Mac. Or hold ⌥Space, or type." },
  { icon: "⌨️", title: "Agents in real terminals", text: "Claude Code, Kilo, Freebuff, Codex… start in the right project folder, get your prompt typed in, and keep running when you look away." },
  { icon: "📱", title: "Your phone is the remote", text: "Watch every agent's screen live, type into it, answer “are you sure?” prompts, from the couch or anywhere through Tailscale." },
  { icon: "🪟", title: "Mac and Windows", text: "A native SwiftUI app on the Mac, a Node.js agent with native ConPTY terminals on Windows, and the same phone app for both." },
  { icon: "🛡", title: "Safe by design", text: "Spoken text is never run as a shell command. git push, rm, deploy and every kill wait for your “yes”." },
  { icon: "🧩", title: "Drives your IDE", text: "A tiny extension lets Vox open and target terminals in Antigravity, Kiro and VS Code: “run npm test in terminal 2”." },
];

const STACK = ["Swift", "SwiftUI", "AppKit", "Speech", "tmux", "Network.framework", "Node.js", "node-pty / ConPTY", "xterm headless",
  "PowerShell", "PWA", "Web Speech API", "Tailscale", "XCTest", "node:test", "Playwright", "React", "Vite", "GitHub Actions"];

function useRotating(list, ms = 3200) {
  const [i, setI] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setI((n) => (n + 1) % list.length), ms);
    return () => clearInterval(t);
  }, [list, ms]);
  return list[i];
}

function Nav() {
  return (
    <nav className="nav glass">
      <a className="brand" href="#top"><span className="orb-dot" /> Vox</a>
      <div className="nav-links">
        <a href="#features">Features</a>
        <a href="#how">How it works</a>
        <a href="#download">Download</a>
        <a href={REPO} target="_blank" rel="noreferrer">GitHub</a>
      </div>
    </nav>
  );
}

function Hero() {
  const saying = useRotating(SAYINGS);
  return (
    <header className="hero" id="top">
      <div className="hero-copy">
        <p className="eyebrow">Voice assistant for developers · Mac + Windows + phone</p>
        <h1>Talk to your AI&nbsp;coding&nbsp;agents.</h1>
        <p className="lede">
          Vox starts Claude Code, Kilo and friends in the right project, types what you say, and puts every
          terminal on your phone. Hands free, and it asks before anything risky.
        </p>
        <p className="saying" key={saying}>“{saying}”</p>
        <div className="cta">
          <a className="btn primary" href={DEMO}>Try it in your browser</a>
          <a className="btn" href="#download">Download</a>
          <a className="btn ghost" href={REPO} target="_blank" rel="noreferrer">View source</a>
        </div>
        <p className="fine">The demo runs the real Vox command grammar against a simulated computer. Voice works in Chrome and Safari.</p>
      </div>
      <div className="phone" aria-label="Live demo">
        <div className="phone-notch" />
        <iframe title="Vox live demo" src={DEMO} allow="microphone" loading="lazy" />
      </div>
    </header>
  );
}

function Features() {
  return (
    <section id="features" className="section">
      <h2>Everything your hands were doing</h2>
      <div className="grid">
        {FEATURES.map((f) => (
          <article key={f.title} className="card glass">
            <div className="card-icon">{f.icon}</div>
            <h3>{f.title}</h3>
            <p>{f.text}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function How() {
  const steps = [
    { n: "1", t: "You speak", d: "“Balcha, tell claude to fix the login bug.” The wake word and speech are handled on-device (Mac) or by the browser (phone, Windows)." },
    { n: "2", t: "Rules decide", d: "A predictable grammar and state machine turn words into actions: which tool, which folder, what text. An LLM only helps when the rules miss." },
    { n: "3", t: "Safety checks", d: "Risky words (push, rm, deploy, force) and every kill wait for “yes”. Spoken text is typed, never executed." },
    { n: "4", t: "Things happen", d: "tmux (Mac) or ConPTY (Windows) terminals, desktop actions, IDE terminals, all visible live in the HUD and on your phone." },
  ];
  return (
    <section id="how" className="section">
      <h2>How it works</h2>
      <ol className="steps">
        {steps.map((s) => (
          <li key={s.n} className="glass">
            <span className="step-n">{s.n}</span>
            <div><h3>{s.t}</h3><p>{s.d}</p></div>
          </li>
        ))}
      </ol>
      <div className="stack">
        {STACK.map((s) => <span key={s} className="chip">{s}</span>)}
      </div>
    </section>
  );
}

function Download() {
  return (
    <section id="download" className="section">
      <h2>Get Vox</h2>
      <p className="muted center">Free and open source. Beta builds are <b>unsigned</b>. The steps below are the one-time way past the OS warning.</p>
      <div className="grid three">
        <article className="card glass">
          <h3> Mac</h3>
          <p className="muted">macOS 14+, Apple Silicon or Intel</p>
          <a className="btn primary block" href={MAC_ZIP}>Download for Mac (beta)</a>
          <ol className="small">
            <li>Unzip, drag Vox to Applications.</li>
            <li>Open it once. macOS says it can't verify the developer.</li>
            <li>System Settings → Privacy &amp; Security → <b>Open Anyway</b>.</li>
            <li>Allow Microphone, Speech Recognition and Accessibility when asked.</li>
          </ol>
        </article>
        <article className="card glass">
          <h3>⊞ Windows</h3>
          <p className="muted">Windows 10/11 · Node.js 20+</p>
          <a className="btn primary block" href={WIN_ZIP}>Download for Windows (beta)</a>
          <ol className="small">
            <li>Install Node: <code>winget install OpenJS.NodeJS.LTS</code></li>
            <li>Unzip, double-click <b>Install-Vox.cmd</b> (SmartScreen: More info → Run anyway).</li>
            <li>Start <b>Vox</b> from the Start menu.</li>
          </ol>
          <p className="small">All versions and release notes: <a href={RELEASES}>GitHub Releases</a></p>
        </article>
        <article className="card glass">
          <h3>📱 Phone</h3>
          <p className="muted">iPhone or Android, no app store</p>
          <ol className="small">
            <li>Install <a href="https://tailscale.com/download" target="_blank" rel="noreferrer">Tailscale</a> on the computer and the phone.</li>
            <li>Mac: run <code>scripts/Remote-Tailscale.command</code>. Windows: <b>Remote-Tailscale.cmd</b>.</li>
            <li>Scan the QR code in Vox → Settings → Phone (Mac) or ⋯ → Pair a phone (Windows).</li>
            <li>Share → Add to Home Screen.</li>
          </ol>
        </article>
      </div>
      <div className="card glass source">
        <h3>Build from source (recommended for developers)</h3>
        <pre>{`git clone ${REPO}.git && cd vox
scripts/bootstrap.sh          # Mac: tmux + xcodegen, tests, Xcode project
open Vox.xcodeproj            # sign with your own (free) Apple ID, then ⌘R

cd windows && npm ci && npm start   # Windows agent`}</pre>
      </div>
    </section>
  );
}

function Security() {
  const items = [
    "Only commands from your own config file ever execute. Voice and LLM output are typed as keystrokes, never put in a shell string.",
    "Push, delete, rm, deploy, force, publish, and every kill need a spoken or tapped “yes”.",
    "The phone server listens on localhost only; Tailscale gives it HTTPS inside your private network. Home Wi-Fi access is off unless you turn it on.",
    "Pairing codes are ~100-bit, compared in constant time, sent in the URL fragment (never to a server), and 10 wrong tries lock that device out.",
    "On the Mac, speech is recognized on-device and audio is never recorded to disk.",
  ];
  return (
    <section className="section">
      <h2>Built to be trusted with a terminal</h2>
      <ul className="checks glass">
        {items.map((t) => <li key={t}>{t}</li>)}
      </ul>
    </section>
  );
}

export default function App() {
  return (
    <>
      <div className="wash" aria-hidden="true"><i /><i /><i /></div>
      <Nav />
      <main>
        <Hero />
        <Features />
        <How />
        <Security />
        <Download />
      </main>
      <footer className="footer">
        Built by <a href="https://github.com/Mattathiasa" target="_blank" rel="noreferrer">Mattathias Abraham</a> ·
        <a href={REPO} target="_blank" rel="noreferrer"> Source on GitHub</a> · MIT License
      </footer>
    </>
  );
}
