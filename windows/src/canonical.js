// One-line form of router actions, shared with Swift (VoxCore/Remote/GrammarCanonical.swift)
// so shared/grammar-cases.json can check both grammars.
import { describeCombo } from "./keys.js";

const f = (...parts) => parts.map((p) => (p === null || p === undefined ? "" : String(p))).join("|");

export function canonicalAction(a) {
  switch (a.action) {
    case "launch": return f("launch", a.tool, a.directory, a.prompt);
    case "focus": return f("focus", a.tool);
    case "send": return f("send", a.tool, a.text);
    case "kill": return f("kill", a.tool);
    case "list": return "list";
    case "interrupt": return f("interrupt", a.tool);
    case "show": return f("show", a.tool);
    case "confirm": return f("confirm", a.question);
    case "feedback": return a.help ? "feedback|<help>" : f("feedback", a.message);
    case "llm": return f("llm", a.text);
    case "desktop": return `desktop:${canonicalCommand(a.command)}`;
    default: return `?${a.action}`;
  }
}

export function canonicalCommand(c) {
  switch (c.type) {
    case "openApp": case "quitApp": case "focusApp": case "hideApp": return f(c.type, c.name);
    case "createNote": case "typeText": return f(c.type, c.text);
    case "webSearch": return f(c.type, c.query);
    case "openURL": return f(c.type, c.spoken);
    case "pressKey": return f(c.type, describeCombo(c.combo));
    case "volume": return f(c.type, c.change);
    case "media": return f(c.type, c.key);
    case "answer": return c.question === "calculation" ? f(c.type, "calculation", c.expression) : f(c.type, c.question);
    case "timer": return f(c.type, c.seconds);
    case "cancelTimers": return "cancelTimers";
    case "reminder": return f(c.type, c.text, c.seconds);
    case "openFolder": return f(c.type, c.name);
    case "openProject": return f(c.type, c.project, c.app);
    case "siteSearch": return f(c.type, c.site, c.query);
    case "system": return c.action === "screenOff" ? "system|screenOff" : f("system", "darkMode", c.on === null ? "toggle" : c.on ? "on" : "off");
    case "safariReadTab": return "safariReadTab";
    case "sendMessageToApp": return f(c.type, c.app, c.text);
    case "ide": return `ide:${canonicalIDE(c.ide)}`;
    default: return `?${c.type}`;
  }
}

function canonicalIDE(i) {
  switch (i.op) {
    case "openTerminals": return f("openTerminals", i.count, i.commands.join(","));
    case "send": return f("send", i.target, i.text, i.submit ? "submit" : "type");
    case "closeTerminals": return "closeTerminals";
    case "chat": return f("chat", i.message, i.submit ? "submit" : "type");
    case "openFile": return f("openFile", i.path);
    case "openFolder": return f("openFolder", i.path);
    case "runTask": return f("runTask", i.name);
    default: return `?${i.op}`;
  }
}
