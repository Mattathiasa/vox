// Config defaults and normalization with no Node imports, so the browser demo can use them too.
// Port of VoxConfig.swift's defaults and decoder.

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
