import React, { lazy, Suspense, useEffect, useRef, useState } from "react";
import {
  REPO, RELEASES_URL, LATEST_MAC, LATEST_WIN, SAYINGS, WORKS_WITH, STATS, FEATURES,
  COMMANDS, PLATFORMS, SECURITY, ROADMAP, FAQ,
} from "./data.js";
import { useTypewriter, useReveal, detectOS, useGitHub, formatSize } from "./hooks.js";
import { stage, pulse } from "./stage.js";

const Stage3D = lazy(() => import("./three/Stage3D.jsx"));
const DEMO = `${import.meta.env.BASE_URL}demo/`;

function sayInDemo(text) {
  const frame = document.getElementById("demo-frame");
  frame?.contentWindow?.postMessage({ type: "vox-say", text }, window.location.origin);
  pulse(0.8);
  document.getElementById("try")?.scrollIntoView({ behavior: "smooth", block: "start" });
}

// MARK: - Icons and small pieces

function Icon({ name, size = 20 }) {
  const paths = {
    github: <path d="M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.61.07-.61 1 .07 1.53 1.03 1.53 1.03.9 1.52 2.34 1.08 2.91.83.09-.65.35-1.08.63-1.33-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.3 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2Z" fill="currentColor" stroke="none" />,
    apple: <path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9-.7 0-1.8-.9-3-.8-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7c1.3 0 2.1-1.1 2.8-2.3.9-1.3 1.3-2.6 1.3-2.7 0 0-2.5-1-2.5-3.7ZM14.1 5.8c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3Z" fill="currentColor" stroke="none" />,
    windows: <path d="M3 5.5 10.5 4.5v7H3v-6Zm8.5-1.1L21 3v8.5h-9.5V4.4ZM3 12.5h7.5v7L3 18.5v-6Zm8.5 0H21V21l-9.5-1.3v-7.2Z" fill="currentColor" stroke="none" />,
    phone: <><rect x="7" y="2.5" width="10" height="19" rx="2.5" /><path d="M11 18.5h2" /></>,
    mic: <><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21" /></>,
    arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
    down: <path d="M12 5v14M6 13l6 6 6-6" />,
    download: <path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 19.5h14" />,
    star: <path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2L3 9.6l6.2-.9L12 3Z" fill="currentColor" stroke="none" />,
    shield: <path d="M12 3 4.5 6v5.5c0 4.6 3.2 8.4 7.5 9.5 4.3-1.1 7.5-4.9 7.5-9.5V6L12 3Z" />,
    menu: <path d="M4 7h16M4 12h16M4 17h16" />,
    close: <path d="M6 6l12 12M18 6 6 18" />,
  };
  return <svg className="icon" width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">{paths[name]}</svg>;
}

function Wave({ bars = 18 }) {
  return <span className="wave" aria-hidden="true">{Array.from({ length: bars }, (_, i) => <i key={i} style={{ animationDelay: `${(i * 83) % 700}ms` }} />)}</span>;
}

function Orb({ size = 120 }) {
  return <span className="orb" style={{ width: size, height: size }} aria-hidden="true"><i /><i /><i /><i /></span>;
}

function SectionHead({ index, eyebrow, title, text }) {
  return (
    <div className="section-head reveal">
      <p className="eyebrow">{index && <span className="idx">{index}</span>}{eyebrow}</p>
      <h2>{title}</h2>
      {text && <p className="section-text">{text}</p>}
    </div>
  );
}

// MARK: - Scroll → stage (which part of the page the 3D scene is serving)

function useScrollStage(setStep) {
  useEffect(() => {
    let raf = 0;
    const bar = document.getElementById("progress");
    const update = () => {
      raf = 0;
      const vh = window.innerHeight;
      const hero = document.getElementById("top");
      const story = document.getElementById("story");
      const max = document.documentElement.scrollHeight - vh;
      if (bar) bar.style.transform = `scaleX(${max > 0 ? window.scrollY / max : 0})`;
      const heroRect = hero?.getBoundingClientRect();
      const storyRect = story?.getBoundingClientRect();
      if (heroRect && heroRect.bottom > vh * 0.45) stage.mode = "hero";
      else if (storyRect && storyRect.top < vh * 0.6 && storyRect.bottom > vh * 0.4) {
        stage.mode = "story";
        const progress = Math.min(1, Math.max(0, -storyRect.top / (storyRect.height - vh)));
        stage.storyProgress = progress;
        const step = Math.min(3, Math.floor(progress * 4));
        if (step !== stage.step) { stage.step = step; setStep(step); if (step === 0) stage.pulseAt = performance.now() / 1000; }
      } else stage.mode = "ambient";
    };
    const onScroll = () => { if (!raf) raf = requestAnimationFrame(update); };
    update();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => { window.removeEventListener("scroll", onScroll); window.removeEventListener("resize", onScroll); cancelAnimationFrame(raf); };
  }, [setStep]);
}

/** Cursor-lit glass: sets --mx/--my on the .spot element under the pointer. */
function useSpotlight() {
  useEffect(() => {
    const on = (e) => {
      const el = e.target.closest?.(".spot");
      if (!el) return;
      const r = el.getBoundingClientRect();
      el.style.setProperty("--mx", `${e.clientX - r.left}px`);
      el.style.setProperty("--my", `${e.clientY - r.top}px`);
    };
    document.addEventListener("pointermove", on, { passive: true });
    return () => document.removeEventListener("pointermove", on);
  }, []);
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
  const links = [["#try", "Try it"], ["#story", "How it works"], ["#features", "Features"], ["#download", "Download"], ["#releases", "Releases"], ["#faq", "FAQ"]];
  return (
    <nav className={`nav ${scrolled ? "scrolled" : ""} ${open ? "open" : ""}`} aria-label="Main">
      <a className="brand" href="#top" onClick={() => setOpen(false)}><Orb size={26} /> Vox</a>
      <div className="nav-links">{links.map(([href, label]) => <a key={href} href={href} onClick={() => setOpen(false)}>{label}</a>)}</div>
      <div className="nav-actions">
        <a className="gh" href={REPO} target="_blank" rel="noreferrer" aria-label="GitHub"><Icon name="github" size={18} />{stars !== null && <span><Icon name="star" size={12} /> {stars}</span>}</a>
        <a className="btn small primary" href="#download">Download</a>
        <button className="menu-btn" aria-label="Menu" aria-expanded={open} onClick={() => setOpen(!open)}><Icon name={open ? "close" : "menu"} /></button>
      </div>
      <div id="progress" className="progress" aria-hidden="true" />
    </nav>
  );
}

// MARK: - Hero

function Hero({ latest, webgl }) {
  const { text } = useTypewriter(SAYINGS, { onChar: () => pulse(0.035), onDone: () => pulse(0.6) });
  const os = detectOS();
  const primary = os === "windows" ? { href: LATEST_WIN, label: "Download for Windows", icon: "windows" } : { href: LATEST_MAC, label: "Download for Mac", icon: "apple" };
  return (
    <header className="hero" id="top">
      <div className="hero-copy">
        <a className="announce reveal" href="#releases"><span className="pill-new">New</span>{latest ? `${latest.tag} · ` : ""}Phone remote + Windows beta<Icon name="arrow" size={14} /></a>
        <h1 className="reveal">Talk to your <br />AI coding <em>agents.</em></h1>
        <p className="lede reveal">Vox starts Claude Code, Kilo and friends in the right project, types what you say, streams every terminal to your Mac, PC or phone, and waits for your “yes” before anything risky.</p>
        <button className="voicebar spot reveal" onClick={() => sayInDemo(text || SAYINGS[0])} title="Send this to the live demo">
          <span className="voicebar-mic"><Icon name="mic" size={18} /></span>
          <Wave bars={12} />
          <span className="voicebar-text"><b>Balcha,</b> {text}<span className="caret" /></span>
          <span className="voicebar-try">Try <Icon name="arrow" size={13} /></span>
        </button>
        <div className="cta reveal">
          {os === "phone"
            ? <a className="btn primary" href={DEMO}>Open the live demo <Icon name="arrow" size={16} /></a>
            : <a className="btn primary" href={primary.href}><Icon name={primary.icon} size={18} /> {primary.label}</a>}
          <a className="btn" href="#try">Try it in your browser</a>
          <a className="btn ghost" href={REPO} target="_blank" rel="noreferrer"><Icon name="github" size={18} /> Source</a>
        </div>
        <div className="platforms reveal">
          <span><Icon name="apple" size={15} /> macOS 14+</span><span><Icon name="windows" size={14} /> Windows 10/11</span><span><Icon name="phone" size={15} /> iPhone &amp; Android</span><span>MIT · free</span>
        </div>
      </div>
      <div className="hero-space" aria-hidden="true">{!webgl && <Orb size={340} />}</div>
      <a className="scroll-hint" href="#try" aria-label="Scroll"><span>Scroll</span><Icon name="down" size={16} /></a>
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
  return <section className="stats">{STATS.map((s) => <div key={s.label} className="stat reveal"><b>{s.value}</b><span>{s.label}</span></div>)}</section>;
}

// MARK: - Try it (commands + live phone)

function TryIt() {
  const [tab, setTab] = useState(COMMANDS[0].group);
  const group = COMMANDS.find((c) => c.group === tab);
  return (
    <section id="try" className="section try">
      <div className="try-copy">
        <SectionHead index="01" eyebrow="Try it live" title={<>Say it like you'd <em>say it.</em></>} text="This is the real Vox phone app and the real command grammar, running against a simulated computer. Tap a phrase, or type your own. Voice works in Chrome and Safari." />
        <div className="tabs reveal" role="tablist">
          {COMMANDS.map((c) => <button key={c.group} role="tab" aria-selected={c.group === tab} className={c.group === tab ? "on" : ""} onClick={() => setTab(c.group)}>{c.group}</button>)}
        </div>
        <div className="cmd-list" key={tab}>
          {group.items.map((item, i) => (
            <button key={item} className="cmd spot" style={{ animationDelay: `${i * 35}ms` }} onClick={() => sayInDemo(item)}>
              <span className="cmd-q">“</span>{item}<span className="cmd-q">”</span><Icon name="arrow" size={14} />
            </button>
          ))}
        </div>
      </div>
      <div className="try-phone reveal">
        <div className="phone">
          <div className="phone-notch" />
          <iframe id="demo-frame" title="Vox live demo" src={DEMO} allow="microphone" />
        </div>
        <p className="phone-cap">Simulated computer · real Vox grammar</p>
      </div>
    </section>
  );
}

// MARK: - Story (pinned, drives the 3D orb)

const STORY = [
  { key: "Hear", title: "It hears you.", text: "“Balcha” wakes it. Speech is transcribed on-device on the Mac, never recorded to disk.",
    demo: (s) => <div className="trace"><Wave bars={22} /><p className="trace-say">“Balcha, tell claude to <span className={s >= 0 ? "hl" : ""}>push the fix</span>”</p></div> },
  { key: "Understand", title: "It understands.", text: "A predictable grammar and state machine, not a guessing game. An LLM only helps when the rules miss.",
    demo: () => <div className="trace chips"><span className="t-chip">intent <b>tell</b></span><span className="t-chip">tool <b>claude</b></span><span className="t-chip">text <b>“push the fix”</b></span><span className="t-chip dim">switch focus <b>no</b></span></div> },
  { key: "Check", title: "It asks first.", text: "“push” is risky, so Vox waits for your yes. Same for rm, deploy, force and every kill.",
    demo: () => <div className="trace"><div className="t-sheet"><span className="warn">?</span><p>Send to claude: “push the fix”?</p><div><em>Cancel</em><b>Yes, do it</b></div></div></div> },
  { key: "Act", title: "It gets it done.", text: "Typed into Claude's real terminal as keystrokes, never a shell string, and streamed live to your HUD and phone.",
    demo: () => <div className="trace"><pre className="t-term">{"> push the fix\n● Committing: fix(auth): trim token\n  ⎿ 1 file changed\n● Pushed to origin/main ✓"}</pre></div> },
];

function Story({ step }) {
  return (
    <section id="story" className="story">
      <div className="story-sticky">
        <div className="story-copy">
          <p className="eyebrow"><span className="idx">02</span>How it works</p>
          <h2 className="story-h">One sentence, <em>four steps.</em></h2>
          <ol className="story-steps">
            {STORY.map((s, i) => (
              <li key={s.key} className={i === step ? "on" : i < step ? "done" : ""}>
                <span className="n">{i + 1}</span>
                <div>
                  <h3>{s.key} <small>{s.title}</small></h3>
                  <p>{s.text}</p>
                  <div className="story-demo">{i === step && s.demo(step)}</div>
                </div>
              </li>
            ))}
          </ol>
        </div>
        <div className="story-dots" aria-hidden="true">{STORY.map((s, i) => <span key={s.key} className={i === step ? "on" : ""} />)}</div>
      </div>
    </section>
  );
}

// MARK: - Features

function FeatureVisual({ kind }) {
  switch (kind) {
    case "wake": return <div className="fv fv-wake"><Orb size={64} /><Wave bars={24} /><code>“Balcha, open safari”</code></div>;
    case "agents":
      return (
        <div className="fv fv-term">
          {[["claude", "● Writing tests/login.test.ts", "  ⎿ npm test → 4 passed"], ["kilo", "▸ Drafting README.md", "  ⎿ 4 sections"], ["freebuff", "▸ Refactoring auth.ts", "  ⎿ 2 files changed"]].map(([t, a, b], i) => (
            <div key={t} className={`mini-term ${i === 0 ? "active" : ""}`}><div className="mini-bar"><span />{t}</div><pre>{`> ${["add tests", "write the readme", "clean up auth"][i]}\n${a}\n${b}`}</pre></div>
          ))}
        </div>
      );
    case "phone": return <div className="fv"><div className="mini-phone"><Orb size={36} /><div className="mini-line" /><div className="mini-line short" /><div className="mini-card" /><div className="mini-card" /></div></div>;
    case "safe": return <div className="fv"><div className="t-sheet small"><span className="warn">?</span><p>Send to claude: “git push origin main”?</p><div><em>Cancel</em><b>Yes, do it</b></div></div></div>;
    case "ide": return <div className="fv"><div className="ide"><div className="ide-top"><span /><span /><span /> Antigravity</div><div className="ide-terms">{["claude", "freebuff", "npm run dev"].map((t, i) => <pre key={t}>{`terminal ${i + 1}\n$ ${t}`}</pre>)}</div></div></div>;
    case "desktop": return <div className="fv fv-desk">{["🧭 open safari", "🔎 search youtube for lofi", "⏱ timer 25 min", "🔊 volume 30", "🌙 dark mode", "⌘ close tab", "🧮 15% of 80 = 12"].map((t) => <span key={t} className="chip">{t}</span>)}</div>;
    default: return null;
  }
}

function Features() {
  return (
    <section id="features" className="section">
      <SectionHead index="03" eyebrow="Features" title={<>Everything your hands <em>were doing.</em></>} text="Built for the way people code now: several AI agents running at once, and you directing them." />
      <div className="bento">
        {FEATURES.map((f) => (
          <article key={f.key} className={`bento-card spot reveal ${f.size}`}>
            <FeatureVisual kind={f.key} />
            <h3>{f.title}</h3>
            <p>{f.text}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

function Showcase() {
  return (
    <section className="section showcase">
      <SectionHead index="04" eyebrow="On the Mac" title={<>A glass HUD for <em>all your agents.</em></>} text="Every running agent as a live tile. Click one and type like a real terminal, or keep talking. Esc hides it; the orb waits in the corner." />
      <div className="macwin reveal">
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
                  <div className="tile-input"><span>›</span> Command for {t}… <kbd>⏎</kbd><kbd>esc</kbd><kbd>⌃C</kbd></div>
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

function Platforms() {
  return (
    <section className="section">
      <SectionHead index="05" eyebrow="Platforms" title={<>One assistant, <em>three screens.</em></>} />
      <div className="table-wrap reveal">
        <table className="matrix">
          <thead><tr><th />{PLATFORMS.columns.map((c) => <th key={c}>{c}</th>)}</tr></thead>
          <tbody>{PLATFORMS.rows.map(([label, ...cells]) => <tr key={label}><td>{label}</td>{cells.map((c, i) => <td key={i} className={c.startsWith("✓") ? "yes" : c === "—" ? "no" : "later"}>{c}</td>)}</tr>)}</tbody>
        </table>
      </div>
    </section>
  );
}

function Security() {
  return (
    <section id="security" className="section">
      <SectionHead index="06" eyebrow="Security" title={<>Built to be trusted <em>with a terminal.</em></>} text="A voice assistant that types into your shell has to be paranoid. These rules are written down, enforced in code, and tested." />
      <div className="sec-grid">
        {SECURITY.map((s, i) => (
          <article key={s.title} className="sec spot reveal" style={{ transitionDelay: `${(i % 3) * 80}ms` }}>
            <span className="sec-ico"><Icon name="shield" size={18} /></span>
            <h3>{s.title}</h3>
            <p>{s.text}</p>
          </article>
        ))}
      </div>
    </section>
  );
}

// MARK: - Download + releases

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
      <SectionHead index="07" eyebrow="Download" title={<>Get <em>Vox.</em></>} text={fromGitHub && latest ? `Latest: ${latest.tag} · ${latest.date}${latest.prerelease ? " · beta" : ""}` : "Free and open source. Beta builds are unsigned; the steps get you past the one-time OS warning."} />
      <div className="dl-grid">
        <article className={`dl spot reveal ${os === "mac" ? "suggested" : ""}`}>
          {os === "mac" && <span className="badge">Your system</span>}
          <div className="dl-head"><Icon name="apple" size={30} /><div><h3>Mac</h3><p>macOS 14+ · Apple Silicon &amp; Intel</p></div></div>
          <a className="btn primary block" href={mac?.url ?? LATEST_MAC}><Icon name="download" size={18} /> Download for Mac{mac ? ` · ${formatSize(mac.size)}` : ""}</a>
          <ol className="steps-list">
            <li>Unzip and drag <b>Vox</b> to Applications.</li>
            <li>Open it once; macOS says it can't verify the developer.</li>
            <li>System Settings → Privacy &amp; Security → <b>Open Anyway</b>.</li>
            <li>Allow Microphone, Speech Recognition and Accessibility.</li>
            <li>For agents: <code>brew install tmux</code></li>
          </ol>
        </article>
        <article className={`dl spot reveal ${os === "windows" ? "suggested" : ""}`}>
          {os === "windows" && <span className="badge">Your system</span>}
          <div className="dl-head"><Icon name="windows" size={28} /><div><h3>Windows</h3><p>Windows 10/11 · x64 · Node.js included</p></div></div>
          <a className="btn primary block" href={win?.url ?? LATEST_WIN}><Icon name="download" size={18} /> Download for Windows{win ? ` · ${formatSize(win.size)}` : ""}</a>
          <ol className="steps-list">
            <li>Unzip <b>Vox-Windows.zip</b> anywhere (e.g. your user folder).</li>
            <li>Double-click <b>Install-Vox.cmd</b>. SmartScreen: <b>More info → Run anyway</b>.</li>
            <li>Vox opens, and it's in your Start menu and on your desktop.</li>
            <li>Say or type “run claude”: it starts in <code>D:\Projects</code> or <code>~\Projects</code>.</li>
          </ol>
        </article>
        <article className={`dl spot reveal ${os === "phone" ? "suggested" : ""}`}>
          {os === "phone" && <span className="badge">Your device</span>}
          <div className="dl-head"><Icon name="phone" size={28} /><div><h3>Phone</h3><p>iPhone &amp; Android · installs from your computer</p></div></div>
          <div className="phone-qr">
            <img src={`${import.meta.env.BASE_URL}demo-qr.svg`} alt="QR code: open the Vox demo on your phone" width="104" height="104" />
            <p><b>Try it on your phone now:</b> scan to open the live demo, then Share → Add to Home Screen.</p>
          </div>
          <ol className="steps-list">
            <li>Install Vox on your Mac or PC, and <a href="https://tailscale.com/download" target="_blank" rel="noreferrer">Tailscale</a> (free) on both.</li>
            <li>Mac: <code>scripts/Remote-Tailscale.command</code> · Windows: <b>Remote-Tailscale.cmd</b>.</li>
            <li>Scan the pairing QR in Vox → Settings → Phone, or ⋯ → Pair a phone.</li>
            <li>Share → <b>Add to Home Screen</b>. Now your phone controls your computer.</li>
          </ol>
        </article>
      </div>
      <div className="source spot reveal">
        <div><h3>Build from source</h3><p>Recommended for developers: sign with your own free Apple ID, and there are no warnings.</p></div>
        <button className="clone" onClick={copy} title="Copy"><code>{clone}</code><span>{copied ? "Copied ✓" : "Copy"}</span></button>
      </div>
      <p className="center muted small">Needs the AI agents you want to drive (Claude Code, Kilo…) and, on the Mac, <code>brew install tmux</code>. Checksums and all versions on <a href={RELEASES_URL}>GitHub Releases</a>.</p>
    </section>
  );
}

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
  const [open, setOpen] = useState(0);
  return (
    <section id="releases" className="section">
      <SectionHead index="08" eyebrow="Release notes" title={<>What's <em>new.</em></>} text={fromGitHub ? "Straight from GitHub Releases." : "From the changelog. Downloads appear here when the first release is published."} />
      <div className="timeline">
        {releases.map((r, i) => (
          <article key={r.tag} className={`release spot reveal ${open === i ? "open" : ""}`}>
            <button className="release-head" onClick={() => setOpen(open === i ? -1 : i)} aria-expanded={open === i}>
              <span className={`tag ${i === 0 ? "latest" : ""}`}>{r.tag}</span>
              {i === 0 && <span className="pill-new">Latest</span>}
              {(r.prerelease || /^v0\./.test(r.tag)) && <span className="pill-beta">Beta</span>}
              <h3>{r.title}</h3>
              <time>{r.date}</time>
            </button>
            {open === i && (
              <div className="release-body">
                <Notes body={r.body} />
                {r.assets?.length > 0 && <div className="assets">{r.assets.map((a) => <a key={a.name} href={a.url} className="chip"><Icon name="download" size={14} /> {a.name} · {formatSize(a.size)}</a>)}</div>}
                {r.url && <a className="more" href={r.url} target="_blank" rel="noreferrer">View on GitHub <Icon name="arrow" size={14} /></a>}
              </div>
            )}
          </article>
        ))}
      </div>
    </section>
  );
}

function Roadmap() {
  return (
    <section className="section">
      <SectionHead index="09" eyebrow="Roadmap" title={<>Where it's <em>going.</em></>} />
      <div className="road">{ROADMAP.map((col) => <div key={col.when} className={`road-col spot reveal ${col.when.toLowerCase()}`}><h3>{col.when}</h3><ul>{col.items.map((i) => <li key={i}>{i}</li>)}</ul></div>)}</div>
    </section>
  );
}

function Faq() {
  return (
    <section id="faq" className="section">
      <SectionHead index="10" eyebrow="FAQ" title={<>Questions, <em>answered.</em></>} />
      <div className="faq">{FAQ.map((f) => <details key={f.q} className="reveal"><summary>{f.q}<span className="plus" /></summary><p>{f.a}</p></details>)}</div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="final reveal">
      <h2>Put your agents on <em>speaking terms.</em></h2>
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
        <div><a className="brand" href="#top"><Orb size={24} /> Vox</a><p className="muted small">Voice and phone control for AI coding agents and your desktop.</p></div>
        <div><h4>Product</h4><a href="#try">Live demo</a><a href="#features">Features</a><a href="#download">Download</a><a href="#releases">Release notes</a></div>
        <div><h4>Project</h4><a href={REPO}>GitHub</a><a href={`${REPO}/blob/main/ROADMAP.md`}>Roadmap</a><a href={`${REPO}/blob/main/docs/ARCHITECTURE.md`}>Architecture</a><a href={`${REPO}/issues`}>Report an issue</a></div>
        <div><h4>Maker</h4><a href="https://github.com/Mattathiasa">Mattathias Abraham</a><a href={`${REPO}/blob/main/LICENSE`}>MIT License</a></div>
      </div>
      <div className="footer-big" aria-hidden="true">Vox</div>
      <p className="muted small copyright">© 2026 Mattathias Abraham · Built with Swift, Node.js, Three.js and a lot of talking to computers.</p>
    </footer>
  );
}

export default function App() {
  const { releases, latest, stars, fromGitHub } = useGitHub();
  const [step, setStep] = useState(0);
  const [webgl, setWebgl] = useState(true);
  useReveal();
  useSpotlight();
  useScrollStage(setStep);
  return (
    <>
      <div className="bg" aria-hidden="true"><i /><i /><div className="grid-lines" /><div className="grain" /></div>
      <Suspense fallback={null}><Stage3D onUnsupported={() => setWebgl(false)} /></Suspense>
      <Nav stars={stars} />
      <main>
        <Hero latest={fromGitHub ? latest : null} webgl={webgl} />
        <WorksWith />
        <Stats />
        <TryIt />
        <Story step={step} />
        <Features />
        <Showcase />
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
