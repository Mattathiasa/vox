// Installed apps on Windows: Start Menu shortcuts (.lnk/.url) plus config "apps" (name -> exe/URI).
// Port of AppCatalog.find's matching rules.
import fs from "node:fs";
import path from "node:path";
import { words, normalizedPhrase } from "./tokenizer.js";

export function startMenuDirs(env = process.env) {
  const dirs = [];
  if (env.ProgramData) dirs.push(path.join(env.ProgramData, "Microsoft", "Windows", "Start Menu", "Programs"));
  if (env.APPDATA) dirs.push(path.join(env.APPDATA, "Microsoft", "Windows", "Start Menu", "Programs"));
  return dirs;
}

function walk(dir, depth = 0, out = []) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory() && depth < 4) walk(full, depth + 1, out);
    else if (/\.(lnk|url)$/i.test(entry.name)) out.push(full);
  }
  return out;
}

const SKIP = /\b(uninstall|readme|help|documentation|release notes|website|manual)\b/i;

const SPOKEN_ALIASES = {
  "vs code": "visual studio code", vscode: "visual studio code", code: "visual studio code",
  chrome: "google chrome", edge: "microsoft edge", explorer: "file explorer", files: "file explorer",
  settings: "settings", "epic": "epic games launcher", "epic games": "epic games launcher",
  "claude desktop": "claude", whatsapp: "whatsapp", xbox: "xbox",
};

export class AppCatalog {
  constructor(entries) { this.entries = entries; }

  /** @param {Record<string,string>} configured  extra "name": "target" pairs from config.json */
  static scan(configured = {}, dirs = startMenuDirs()) {
    const entries = [];
    const seen = new Set();
    for (const [name, target] of Object.entries(configured)) {
      const key = normalizedPhrase(name);
      if (key && !seen.has(key)) { seen.add(key); entries.push({ name, target, key }); }
    }
    for (const file of dirs.flatMap((d) => walk(d))) {
      const name = path.basename(file).replace(/\.(lnk|url)$/i, "");
      if (SKIP.test(name)) continue;
      const key = normalizedPhrase(name);
      if (key && !seen.has(key)) { seen.add(key); entries.push({ name, target: file, key }); }
    }
    return new AppCatalog(entries.sort((a, b) => a.name.localeCompare(b.name)));
  }

  find(spoken) {
    const list = words(spoken);
    while (list.length && ["the", "my"].includes(list[0])) list.shift();
    while (list.length && ["app", "application", "ide", "editor", "game"].includes(list[list.length - 1])) list.pop();
    if (!list.length) return null;
    let key = list.join(" ");
    if (Object.hasOwn(SPOKEN_ALIASES, key)) key = SPOKEN_ALIASES[key];
    const squashed = key.replace(/ /g, "");
    const exact = this.entries.find((e) => e.key === key);
    if (exact) return exact;
    const joined = this.entries.find((e) => e.key.replace(/ /g, "") === squashed);
    if (joined) return joined;
    if (squashed.length < 3) return null;
    const prefixed = this.entries.filter((e) => e.key.startsWith(key) || e.key.replace(/ /g, "").startsWith(squashed));
    return prefixed.sort((a, b) => a.name.length - b.name.length)[0] ?? null;
  }

  get names() { return this.entries.map((e) => e.name); }
}
