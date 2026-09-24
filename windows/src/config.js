// Port of VoxCore/Config/VoxConfig.swift defaults + a Windows starter config.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

export const DEFAULT_EXIT_PHRASES = ["exit", "done", "unlock", "stop listening", "back to vox", "that's all"];
export const DEFAULT_COMMAND_PREFIXES = ["vox", "hey vox", "computer"];
export const DEFAULT_CONFIRM_PATTERNS = [
  "\\bpush\\b", "\\bdeploy", "\\b(delete|remove|drop|wipe|erase|destroy|truncate)\\b", "\\brm\\b",
  "\\breset\\b.*\\bhard\\b", "\\bforce\\b", "\\b(publish|release)\\b",
];
export const DEFAULT_AFFIRMATIVES = ["yes", "yeah", "yep", "confirm", "do it", "go ahead", "affirmative", "yes please"];

/** Fills defaults exactly like VoxConfig's decoder. */
export function normalizeConfig(raw = {}) {
  return {
    tools: (raw.tools || []).map((t) => ({
      name: t.name, aliases: t.aliases || [], command: t.command,
      defaultDirectory: t.defaultDirectory ?? null, startupDelaySeconds: t.startupDelaySeconds ?? 4,
    })),
    projects: (raw.projects || []).map((p) => ({ name: p.name, aliases: p.aliases || [], path: p.path })),
    exitPhrases: raw.exitPhrases || DEFAULT_EXIT_PHRASES,
    commandPrefixes: raw.commandPrefixes || DEFAULT_COMMAND_PREFIXES,
    confirmPatterns: raw.confirmPatterns || DEFAULT_CONFIRM_PATTERNS,
    affirmativePhrases: raw.affirmativePhrases || DEFAULT_AFFIRMATIVES,
    shell: raw.shell || "powershell.exe",
    speakFeedback: raw.speakFeedback ?? true,
    wakeWord: raw.wakeWord || { enabled: false, phrases: ["balcha"] },
    remote: { port: 7788, allowLAN: false, ...(raw.remote || {}) },
    apps: raw.apps || {},
  };
}

export const phrasesOf = (item) => [item.name, ...(item.aliases || [])];

export const WINDOWS_STARTER = {
  tools: [
    { name: "claude", aliases: ["claude code", "cloud code", "clod"], command: "claude", defaultDirectory: "~/Projects" },
    { name: "freebuff", aliases: ["free buff", "freebuf", "free buf", "free bath"], command: "freebuff", defaultDirectory: "~/Projects" },
    { name: "kilo", aliases: ["kilo code", "kilocode", "keylo", "kilo cli"], command: "kilo", defaultDirectory: "~/Projects" },
    { name: "codex", aliases: ["codecs", "code x"], command: "codex", defaultDirectory: "~/Projects" },
    { name: "gemini", aliases: ["gemini cli", "jiminy"], command: "gemini", defaultDirectory: "~/Projects" },
  ],
  projects: [],
  remote: { port: 7788, allowLAN: false },
  apps: {
    "steam": "steam://open/main",
    "epic games": "com.epicgames.launcher://",
    "discord": "discord://",
    "xbox": "xbox:",
    "settings": "ms-settings:",
    "file explorer": "explorer.exe",
    "explorer": "explorer.exe",
    "notepad": "notepad.exe",
    "calculator": "calc.exe",
    "task manager": "taskmgr.exe",
  },
};

export function configDir() {
  const base = process.env.APPDATA || path.join(os.homedir(), ".config");
  return path.join(base, "Vox");
}

export function loadConfig(file = path.join(configDir(), "config.json")) {
  if (!fs.existsSync(file)) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(WINDOWS_STARTER, null, 2));
  }
  return { file, config: normalizeConfig(JSON.parse(fs.readFileSync(file, "utf8"))) };
}

export function expandHome(p) {
  if (!p) return p;
  if (p === "~" || p.startsWith("~/") || p.startsWith("~\\")) return path.join(os.homedir(), p.slice(2));
  return p;
}
