// Port of VoxCore/Config/VoxConfig.swift defaults + a Windows starter config.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { normalizeConfig } from "./defaults.js";

export * from "./defaults.js";


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

/** Owner keeps projects in D:\\Projects on the PC; use it when it exists, else ~/Projects. */
export function defaultProjectsDir(exists = fs.existsSync) {
  return exists("D:\\Projects") ? "D:\\Projects" : "~/Projects";
}

export function starterConfig(projectsDir = defaultProjectsDir()) {
  return { ...WINDOWS_STARTER, tools: WINDOWS_STARTER.tools.map((t) => ({ ...t, defaultDirectory: projectsDir })) };
}

export function configDir() {
  const base = process.env.APPDATA || path.join(os.homedir(), ".config");
  return path.join(base, "Vox");
}

export function loadConfig(file = path.join(configDir(), "config.json")) {
  if (!fs.existsSync(file)) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(starterConfig(), null, 2));
  }
  return { file, config: normalizeConfig(JSON.parse(fs.readFileSync(file, "utf8"))) };
}

export function expandHome(p) {
  if (!p) return p;
  if (p === "~" || p.startsWith("~/") || p.startsWith("~\\")) return path.join(os.homedir(), p.slice(2));
  return p;
}
