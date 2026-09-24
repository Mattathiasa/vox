// A simulated computer for the public demo. Uses the REAL Vox grammar and router
// (windows/src, the same code the Windows app runs) and fakes only the effects:
// terminals print scripted agent replies, desktop commands just say what they'd do.
import { SessionRouter, HELP_TEXT } from "../../../windows/src/router.js";
import { normalizeConfig } from "../../../windows/src/defaults.js";
import { evaluateMath, formatNumber, describeDuration } from "../../../windows/src/spoken.js";
import { describeCombo, urlFromSpoken, knownSite } from "../../../windows/src/keys.js";

const CONFIG = normalizeConfig({
  tools: [
    { name: "claude", aliases: ["claude code", "cloud code"], command: "claude", defaultDirectory: "~/Projects" },
    { name: "kilo", aliases: ["kilo code"], command: "kilo", defaultDirectory: "~/Projects" },
    { name: "freebuff", aliases: ["free buff", "freebuf"], command: "freebuff", defaultDirectory: "~/Projects" },
  ],
  projects: [
    { name: "chirp", aliases: ["chip"], path: "~/Projects/chirp" },
    { name: "portfolio", aliases: ["my portfolio"], path: "~/Projects/portfolio" },
  ],
});

const BANNERS = {
  claude: (cwd) => ["╭──────────────────────────────────────────╮", "│ ✻ Welcome to Claude Code!                │", "│   /help for help · /status for setup     │", `│   cwd: ${cwd.padEnd(34)}│`, "╰──────────────────────────────────────────╯", ""],
  kilo: (cwd) => ["Kilo Code CLI · ready", `workspace: ${cwd}`, ""],
  freebuff: (cwd) => ["freebuff ▸ free AI coding agent", `project: ${cwd}`, ""],
};

function replyFor(tool, prompt) {
  const p = prompt.toLowerCase();
  const name = tool === "claude" ? "●" : "▸";
  if (/test/.test(p)) return [`${name} I'll add tests. Reading src/ …`, "  ⎿ Read 6 files", `${name} Writing tests/login.test.ts (4 tests)`, "  ⎿ npm test → 4 passed", `${name} Done: 4 new tests, all passing.`];
  if (/bug|fix|error/.test(p)) return [`${name} Looking for the bug …`, "  ⎿ Found it in src/auth.ts:42 (token compared before trim)", `${name} Fixed and re-ran the tests: all green.`];
  if (/readme|doc/.test(p)) return [`${name} Drafting README.md …`, "  ⎿ Sections: Install · Usage · Config · Security", `${name} README.md written (1.8 KB).`];
  if (/push|deploy|delete|rm /.test(p)) return [`${name} Running: ${prompt}`, "  ⎿ (demo) nothing actually happened"];
  return [`${name} ${prompt.charAt(0).toUpperCase()}${prompt.slice(1)}: on it.`, "  ⎿ Thinking …", `${name} Done. (This is the demo; the real agent does the real work.)`];
}

export class DemoAgent {
  constructor() {
    this.router = new SessionRouter(CONFIG);
    this.screens = new Map(); // tool -> { lines: [], input: "", exited }
    this.log = [];
    this.history = [];
    this.busy = false;
    this.timers = [];
  }

  // MARK: protocol

  state(lines = 60) {
    return {
      name: "Vox", host: "Demo Mac (simulated)", platform: "mac", version: 1,
      lockedTool: this.router.lockedTool, pendingQuestion: this.router.pending?.question ?? null,
      busy: this.busy, wake: { enabled: true, name: "Balcha" },
      tools: CONFIG.tools.map((t) => t.name),
      screens: [...this.screens].map(([tool, s]) => ({ tool, text: [...s.lines, `> ${s.input}`].slice(-lines).join("\n"), exited: s.exited })),
      history: this.history, log: this.log.slice(-60),
    };
  }

  async request(method, path, body = {}) {
    const route = path.replace(/^.*?api\//, "").split("?")[0];
    if (route === "state") return this.state(Number(new URLSearchParams(path.split("?")[1]).get("lines")) || 60);
    if (route === "pairing") throw Object.assign(new Error("Pairing is only on the real app."), { status: 404 });
    if (route === "command") return { events: this.command(body.text || "", body.spoken) };
    if (route === "confirm") return { events: this.router.pending ? this.command(body.yes ? "yes" : "no") : [ev("info", "Nothing to confirm.")] };
    if (route === "exit") { this.router.unlock(); return { events: [] }; }
    const m = route.match(/^tools\/([^/]+)\/(\w+)$/);
    if (!m) throw Object.assign(new Error("No such endpoint."), { status: 404 });
    const tool = decodeURIComponent(m[1]);
    switch (m[2]) {
      case "launch": return { events: this.command(`vox run ${tool}`) };
      case "kill": return { events: this.command(`vox kill ${tool}`) };
      case "focus": return { events: this.command(`vox switch to ${tool}`) };
      case "send": return { events: this.run(this.router.sendTo(tool, body.text || "")) };
      case "type": return { events: this.type(tool, body.text || "") };
      case "key": return { events: this.key(tool, body.key || "") };
      default: throw Object.assign(new Error("No such endpoint."), { status: 404 });
    }
  }

  // MARK: engine

  append(kind, text) {
    this.log.push({ kind, text, time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }) });
  }

  command(text, spoken = false) {
    const trimmed = String(text).trim();
    if (!trimmed) return [];
    this.append("info", `› ${trimmed}`);
    const events = this.run(this.router.handle(trimmed));
    const order = ["error", "confirm", "warning", "info", "success"];
    const worst = order.find((k) => events.some((e) => e.kind === k)) ?? "info";
    this.history.unshift({ command: trimmed, kind: worst, reply: events.find((e) => e.kind === worst)?.message ?? "", spoken: Boolean(spoken), source: "phone" });
    this.history.length = Math.min(this.history.length, 8);
    return events;
  }

  run(actions) {
    const events = actions.flatMap((a) => this.execute(a));
    for (const e of events) this.append(e.kind, e.message);
    return events;
  }

  execute(a) {
    switch (a.action) {
      case "launch": {
        if (this.screens.has(a.tool) && !this.screens.get(a.tool).exited) {
          const out = [ev("info", `${a.tool} is already running. Talking to it now.`)];
          if (a.prompt) out.push(...this.sendToTool(a.tool, a.prompt));
          return out;
        }
        const cwd = a.directory || "~";
        this.screens.set(a.tool, { lines: BANNERS[a.tool]?.(cwd) ?? [`${a.tool} started`], input: "", exited: false });
        const out = [ev("success", `Started ${a.tool} in ${cwd}. Talking to it now.`)];
        if (a.prompt) out.push(...this.sendToTool(a.tool, a.prompt, 700));
        return out;
      }
      case "focus":
        if (!this.screens.has(a.tool)) { this.router.unlock(); return [ev("warning", `${a.tool} isn't running. Say "run ${a.tool}".`)]; }
        return [ev("success", `Talking to ${a.tool}. Say "exit" to stop.`)];
      case "send": return this.sendToTool(a.tool, a.text);
      case "kill":
        if (!this.screens.delete(a.tool)) return [ev("info", `${a.tool} wasn't running.`)];
        return [ev("success", `Killed ${a.tool}.`)];
      case "list": return [ev("info", this.screens.size ? `Running: ${[...this.screens.keys()].join(", ")}` : "No tools running.")];
      case "interrupt": {
        const s = this.screens.get(a.tool);
        if (!s) return [ev("info", `${a.tool} isn't running.`)];
        s.lines.push("^C", "Interrupted.");
        return [ev("success", `Interrupted ${a.tool}.`)];
      }
      case "show": return [ev("info", `On the real Mac this opens ${a.tool} in Terminal.`)];
      case "confirm": return [ev("confirm", a.question)];
      case "feedback": return [ev("info", a.help ? HELP_TEXT : a.message)];
      case "llm": return [ev("info", `The rules didn't catch "${a.text}". In the real app, an LLM (on-device or Claude) gets a try next. Tap ⋯ → What can I say?`)];
      case "desktop": return [this.desktop(a.command)];
      default: return [];
    }
  }

  sendToTool(tool, text, delay = 0) {
    const s = this.screens.get(tool);
    if (!s) { this.router.unlock(); return [ev("error", `Session ${tool} is not running.`)]; }
    setTimeout(() => {
      s.lines.push(`> ${text}`);
      this.busy = true;
      replyFor(tool, text).forEach((line, i) => setTimeout(() => {
        s.lines.push(line);
        if (i === replyFor(tool, text).length - 1) { s.lines.push(""); this.busy = false; }
      }, 500 + i * 650));
    }, delay);
    return [ev("success", `→ ${tool}: ${text}`)];
  }

  type(tool, text) {
    const s = this.screens.get(tool);
    if (!s) return [ev("warning", `${tool} isn't running.`)];
    s.input += text;
    return [];
  }

  key(tool, key) {
    const s = this.screens.get(tool);
    if (!s) return [ev("warning", `${tool} isn't running.`)];
    if (key === "Enter") {
      const line = s.input;
      s.input = "";
      if (line.trim()) this.sendToTool(tool, line.trim()); else s.lines.push(">");
    } else if (key === "BSpace") s.input = s.input.slice(0, -1);
    else if (key === "C-c") { s.input = ""; s.lines.push("^C"); }
    else if (key === "Escape") s.lines.push("(esc)");
    return [];
  }

  desktop(c) {
    const d = (message) => ev("success", `Demo: ${message}`);
    switch (c.type) {
      case "openApp": return d(knownSite(c.name) ? `would open ${new URL(knownSite(c.name)).host}` : `would open ${c.name}`);
      case "focusApp": return d(`would switch to ${c.name}`);
      case "quitApp": return d(`would quit ${c.name}`);
      case "hideApp": return d(`would hide ${c.name}`);
      case "createNote": return d(`would create a note: ${c.text}`);
      case "webSearch": return d(`would search the web for ${c.query}`);
      case "openURL": return d(`would open ${urlFromSpoken(c.spoken) ?? c.spoken}`);
      case "typeText": return d(`would type "${c.text}" into the front app`);
      case "pressKey": return d(`would press ${describeCombo(c.combo)}`);
      case "volume": return d(`volume ${c.change}`);
      case "media": return d({ playPause: "play/pause", next: "next track", previous: "previous track" }[c.key]);
      case "timer": return ev("info", `Timer set for ${describeDuration(c.seconds)}.`);
      case "cancelTimers": return ev("info", "No timers running.");
      case "reminder": return ev("info", `I'd remind you to ${c.text}${c.seconds ? ` in ${describeDuration(c.seconds)}` : ""}.`);
      case "openFolder": return d(`would open ${c.name} in Finder`);
      case "openProject": return d(`would open ${c.project} in ${c.app}`);
      case "siteSearch": return d(`would search ${c.site} for ${c.query}`);
      case "system": return d(c.action === "screenOff" ? "screen off" : `dark mode ${c.on === null ? "toggled" : c.on ? "on" : "off"}`);
      case "ide": return d(ideText(c.ide));
      case "sendMessageToApp": return d(`would send "${c.text}" to the Claude app`);
      case "answer": return ev("info", answer(c));
      default: return d(`would run ${c.type}`);
    }
  }
}

function ideText(i) {
  switch (i.op) {
    case "openTerminals": return `would open ${i.count} terminal${i.count === 1 ? "" : "s"} in the IDE${i.commands.length ? ` running ${i.commands.join(", ")}` : ""}`;
    case "send": return `would ${i.submit ? "run" : "type"} "${i.text}" in terminal ${i.target}`;
    case "closeTerminals": return "would close the IDE terminals";
    case "chat": return `would ask the IDE's AI: ${i.message}`;
    default: return `IDE: ${i.op}`;
  }
}

function answer(c) {
  const now = new Date();
  switch (c.question) {
    case "time": return `It's ${now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}.`;
    case "date": return `Today is ${now.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}.`;
    case "battery": return "Battery is at 87% and charging. (demo)";
    case "clipboard": return "Your clipboard says: hello from the demo";
    case "openApps": return "Open apps: Safari, Antigravity, Terminal. (demo)";
    case "calculation": { const v = evaluateMath(c.expression); return v === null ? "I couldn't work that out." : `That's ${formatNumber(v)}.`; }
    default: return "";
  }
}

const ev = (kind, message) => ({ kind, message });

/** Replaces fetch("api/…") with the simulated agent so the unchanged web app runs against it. */
export function installDemo() {
  const agent = new DemoAgent();
  try { localStorage.setItem("voxToken", "demo"); } catch { /* private mode */ }
  const realFetch = window.fetch.bind(window);
  window.fetch = async (input, init = {}) => {
    const url = typeof input === "string" ? input : input.url;
    if (!/(^|\/)api\//.test(url)) return realFetch(input, init);
    try {
      const body = init.body ? JSON.parse(init.body) : {};
      const data = await agent.request(init.method || "GET", url, body);
      return new Response(JSON.stringify(data), { status: 200, headers: { "Content-Type": "application/json" } });
    } catch (error) {
      return new Response(error.message, { status: error.status || 500 });
    }
  };
  return agent;
}
