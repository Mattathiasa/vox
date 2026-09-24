// Port of VoxCore/Engine/VoxEngine.swift for Windows: executes router actions with
// native terminals (TerminalHost) and Windows desktop control.
import os from "node:os";
import path from "node:path";
import { SessionRouter, HELP_TEXT } from "./router.js";
import { slug } from "./terminal.js";
import { normalizedPhrase } from "./tokenizer.js";
import { describeDuration, evaluateMath, formatNumber } from "./spoken.js";
import { knownSite, urlFromSpoken, searchURL, siteURL, describeCombo } from "./keys.js";
import { expandHome, phrasesOf } from "./config.js";

const ev = (kind, message) => ({ kind, message });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export class VoxEngine {
  /**
   * @param {object} deps
   * @param {object} deps.config   normalized config
   * @param {import('./terminal.js').TerminalHost} deps.terminals
   * @param {object} deps.desktop  WindowsDesktop (or a fake in tests)
   * @param {object} deps.apps     AppCatalog
   */
  constructor({ config, terminals, desktop, apps, pause = sleep, submitDelayMs = 150, focusDelayMs = 800 }) {
    this.config = config;
    this.router = new SessionRouter(config);
    this.terminals = terminals;
    this.desktop = desktop;
    this.apps = apps;
    this.pause = pause;
    this.submitDelayMs = submitDelayMs;
    this.focusDelayMs = focusDelayMs;
    this.size = { cols: 120, rows: 34 };
  }

  get lockedTool() { return this.router.lockedTool; }
  get pendingQuestion() { return this.router.pending?.question ?? null; }
  exitPassThrough() { this.router.unlock(); }

  async handle(text) { return this.run(this.router.handle(text)); }
  async send(text, tool) { return this.run(this.router.sendTo(tool, text)); }

  /** A terminal key button (Enter, Esc, arrows, Ctrl-C…). */
  press(key, tool) {
    if (!this.terminals.has(tool)) return [ev("warning", `${tool} isn't running.`)];
    try { this.terminals.sendKey(tool, key); return []; } catch (error) { return [ev("error", error.message)]; }
  }

  /** Live typing from the phone/Vox window: literal keystrokes, no Enter. */
  type(text, tool) {
    if (!this.terminals.has(tool)) return [ev("warning", `${tool} isn't running.`)];
    try { this.terminals.type(tool, text); return []; } catch (error) { return [ev("error", error.message)]; }
  }

  screens(lines = 150) {
    return this.terminals.list().map((name) => ({ tool: name, text: this.terminals.capture(name, lines), exited: this.terminals.isDead(name) }));
  }

  fit(cols, rows) {
    const c = Math.max(40, Math.min(300, Math.round(cols)));
    const r = Math.max(10, Math.min(120, Math.round(rows)));
    this.size = { cols: c, rows: r };
    let changed = 0;
    for (const name of this.terminals.list()) if (this.terminals.resize(name, c, r)) changed += 1;
    return changed;
  }

  async run(actions) {
    const events = [];
    let needsFocusDelay = false;
    for (const action of actions) {
      if (needsFocusDelay && needsFrontmostApp(action)) {
        await this.pause(this.focusDelayMs);
        needsFocusDelay = false;
      }
      events.push(...(await this.execute(action)));
      needsFocusDelay = action.action === "desktop" && ["openApp", "focusApp"].includes(action.command.type);
    }
    return events;
  }

  async execute(a) {
    switch (a.action) {
      case "launch": return this.launch(a.tool, a.directory, a.prompt);
      case "focus":
        if (!this.terminals.has(a.tool)) {
          this.router.unlock();
          return [ev("warning", `${a.tool} isn't running. Say "run ${a.tool}".`)];
        }
        return [ev("success", `Talking to ${a.tool}. Say "exit" to stop.`)];
      case "send": return this.sendToTool(a.text, a.tool);
      case "kill":
        if (!this.terminals.has(a.tool)) return [ev("info", `${a.tool} wasn't running.`)];
        this.terminals.kill(a.tool);
        return [ev("success", `Killed ${a.tool}.`)];
      case "list": {
        const names = this.terminals.list();
        return [ev("info", names.length ? `Running: ${names.join(", ")}` : "No tools running.")];
      }
      case "interrupt":
        if (!this.terminals.has(a.tool)) return [ev("info", `${a.tool} isn't running.`)];
        this.terminals.interrupt(a.tool);
        return [ev("success", `Interrupted ${a.tool}.`)];
      case "show":
        if (!this.terminals.has(a.tool)) return [ev("warning", `${a.tool} isn't running. Say "run ${a.tool}".`)];
        return [ev("info", `${a.tool}'s screen is in the Vox window. Tap it to type into it.`)];
      case "confirm": return [ev("confirm", a.question)];
      case "feedback": return [ev("info", a.message)];
      case "llm": return [ev("info", `Didn't catch a command in "${a.text}".`)];
      case "desktop": return this.runDesktop(a.command);
      default: return [ev("error", `Unknown action ${a.action}`)];
    }
  }

  async launch(toolName, directory, prompt) {
    const tool = this.config.tools.find((t) => t.name === toolName);
    if (!tool) { this.router.unlock(); return [ev("error", `${toolName} is not in your config.`)]; }
    const events = [];
    if (this.terminals.has(tool.name) && !this.terminals.isDead(tool.name)) {
      events.push(ev("info", `${tool.name} is already running. Talking to it now.`));
    } else {
      if (this.terminals.has(tool.name)) this.terminals.kill(tool.name);
      const cwd = directory ? path.resolve(expandHome(directory)) : os.homedir();
      try {
        await this.terminals.start(tool.name, tool.command, cwd, this.size);
      } catch (error) {
        this.router.unlock();
        return [ev("error", `Couldn't start ${tool.name}: ${error.message}`)];
      }
      events.push(ev("success", `Started ${tool.name}${directory ? ` in ${directory}` : ""}. Talking to it now.`));
      if (prompt) await this.pause(tool.startupDelaySeconds * 1000);
    }
    if (prompt) events.push(...(await this.sendToTool(prompt, tool.name)));
    return events;
  }

  async sendToTool(text, tool) {
    if (!this.terminals.has(tool)) { this.router.unlock(); return [ev("error", `Session ${tool} is not running.`)]; }
    if (this.terminals.isDead(tool)) { this.router.unlock(); return [ev("error", `The program in ${tool} has exited. Say "kill" and run it again.`)]; }
    try {
      this.terminals.type(tool, text);
      await this.pause(this.submitDelayMs);
      this.terminals.submit(tool);
      return [ev("success", `→ ${tool}: ${text}`)];
    } catch (error) {
      return [ev("error", error.message)];
    }
  }

  folder(spoken) {
    const key = normalizedPhrase(spoken);
    const home = os.homedir();
    const standard = {
      home, downloads: path.join(home, "Downloads"), documents: path.join(home, "Documents"), desktop: path.join(home, "Desktop"),
      pictures: path.join(home, "Pictures"), movies: path.join(home, "Videos"), music: path.join(home, "Music"),
      projects: path.join(home, "Projects"),
      applications: path.join(process.env.APPDATA || home, "Microsoft", "Windows", "Start Menu", "Programs"),
    };
    if (Object.hasOwn(standard, key)) return standard[key];
    const project = this.config.projects.find((p) => phrasesOf(p).some((ph) => normalizedPhrase(ph) === key));
    return project ? path.resolve(expandHome(project.path)) : null;
  }

  async runDesktop(c) {
    const d = this.desktop;
    try {
      switch (c.type) {
        case "openApp": {
          const app = this.apps.find(c.name);
          if (!app) {
            const site = knownSite(c.name) ?? urlFromSpoken(c.name);
            if (site) { await d.openURL(site); return [ev("success", `Opened ${new URL(site).host}.`)]; }
            const folder = this.folder(c.name);
            if (folder) { await d.open(folder); return [ev("success", `Opened ${path.basename(folder)} in File Explorer.`)]; }
            return [ev("warning", `No app called "${c.name}" found in the Start menu.`)];
          }
          await d.open(app.target);
          return [ev("success", `Opened ${app.name}.`)];
        }
        case "focusApp": {
          if (await d.focusApp(c.name)) return [ev("success", `Switched to ${c.name}.`)];
          const app = this.apps.find(c.name);
          if (!app) return [ev("warning", `No app called "${c.name}" found.`)];
          await d.open(app.target);
          return [ev("success", `Opened ${app.name}.`)];
        }
        case "quitApp":
          return [(await d.quitApp(c.name)) ? ev("success", `Closed ${c.name}.`) : ev("info", `${c.name} isn't running.`)];
        case "hideApp":
          return [(await d.minimizeApp(c.name)) ? ev("success", `Minimized ${c.name}.`) : ev("info", `${c.name} isn't running.`)];
        case "createNote":
          await d.createNote(c.text);
          return [ev("success", c.text ? `Noted: ${c.text}` : "Opened your notes.")];
        case "webSearch":
          await d.openURL(searchURL(c.query));
          return [ev("success", `Searching for ${c.query}.`)];
        case "openURL": {
          const url = urlFromSpoken(c.spoken);
          if (!url) return [ev("warning", `"${c.spoken}" doesn't look like a web address.`)];
          await d.openURL(url);
          return [ev("success", `Opened ${new URL(url).host}.`)];
        }
        case "typeText":
          await d.typeText(c.text);
          return [ev("success", `Typed: ${c.text}`)];
        case "pressKey":
          if (describeCombo(c.combo) === "control+command+q") { await d.lock(); return [ev("success", "Locked.")]; }
          await d.pressKey(c.combo);
          return [ev("success", `Pressed ${describeCombo(c.combo)}.`)];
        case "volume": {
          await d.volume(c.change);
          const labels = { up: "Volume up.", down: "Volume down.", mute: "Mute toggled.", unmute: "Mute toggled." };
          return [ev("success", labels[c.change] ?? `Volume ${c.change.split(" ")[1]}%.`)];
        }
        case "media":
          await d.media(c.key);
          return [ev("success", { playPause: "Play/pause.", next: "Next track.", previous: "Previous track." }[c.key])];
        case "answer": return [ev("info", await this.answer(c))];
        case "timer":
          d.startTimer(c.seconds, `⏰ ${describeDuration(c.seconds)} timer done.`);
          return [ev("info", `Timer set for ${describeDuration(c.seconds)}.`)];
        case "cancelTimers": {
          const n = d.cancelTimers();
          return [ev("info", n === 0 ? "No timers running." : `Cancelled ${n} timer${n === 1 ? "" : "s"}.`)];
        }
        case "reminder": {
          if (c.seconds) d.startTimer(c.seconds, `⏰ Reminder: ${c.text}`);
          else await d.createNote(`TODO: ${c.text}`);
          return [ev("info", c.seconds ? `I'll remind you to ${c.text} in ${describeDuration(c.seconds)}.` : `Added "${c.text}" to your notes.`)];
        }
        case "openFolder": {
          const folder = this.folder(c.name);
          if (!folder) return [ev("warning", `No folder or project called "${c.name}".`)];
          await d.open(folder);
          return [ev("success", `Opened ${path.basename(folder)} in File Explorer.`)];
        }
        case "openProject": {
          const folder = this.folder(c.project);
          if (!folder) return [ev("warning", `No project called "${c.project}" in your config.`)];
          const app = this.apps.find(c.app);
          if (!app) return [ev("warning", `No app called "${c.app}" found.`)];
          await d.open(app.target, folder);
          return [ev("success", `Opened ${c.project} in ${app.name}.`)];
        }
        case "siteSearch":
          await d.openURL(siteURL(c.site, c.query));
          return [ev("success", `Searching ${c.site} for ${c.query}.`)];
        case "system":
          if (c.action === "screenOff") { await d.screenOff(); return [ev("success", "Screen off.")]; }
          await d.darkMode(c.on);
          return [ev("success", `Dark mode ${c.on === null ? "toggled" : c.on ? "on" : "off"}.`)];
        case "sendMessageToApp": {
          const app = this.apps.find(c.app);
          if (!app) return [ev("warning", `No app called "${c.app}" found.`)];
          await d.open(app.target);
          await this.pause(600);
          const saved = await d.clipboard().catch(() => "");
          await d.setClipboard(c.text);
          await d.pressKey({ key: "v", modifiers: ["command"] });
          await this.pause(150);
          await d.pressKey({ key: "return", modifiers: [] });
          if (saved) await d.setClipboard(saved);
          return [ev("success", `Sent to ${app.name}.`)];
        }
        case "ide":
          return [ev("warning", "IDE terminals aren't wired up on Windows yet (Phase 9 follow-up). Run tools with \"run claude\" instead.")];
        case "safariReadTab":
          return [ev("warning", "Safari isn't on Windows.")];
        default:
          return [ev("warning", `"${c.type}" isn't available on Windows yet.`)];
      }
    } catch (error) {
      return [ev("error", error.message)];
    }
  }

  async answer(c) {
    const now = new Date();
    switch (c.question) {
      case "time": return `It's ${now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}.`;
      case "date": return `Today is ${now.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}.`;
      case "battery": return this.desktop.battery();
      case "clipboard": {
        const text = ((await this.desktop.clipboard()) || "").trim();
        if (!text) return "The clipboard has no text.";
        return text.length > 200 ? `Your clipboard says: ${text.slice(0, 200)}…` : `Your clipboard says: ${text}`;
      }
      case "openApps": {
        const names = await this.desktop.runningApps();
        return names.length ? `Open apps: ${names.join(", ")}.` : "No apps are open.";
      }
      case "calculation": {
        const value = evaluateMath(c.expression);
        return value === null ? "I couldn't work that out." : `That's ${formatNumber(value)}.`;
      }
      default: return "I don't know that one.";
    }
  }

  static get helpText() { return HELP_TEXT; }
}

function needsFrontmostApp(action) {
  return action.action === "desktop" && ["typeText", "pressKey", "createNote", "reminder", "webSearch", "openURL"].includes(action.command.type);
}

export { slug };
