import React, { useEffect, useRef, useState } from "react";
import {
  REPO, RELEASES_URL, LATEST_MAC, LATEST_WIN, SAYINGS, WORKS_WITH, STATS, FEATURES, PIPELINE,
  COMMANDS, PLATFORMS, SECURITY, ROADMAP, FAQ,
} from "./data.js";
import { useTypewriter, useReveal, detectOS, useGitHub, formatSize } from "./hooks.js";

const DEMO = `${import.meta.env.BASE_URL}demo/`;

/** Sends a phrase into the embedded demo (same-origin iframe; it listens for "vox-say"). */
function sayInDemo(text) {
  const frame = document.getElementById("demo-frame");
  frame?.contentWindow?.postMessage({ type: "vox-say", text }, window.location.origin);
  document.getElementById("try")?.scrollIntoView({ behavior: "smooth", block: "center" });
}

// MARK: - Small pieces

function Icon({ name, size = 20 }) {
  const paths = {
    github: <path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.08.63-1.33-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.3 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" fill="currentColor" stroke="none" />,
    apple: <path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9-.7 0-1.8-.9-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.7 0 0-2.5-1-2.5-3.7ZM14.1 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3Z" fill="currentColor" stroke="none" />,
    windows: <path d="M3 5.5 10.5 4.5v7H3v-6Zm8.5-1.1L21 3v8.5h-9.5V4.4ZM3 12.5h7.5v7L3 18.5v-6Zm8.5 0H21V21l-9.5-1.3v-7.2Z" fill="currentColor" stroke="none" />,
    phone: <><rect x="7" y="2.5" width="10" height="19" rx="2.5" /><path d="M11 18.5h2" /></>,
    mic: <><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" /></>,
    arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
    download: <path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 19.5h14" />,
    star: <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2L3 9.6l6.2-.9L12 3Z" fill="currentColor" stroke="none" />,
    check: <path d="m5 12.5 4.5 4.5L19 7.5" />,
    shield: <path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6L12 3Z" />,
    menu: <path d="M4 7h16M4 12h16M4 17h16" />,
    close: <path d="M6 6l12 12M18 6 6 18" />,
  };
  return <svg className="icon" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">{paths[name]}</svg>;
}

function Wave({ bars = 18, live = true }) {
  return (
    <span className={`wave ${live ? "live" : ""}`} aria-hidden="true">
      {Array.from({ length: bars }, (_, i) => <i key={i} style={{ animationDelay: `${(i * 83) % 700}ms` }} />)}
    </span>
  );
}

function Orb({ size = 120 }) {
  return <span className="orb" style={{ width: size, height: size }} aria-hidden="true"><i /><i /><i /><i /></span>;
}

function SectionHead({ eyebrow, title, text }) {
  return (
    <div className="section-head reveal">
      {eyebrow && <p className="eyebrow">{eyebrow}</p>}
      <h2>{title}</h2>
      {text && <p className="section-text">{text}</p>}
    </div>
  );
}

// MARK: - Nav

function Nav({ stars }) {
  const [open, setOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 12);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  const links = [["#features", "Features"], ["#how", "How it works"], ["#commands", "Commands"], ["#download", "Download"], ["#releases", "Release notes"], ["#faq", "FAQ"]];
  return (
    <nav className={`nav ${scrolled ? "scrolled" : ""} ${open ? "open" : ""}`}>
      <a className="brand" href="#top" onClick={() => setOpen(false)}><Orb size={26} /> Vox</a>
      <div className="nav-links">
        {links.map(([href, label]) => <a key={href} href={href} onClick={() => setOpen(false)}>{label}</a>)}
      </div>
      <div className="nav-actions">
        <a className="gh" href={REPO} target="_blank" rel="noreferrer"><Icon name="github" size={18} />{stars !== null && <span><Icon name="star" size={12} /> {stars}</span>}</a>
        <a className="btn small primary" href="#download">Download</a>
        <button className="menu-btn" aria-label="Menu" onClick={() => setOpen(!open)}><Icon name={open ? "close" : "menu"} /></button>
      </div>
    </nav>
  );
}

// MARK: - Hero

function Hero({ latest }) {
  const { text } = useTypewriter(SAYINGS);
  const os = detectOS();
  const primary = os === "windows" ? { href: LATEST_WIN, label: "Download for Windows", icon: "windows" }
    : { href: LATEST_MAC, label: "Download for Mac", icon: "apple" };
  return (
    <header className="hero" id="top">
      <div className="hero-copy">
        <a className="announce reveal" href="#releases">
          <span className="pill-new">New</span> {latest ? `${latest.tag} · ` : ""}Phone remote + Windows beta <Icon name="arrow" size={14} />
        </a>
        <h1 className="reveal">Talk to your <span className="grad-text">AI coding agents.</span></h1>
        <p className="lede reveal">
          Vox is a voice assistant for developers. It starts Claude Code, Kilo and friends in the right project,
          types what you say, shows every terminal live on your Mac, PC or phone, and asks before anything risky.
        </p>
        <button className="voicebar glass reveal" onClick={() => sayInDemo(text || SAYINGS[0])} title="Send this to the live demo">
          <span className="voicebar-mic"><Icon name="mic" size={18} /></span>
          <Wave bars={14} />
          <span className="voicebar-text"><b>Balcha,</b> {text}<span className="caret" /></span>
        </button>
        <div className="cta reveal">
          {os === "phone"
            ? <a className="btn primary" href={DEMO}>Open the live demo <Icon name="arrow" size={16} /></a>
            : <a className="btn primary" href={primary.href}><Icon name={primary.icon} size={18} /> {primary.label}</a>}
          <a className="btn" href="#try">Try it in your browser</a>
          <a className="btn ghost" href={REPO} target="_blank" rel="noreferrer"><Icon name="github" size={18} /> Source</a>
        </div>
        <p className="fine reveal">Free &amp; open source · macOS 14+ · Windows 10/11 · iPhone &amp; Android · beta builds are unsigned</p>
      </div>
      <div className="hero-visual reveal" id="try">
        <div className="float f1 glass"><span className="ok" /> Started claude in ~/Projects/chirp</div>
        <div className="float f2 glass"><span className="warn">?</span> Kill freebuff? <b>Yes, do it</b></div>
        <div className="float f3 glass"><Wave bars={8} /> “tell kilo to write the README”</div>
        <div className="phone">
          <div className="phone-notch" />
          <iframe id="demo-frame" title="Vox live demo" src={DEMO} allow="microphone" />
        </div>
      </div>
    </header>
  );
}

function WorksWith() {
  const list = [...WORKS_WITH, ...WORKS_WITH];
  return (
    <section className="works reveal" aria-label="Works with">
      <p>Works with</p>
      <div className="marquee"><div className="marquee-track">{list.map((w, i) => <span key={i}>{w}</span>)}</div></div>
    </section>
  );
}

function Stats() {
  return (
    <section className="stats">
      {STATS.map((s) => (
        <div key={s.label} className="stat reveal"><b className="grad-text">{s.value}</b><span>{s.label}</span></div>
      ))}
    </section>
  );
}

// MARK: - Features (bento with mini visuals)

function FeatureVisual({ kind }) {
  switch (kind) {
    case "wake":
      return <div className="fv fv-wake"><Orb size={64} /><Wave bars={26} /><code>“Balcha, open safari”</code></div>;
    case "agents":
      return (
        <div className="fv fv-term">
          {[["claude", "● Writing tests/login.test.ts", "  ⎿ npm test → 4 passed"], ["kilo", "▸ Drafting README.md", "  ⎿ 4 sections"], ["freebuff", "▸ Refactoring auth.ts", "  ⎿ 2 files changed"]].map(([t, a, b], i) => (
            <div key={t} className={`mini-term ${i === 0 ? "active" : ""}`}><div className="mini-bar"><span />{t}</div><pre>{`> ${i === 0 ? "add tests" : i === 1 ? "write the readme" : "clean up auth"}\n${a}\n${b}`}</pre></div>
          ))}
        </div>
      );
    case "phone":
      return <div className="fv fv-phone"><div className="mini-phone"><Orb size={36} /><div className="mini-line" /><div className="mini-line short" /><div className="mini-card" /><div className="mini-card" /></div></div>;
    case "safe":
      return <div className="fv fv-safe"><div className="mini-sheet"><span className="warn">?</span><p>Send to claude: “git push origin main”?</p><div><em>Cancel</em><b>Yes, do it</b></div></div></div>;
    case "ide":
      return <div className="fv fv-ide"><div className="ide"><div className="ide-top"><span /><span /><span /> Antigravity</div><div className="ide-terms">{["claude", "freebuff", "npm run dev"].map((t, i) => <pre key={t}>{`terminal ${i + 1}\n$ ${t}`}</pre>)}</div></div></div>;
    case "desktop":
      return <div className="fv fv-desk">{["🧭 open safari", "🔎 search youtube for lofi", "⏱ timer 25 min", "🔊 volume 30", "🌙 dark mode", "⌘ close tab", "🧮 15% of 80 = 12"].map((t) => <span key={t} className="chip">{t}</span>)}</div>;
    default:
      return null;
  }
}

function Features() {
  return (
    <section id="features" className="section">
      <SectionHead eyebrow="Features" title="Everything your hands were doing." text="Built for the way people code now: several AI agents running at once, and you directing them." />
      <div className="bento">
        {FEATURES.map((f) => (
          <article key={f.key} className={`bento-card glass reveal ${f.size}`}>
            <FeatureVisual kind={f.key} />
            <h3>{f.title}</h3>
            <p>{f.text}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

// MARK: - Showcase: the Mac HUD

function Showcase() {
  return (
    <section className="section showcase">
      <SectionHead eyebrow="On the Mac" title="A glass HUD for all your agents." text="Every running agent as a live tile. Click one and type like a real terminal, or just keep talking. Esc hides it; the orb stays in the corner." />
      <div className="macwin glass reveal">
        <div className="macwin-bar"><span className="tl r" /><span className="tl y" /><span className="tl g" /><b>Vox</b><span className="muted">Ready</span><span className="grow" /><span className="pillx">“Balcha” ●</span></div>
        <div className="macwin-body">
          <aside className="macwin-side">
            <p className="side-h">Sessions</p>
            {["claude", "kilo", "freebuff"].map((t, i) => <div key={t} className={`side-row ${i === 0 ? "on" : ""}`}><span className="tile-ico">›_</span>{t}<small>{i === 0 ? "Talking" : "Running"}</small></div>)}
            <p className="side-h">Recent</p>
            {["run claude in chirp", "tell kilo to write…", "open safari"].map((t) => <div key={t} className="side-row small">🎙 {t}</div>)}
          </aside>
          <div className="macwin-main">
            <div className="status-row"><Orb size={44} /><div><span className="pill">Talking to claude</span><p>“add tests for the login flow”</p></div><div className="banner-mini">✓ → claude: add tests for the login flow</div></div>
            <div className="tiles">
              {[["claude", ["✻ Welcome to Claude Code!", "", "> add tests for the login flow", "● Reading src/auth/ …", "  ⎿ Read 6 files", "● Writing tests/login.test.ts", "  ⎿ npm test → 4 passed ✓"]],
                ["kilo", ["Kilo Code CLI · ready", "", "> write the README", "▸ Drafting sections…", "  ⎿ Install · Usage · Config", "▸ README.md written"]],
                ["freebuff", ["freebuff ▸ ready", "", "> clean up auth.ts", "▸ 2 files changed", "▸ running tests…"]]].map(([t, lines], i) => (
                <div key={t} className={`tile ${i === 0 ? "linked" : ""}`}>
                  <div className="tile-bar"><span className="dot" />{t}<span className="muted">{i === 0 ? "Talking" : "Click to talk"}</span></div>
                  <pre>{lines.join("\n")}</pre>
                  <div className="tile-input"><span>›</span> Command for {t}… <kbd>⏎</kbd><kbd>esc</kbd><kbd>↑</kbd><kbd>⌃C</kbd></div>
                </div>
              ))}
            </div>
          </div>
        </div>
        <div className="macwin-cmd"><Icon name="mic" size={16} /> Ask Vox · e.g. open chirp in kiro <kbd>return</kbd></div>
      </div>
    </section>
  );
}

// MARK: - How it works

function How() {
  return (
    <section id="how" className="section">
      <SectionHead eyebrow="How it works" title="Predictable by design." text="Rules first, LLM second, safety always. The same grammar runs on the Mac (Swift) and Windows (JavaScript), and 95 shared test conversations keep them identical." />
      <ol className="pipeline">
        {PIPELINE.map((p, i) => (
          <li key={p.title} className="glass reveal" style={{ transitionDelay: `${i * 90}ms` }}>
            <span className="step">{i + 1}</span>
            <h3>{p.title}</h3>
            <p>{p.text}</p>
          </li>
        ))}
      </ol>
      <div className="arch glass reveal">
        <div className="arch-col"><b>You</b><span>🎙 voice</span><span>⌨️ typing</span><span>📱 phone</span></div>
        <div className="arch-arrow">→</div>
        <div className="arch-col core"><b>Vox core</b><span>Wake word</span><span>Grammar + router</span><span>Safety policy</span><span>LLM fallback</span></div>
        <div className="arch-arrow">→</div>
        <div className="arch-col"><b>Your machine</b><span>tmux / ConPTY agents</span><span>Apps, keys, media</span><span>IDE terminals</span><span>Live screens → HUD &amp; phone</span></div>
      </div>
    </section>
  );
}

// MARK: - Commands

function Commands() {
  const [tab, setTab] = useState(COMMANDS[0].group);
  const group = COMMANDS.find((c) => c.group === tab);
  return (
    <section id="commands" className="section">
      <SectionHead eyebrow="Commands" title="Say it like you'd say it." text="A few of the hundreds of phrasings Vox understands. Click one to try it in the live demo." />
      <div className="tabs reveal" role="tablist">
        {COMMANDS.map((c) => (
          <button key={c.group} role="tab" aria-selected={c.group === tab} className={c.group === tab ? "on" : ""} onClick={() => setTab(c.group)}>{c.group}</button>
        ))}
      </div>
      <div className="cmd-grid reveal" key={tab}>
        {group.items.map((item) => (
          <button key={item} className="cmd glass" onClick={() => sayInDemo(item)}>
            <span className="q">“</span>{item}<span className="q">”</span><Icon name="arrow" size={14} />
          </button>
        ))}
      </div>
    </section>
  );
}

// MARK: - Platforms, security

function Platforms() {
  return (
    <section className="section">
      <SectionHead eyebrow="Platforms" title="One assistant, three screens." />
      <div className="table-wrap glass reveal">
        <table className="matrix">
          <thead><tr><th />{PLATFORMS.columns.map((c) => <th key={c}>{c}</th>)}</tr></thead>
          <tbody>
            {PLATFORMS.rows.map(([label, ...cells]) => (
              <tr key={label}><td>{label}</td>{cells.map((c, i) => <td key={i} className={c.startsWith("✓") ? "yes" : c === "—" ? "no" : "later"}>{c}</td>)}</tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function Security() {
  return (
    <section id="security" className="section">
      <SectionHead eyebrow="Security" title="Built to be trusted with a terminal." text="A voice assistant that can type into your shell has to be paranoid. These rules are written down, enforced in code, and tested." />
      <div className="sec-grid">
        {SECURITY.map((s, i) => (
          <article key={s.title} className="sec glass reveal" style={{ transitionDelay: `${(i % 3) * 80}ms` }}>
            <span className="sec-ico"><Icon name="shield" size={18} /></span>
            <h3>{s.title}</h3>
            <p>{s.text}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

// MARK: - Download

function Download({ latest, fromGitHub }) {
  const os = detectOS();
  const asset = (name) => latest?.assets?.find((a) => a.name === name);
  const mac = asset("Vox-mac.zip");
  const win = asset("Vox-Windows.zip");
  const [copied, setCopied] = useState(false);
  const clone = `git clone ${REPO}.git && cd vox && scripts/bootstrap.sh`;
  const copy = () => navigator.clipboard?.writeText(clone).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500); });
  return (
    <section id="download" className="section">
      <SectionHead eyebrow="Download" title="Get Vox." text={fromGitHub && latest ? `Latest: ${latest.tag} · ${latest.date}${latest.prerelease ? " · beta" : ""}` : "Free and open source. Beta builds are unsigned; the steps below get you past the one-time OS warning."} />
      <div className="dl-grid">
        <article className={`dl glass reveal ${os === "mac" ? "suggested" : ""}`}>
          {os === "mac" && <span className="badge">Your system</span>}
          <div className="dl-head"><Icon name="apple" size={30} /><div><h3>Mac</h3><p>macOS 14+ · Apple Silicon &amp; Intel</p></div></div>
          <a className="btn primary block" href={mac?.url ?? LATEST_MAC}><Icon name="download" size={18} /> Download for Mac{mac ? ` · ${formatSize(mac.size)}` : ""}</a>
          <ol className="steps-list">
            <li>Unzip and drag <b>Vox</b> to Applications.</li>
            <li>Open it once. macOS says it can't verify the developer.</li>
            <li>System Settings → Privacy &amp; Security → <b>Open Anyway</b>.</li>
            <li>Allow Microphone, Speech Recognition and Accessibility.</li>
            <li>Needs <code>brew install tmux</code> for agents.</li>
          </ol>
        </article>
        <article className={`dl glass reveal ${os === "windows" ? "suggested" : ""}`}>
          {os === "windows" && <span className="badge">Your system</span>}
          <div className="dl-head"><Icon name="windows" size={28} /><div><h3>Windows</h3><p>Windows 10/11 · Node.js 20+</p></div></div>
          <a className="btn primary block" href={win?.url ?? LATEST_WIN}><Icon name="download" size={18} /> Download for Windows{win ? ` · ${formatSize(win.size)}` : ""}</a>
          <ol className="steps-list">
            <li>Install Node: <code>winget install OpenJS.NodeJS.LTS</code></li>
            <li>Unzip, double-click <b>Install-Vox.cmd</b>.</li>
            <li>SmartScreen: <b>More info → Run anyway</b>.</li>
            <li>Start <b>Vox</b> from the Start menu.</li>
          </ol>
        </article>
        <article className={`dl glass reveal ${os === "phone" ? "suggested" : ""}`}>
          {os === "phone" && <span className="badge">Your device</span>}
          <div className="dl-head"><Icon name="phone" size={28} /><div><h3>Phone</h3><p>iPhone &amp; Android · no app store</p></div></div>
          <a className="btn block" href="https://tailscale.com/download" target="_blank" rel="noreferrer">Get Tailscale (free)</a>
          <ol className="steps-list">
            <li>Install Tailscale on your computer and phone.</li>
            <li>Mac: <code>scripts/Remote-Tailscale.command</code> · Windows: <b>Remote-Tailscale.cmd</b>.</li>
            <li>Scan the QR in Vox → Settings → Phone (Mac) or ⋯ → Pair a phone (Windows).</li>
            <li>Share → <b>Add to Home Screen</b>.</li>
          </ol>
        </article>
      </div>
      <div className="source glass reveal">
        <div>
          <h3>Build from source</h3>
          <p>Recommended for developers. Sign with your own free Apple ID. No warnings, and permissions stick across updates.</p>
        </div>
        <button className="clone" onClick={copy} title="Copy">
          <code>{clone}</code><span>{copied ? "Copied ✓" : "Copy"}</span>
        </button>
      </div>
      <p className="center muted small">Requirements: tmux (Mac, via Homebrew) and the AI agents you want to drive (Claude Code, Kilo…). All versions on <a href={RELEASES_URL}>GitHub Releases</a>.</p>
    </section>
  );
}

// MARK: - Release notes

function Notes({ body }) {
  const lines = body.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  const out = [];
  let list = [];
  const flush = () => { if (list.length) { out.push(<ul key={`u${out.length}`}>{list.map((t, i) => <li key={i}>{t}</li>)}</ul>); list = []; } };
  for (const line of lines) {
    if (/^[-*] /.test(line)) list.push(line.slice(2).replace(/\*\*/g, ""));
    else { flush(); out.push(/^#+ /.test(line) ? <h4 key={out.length}>{line.replace(/^#+ /, "")}</h4> : <p key={out.length}>{line.replace(/\*\*/g, "")}</p>); }
  }
  flush();
  return <>{out}</>;
}

function Releases({ releases, fromGitHub }) {
  return (
    <section id="releases" className="section">
      <SectionHead eyebrow="Release notes" title="What's new." text={fromGitHub ? "Straight from GitHub Releases." : "From the changelog. Downloads appear here once the first release is published."} />
      <div className="timeline">
        {releases.map((r, i) => (
          <article key={r.tag} className="release glass reveal">
            <div className="release-meta">
              <span className={`tag ${i === 0 ? "latest" : ""}`}>{r.tag}</span>
              {i === 0 && <span className="pill-new">Latest</span>}
              {r.prerelease !== false && <span className="pill-beta">Beta</span>}
              <time>{r.date}</time>
            </div>
            <h3>{r.title}</h3>
            <div className="release-body"><Notes body={r.body} /></div>
            {r.assets?.length > 0 && (
              <div className="assets">{r.assets.map((a) => <a key={a.name} href={a.url} className="chip"><Icon name="download" size={14} /> {a.name} · {formatSize(a.size)}</a>)}</div>
            )}
            {r.url && <a className="more" href={r.url} target="_blank" rel="noreferrer">View on GitHub <Icon name="arrow" size={14} /></a>}
          </article>
        ))}
      </div>
    </section>
  );
}

// MARK: - Roadmap, FAQ, CTA, footer

function Roadmap() {
  return (
    <section className="section">
      <SectionHead eyebrow="Roadmap" title="Where it's going." />
      <div className="road">
        {ROADMAP.map((col) => (
          <div key={col.when} className={`road-col glass reveal ${col.when.toLowerCase()}`}>
            <h3>{col.when}</h3>
            <ul>{col.items.map((i) => <li key={i}>{i}</li>)}</ul>
          </div>
        ))}
      </div>
    </section>
  );
}

function Faq() {
  return (
    <section id="faq" className="section">
      <SectionHead eyebrow="FAQ" title="Questions, answered." />
      <div className="faq">
        {FAQ.map((f) => (
          <details key={f.q} className="glass reveal">
            <summary>{f.q}<span className="plus" /></summary>
            <p>{f.a}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="final glass reveal">
      <Orb size={90} />
      <h2>Put your agents on speaking terms.</h2>
      <p>Free, open source, and yours to change.</p>
      <div className="cta center">
        <a className="btn primary" href="#download"><Icon name="download" size={18} /> Download</a>
        <a className="btn" href={REPO} target="_blank" rel="noreferrer"><Icon name="github" size={18} /> Star on GitHub</a>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="footer">
      <div className="footer-grid">
        <div>
          <a className="brand" href="#top"><Orb size={24} /> Vox</a>
          <p className="muted small">Voice and phone control for AI coding agents and your desktop.</p>
        </div>
        <div><h4>Product</h4><a href="#features">Features</a><a href="#commands">Commands</a><a href="#download">Download</a><a href="#releases">Release notes</a></div>
        <div><h4>Project</h4><a href={REPO}>GitHub</a><a href={`${REPO}/blob/main/ROADMAP.md`}>Roadmap</a><a href={`${REPO}/blob/main/docs/ARCHITECTURE.md`}>Architecture</a><a href={`${REPO}/issues`}>Report an issue</a></div>
        <div><h4>Maker</h4><a href="https://github.com/Mattathiasa">Mattathias Abraham</a><a href={`${REPO}/blob/main/LICENSE`}>MIT License</a></div>
      </div>
      <p className="muted small copyright">© 2026 Mattathias Abraham · Built with Swift, Node.js and a lot of talking to computers.</p>
    </footer>
  );
}

export default function App() {
  const { releases, latest, stars, fromGitHub } = useGitHub();
  useReveal();
  return (
    <>
      <div className="bg" aria-hidden="true"><i /><i /><i /><div className="grid-lines" /></div>
      <Nav stars={stars} />
      <main>
        <Hero latest={fromGitHub ? latest : null} />
        <WorksWith />
        <Stats />
        <Features />
        <Showcase />
        <How />
        <Commands />
        <Platforms />
        <Security />
        <Download latest={fromGitHub ? latest : null} fromGitHub={fromGitHub} />
        <Releases releases={releases} fromGitHub={fromGitHub} />
        <Roadmap />
        <Faq />
        <FinalCta />
      </main>
      <Footer />
    </>
  );
}
