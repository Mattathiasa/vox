// Port of VoxCore/Routing/SessionRouter.swift: pure state machine, text in, actions out.
import { CommandParser } from "./parser.js";
import { SafetyPolicy } from "./safety.js";

// "claude@chirp" (a session of claude in the chirp project, 12.4) -> "claude in chirp".
const spoken = (instance) => instance.replace("@", " in ");

export const HELP_TEXT = `Apps: open / close / switch to steam · open discord · open downloads
Web: search for … · search youtube for … · play … on youtube · go to github dot com
Keys: close tab · new tab · copy · paste · undo · save · scroll down · go back · lock screen
Type: type … and press enter · press control s
Media: play · pause · next song · volume up · mute · set volume to 30
Ask: what time is it · what's the date · battery · what's 12 times 8 · read clipboard · what apps are open
Do: set a timer for 5 minutes · remind me to … in 10 minutes · dark mode
Tools: run claude · tell kilo to … · exit · interrupt · restart freebuff · what's running
Tool keys: approve · always allow · deny · option 2 · press escape · shift tab · arrow down twice · press enter in claude
Read back: what did claude say · read the last answer · read claude`;

export class SessionRouter {
  constructor(config) {
    this.config = config;
    this.parser = new CommandParser(config);
    this.safety = new SafetyPolicy(config.confirmPatterns);
    this.lockedTool = null;
    this.pending = null; // { question, actions }
  }

  unlock() { this.lockedTool = null; }
  cancelPending() { this.pending = null; }

  handle(text) {
    const trimmed = text.trim();
    if (!trimmed) return [];
    if (this.pending) {
      const held = this.pending;
      this.pending = null;
      if (this.parser.isAffirmative(trimmed)) return this.release(held.actions);
      return [{ action: "feedback", message: "Cancelled." }];
    }
    if (this.lockedTool) {
      const tool = this.lockedTool;
      if (this.parser.isExit(trimmed)) {
        this.lockedTool = null;
        return [{ action: "feedback", message: `Stopped talking to ${spoken(tool)}. ${spoken(tool)} is still running.` }];
      }
      if (this.parser.isInterrupt(trimmed)) return [{ action: "interrupt", tool }];
      // "press escape", "shift tab", "approve": keys for the tool, not text.
      const keys = this.parser.toolKeys(trimmed);
      if (keys) return [{ action: "keys", tool: keys.tool ?? tool, keys: keys.keys }];
      const read = this.parser.readRequest(trimmed);
      if (read) return [{ action: "read", tool: read.tool ?? tool }];
      const command = this.parser.strippingPrefix(trimmed);
      if (command !== null) {
        if (command === "") return [{ action: "feedback", message: "Listening for a command." }];
        return this.handleCommand(command);
      }
      return this.guarded([{ action: "send", tool, text: trimmed }], trimmed, `Send to ${spoken(tool)}: "${trimmed}"?`);
    }
    return this.handleCommand(trimmed);
  }

  /** Config entry for a tool or an instance ("claude@chirp" -> claude). */
  tool(name) { const base = name.split("@")[0]; return this.config.tools.find((t) => t.name === base) || null; }
  project(name) { return this.config.projects.find((p) => p.name === name) || null; }

  handleCommand(text) {
    const intent = this.parser.parse(text);
    switch (intent.type) {
      case "launch": {
        const tool = this.tool(intent.tool);
        if (!tool) return [{ action: "feedback", message: `${intent.tool} is not in your config.` }];
        let directory = tool.defaultDirectory;
        if (intent.project) directory = this.project(intent.project)?.path ?? directory;
        // In a project it's its own session ("claude@chirp"), so claude elsewhere keeps running (12.4).
        const instance = intent.project ? `${tool.name}@${intent.project}` : tool.name;
        const action = { action: "launch", tool: instance, directory: directory ?? null, prompt: intent.prompt ?? null };
        if (!intent.prompt) return this.release([action]);
        return this.guarded([action], intent.prompt, `Start ${tool.name} and send: "${intent.prompt}"?`);
      }
      case "focus": return this.release([{ action: "focus", tool: intent.tool }]);
      case "kill": return this.hold([{ action: "kill", tool: intent.tool }], `Kill the ${spoken(intent.tool)} session? Anything it is doing will stop.`);
      case "list": return [{ action: "list" }];
      case "desktop": {
        const actions = intent.commands.map((command) => ({ action: "desktop", command }));
        if (intent.unparsed) actions.push({ action: "feedback", message: `Didn't understand "${intent.unparsed}".` });
        const typed = intent.commands.flatMap((c) => {
          if (c.type === "typeText") return [c.text];
          if (c.type === "ide" && c.ide.op === "send") return [c.ide.text];
          if (c.type === "ide" && c.ide.op === "openTerminals") return c.ide.commands;
          return [];
        }).join(" ");
        if (typed && this.safety.needsConfirmation(typed)) return this.hold(actions, `Type "${typed}" into the front app?`);
        return this.release(actions);
      }
      case "cancel": return [{ action: "feedback", message: "OK." }];
      case "interrupt": {
        const target = intent.tool ?? this.lockedTool;
        if (!target) return [{ action: "feedback", message: 'Not talking to any tool. Say "interrupt freebuff".' }];
        return [{ action: "interrupt", tool: target }];
      }
      case "restart": {
        const tool = this.tool(intent.tool);
        if (!tool) return [{ action: "feedback", message: `${intent.tool} is not in your config.` }];
        const project = intent.tool.includes("@") ? this.project(intent.tool.split("@")[1]) : null;
        const directory = project?.path ?? tool.defaultDirectory ?? null;
        return this.hold([{ action: "kill", tool: intent.tool }, { action: "launch", tool: intent.tool, directory, prompt: null }],
          `Restart ${spoken(intent.tool)}? Whatever it's doing will stop.`);
      }
      case "show": return [{ action: "show", tool: intent.tool }];
      case "toolKeys": {
        const target = intent.tool ?? this.lockedTool;
        if (!target) return [{ action: "feedback", message: 'Not talking to any tool. Say "approve claude" or "press escape in claude".' }];
        return [{ action: "keys", tool: target, keys: intent.keys }];
      }
      case "readOutput": {
        const target = intent.tool ?? this.lockedTool;
        if (!target) return [{ action: "feedback", message: 'Not talking to any tool. Say "what did claude say".' }];
        return [{ action: "read", tool: target }];
      }
      case "tell": return this.sendTo(intent.tool, intent.text);
      case "help": return [{ action: "feedback", message: HELP_TEXT, help: true }];
      case "exit":
        if (!this.lockedTool) return [{ action: "feedback", message: "Not talking to any tool." }];
        this.lockedTool = null;
        return [{ action: "feedback", message: "Back to commands." }];
      case "unknownTool": return [{ action: "feedback", message: `No tool called "${intent.spoken}" in your config.` }];
      case "unknownProject": return [{ action: "feedback", message: `No project called "${intent.spoken}" in your config.` }];
      default: return [{ action: "llm", text }];
    }
  }

  /** Text for one tool without switching to it (voice "tell X to …", the terminal's command box). */
  sendTo(tool, text) {
    const trimmed = text.trim();
    if (!trimmed) return [];
    if (!this.tool(tool)) return [{ action: "feedback", message: `${tool} is not in your config.` }];
    return this.guarded([{ action: "send", tool, text: trimmed }], trimmed, `Send to ${spoken(tool)}: "${trimmed}"?`);
  }

  guarded(actions, text, question) {
    return this.safety.needsConfirmation(text) ? this.hold(actions, question) : this.release(actions);
  }

  hold(actions, question) {
    this.pending = { question, actions };
    return [{ action: "confirm", question: `${question} Say yes to confirm.` }];
  }

  release(actions) {
    for (const a of actions) {
      if (a.action === "launch" || a.action === "focus") this.lockedTool = a.tool;
      else if (a.action === "kill" && this.lockedTool === a.tool) this.lockedTool = null;
    }
    return actions;
  }
}
