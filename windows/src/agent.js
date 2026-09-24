// What the Remote protocol exposes: the engine plus log, history and busy state
// (the Windows counterpart of the Mac's AppState).
import os from "node:os";

export class Agent {
  constructor({ engine, config, platform = "windows", host = os.hostname() }) {
    this.engine = engine;
    this.config = config;
    this.platform = platform;
    this.host = host;
    this.log = [];
    this.history = [];
    this.busy = 0;
  }

  append(kind, text) {
    this.log.push({ kind, text, time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }) });
    if (this.log.length > 300) this.log.splice(0, this.log.length - 300);
  }

  record(command, events, { spoken = false, source = "local" } = {}) {
    const order = ["error", "confirm", "warning", "info", "success"];
    const worst = order.find((kind) => events.some((e) => e.kind === kind)) ?? "info";
    const reply = events.find((e) => e.kind === worst)?.message ?? "";
    this.history.unshift({ command, kind: worst, reply, spoken, source });
    this.history.length = Math.min(this.history.length, 8);
  }

  async command(text, { spoken = false, source = "local" } = {}) {
    const trimmed = String(text || "").trim();
    if (!trimmed) return [];
    this.append("info", `${source === "phone" ? "📱 " : ""}› ${trimmed}`);
    this.busy += 1;
    try {
      const events = await this.engine.handle(trimmed);
      for (const e of events) this.append(e.kind, e.message);
      this.record(trimmed, events, { spoken, source });
      return events;
    } finally {
      this.busy -= 1;
    }
  }

  async sendToTool(tool, text) {
    const trimmed = String(text || "").trim();
    if (!trimmed) return [];
    this.append("info", `› ${tool}: ${trimmed}`);
    const events = await this.engine.send(trimmed, tool);
    for (const e of events) this.append(e.kind, e.message);
    return events;
  }

  alert(message) {
    this.append("success", message);
    this.history.unshift({ command: "timer", kind: "success", reply: message, spoken: false, source: "local" });
    this.history.length = Math.min(this.history.length, 8);
  }

  state(lines = 60) {
    return {
      name: "Vox",
      host: this.host,
      platform: this.platform,
      version: 1,
      lockedTool: this.engine.lockedTool,
      pendingQuestion: this.engine.pendingQuestion,
      busy: this.busy > 0,
      wake: { enabled: false, name: "Balcha", phrases: this.config.wakeWord?.phrases || [] },
      tools: this.config.tools.map((t) => t.name),
      screens: this.engine.screens(lines),
      history: this.history,
      log: this.log.slice(-60),
    };
  }
}
