// Native terminals for CLI tools (Windows ConPTY via node-pty), the Windows
// counterpart of TmuxAdapter. Each tool runs in its own pseudo-terminal; a
// headless xterm keeps its screen so the phone/Vox window can show it.
import xterm from "@xterm/headless";

const { Terminal } = xterm;

/** tmux key names (what the web app sends) -> bytes for the terminal. Anything else is refused. */
export const KEY_SEQUENCES = {
  Enter: "\r", Escape: "\x1b", Up: "\x1b[A", Down: "\x1b[B", Right: "\x1b[C", Left: "\x1b[D",
  Tab: "\t", BTab: "\x1b[Z", "C-c": "\x03", "C-d": "\x04", "C-l": "\x0c",
  BSpace: "\x7f", DC: "\x1b[3~", Home: "\x1b[H", End: "\x1b[F", PPage: "\x1b[5~", NPage: "\x1b[6~",
};

/** "Free Buff!" -> "free-buff" (same as SessionNaming minus the "vox-" prefix). */
export function slug(tool) {
  let out = "";
  for (const ch of tool.toLowerCase()) {
    if (/[a-z0-9_-]/.test(ch)) out += ch;
    else if (!out.endsWith("-")) out += "-";
  }
  return out.replace(/^-+|-+$/g, "");
}

async function loadPty() {
  try {
    return await import("@lydell/node-pty");
  } catch (error) {
    throw new Error(`Terminal support isn't installed (node-pty): ${error.message}. Run Install-Vox.cmd again.`);
  }
}

export class TerminalHost {
  /** @param {{shell?: string, spawn?: Function, scrollback?: number}} options  spawn(file, args, opts) -> pty-like (for tests) */
  constructor({ shell = "cmd.exe", spawn = null, scrollback = 2000 } = {}) {
    this.shell = shell;
    this.spawnImpl = spawn;
    this.scrollback = scrollback;
    this.sessions = new Map(); // slug -> { pty, term, exited, cols, rows }
  }

  has(tool) { return this.sessions.has(slug(tool)); }
  isDead(tool) { return this.sessions.get(slug(tool))?.exited ?? false; }
  list() { return [...this.sessions.keys()]; }

  async start(tool, command, cwd, { cols = 120, rows = 34 } = {}) {
    const name = slug(tool);
    const spawn = this.spawnImpl ?? (await loadPty()).spawn;
    // The command string comes only from config.json (security invariant 2); spoken text never gets here.
    const [file, args] = this.shellArgs(command);
    const pty = spawn(file, args, { name: "xterm-256color", cols, rows, cwd, env: { ...process.env, TERM: "xterm-256color" } });
    const term = new Terminal({ cols, rows, scrollback: this.scrollback, allowProposedApi: true });
    const session = { pty, term, exited: false, cols, rows };
    pty.onData((data) => term.write(data));
    pty.onExit(() => { session.exited = true; term.write("\r\n[process exited]\r\n"); });
    this.sessions.set(name, session);
  }

  shellArgs(command) {
    const shell = this.shell.toLowerCase();
    if (shell.includes("powershell") || shell.includes("pwsh")) return [this.shell, ["-NoLogo", "-Command", command]];
    // cmd.exe: pass ONE raw command line (node-pty uses a string verbatim on Windows). An args array
    // would get C-style \" escaping, which cmd doesn't understand, so commands containing quotes broke.
    // /s + outer quotes = cmd runs exactly the text between them.
    if (shell.endsWith("cmd.exe") || shell === "cmd") return [this.shell, `/d /s /c "${command}"`];
    return [this.shell, ["-lc", command]]; // bash/zsh (tests, WSL)
  }

  get(tool) {
    const session = this.sessions.get(slug(tool));
    if (!session) throw new Error(`Session ${tool} is not running.`);
    return session;
  }

  type(tool, text) {
    const s = this.get(tool);
    if (s.exited) throw new Error(`The program in ${tool} has exited. Say "kill" and run it again.`);
    s.pty.write(text);
  }

  submit(tool) { this.type(tool, "\r"); }
  interrupt(tool) { this.type(tool, "\x03"); }

  sendKey(tool, key) {
    if (!Object.hasOwn(KEY_SEQUENCES, key)) throw new Error(`key not allowed: ${key}`);
    this.type(tool, KEY_SEQUENCES[key]);
  }

  resize(tool, cols, rows) {
    const s = this.get(tool);
    if (s.cols === cols && s.rows === rows) return false;
    if (!s.exited) s.pty.resize(cols, rows);
    s.term.resize(cols, rows);
    s.cols = cols;
    s.rows = rows;
    return true;
  }

  kill(tool) {
    const name = slug(tool);
    const s = this.sessions.get(name);
    if (!s) return false;
    try { if (!s.exited) s.pty.kill(); } catch { /* already gone */ }
    s.term.dispose();
    this.sessions.delete(name);
    return true;
  }

  /** Kills every session (shutdown, tests). */
  killAll() {
    for (const name of [...this.sessions.keys()]) this.kill(name);
  }

  /** Last `lines` lines of screen + scrollback, trailing blanks trimmed (like VoxEngine.tidy). */
  capture(tool, lines = 150) {
    const { term } = this.get(tool);
    const buffer = term.buffer.active;
    const out = [];
    const start = Math.max(0, buffer.length - lines);
    for (let y = start; y < buffer.length; y += 1) out.push(buffer.getLine(y)?.translateToString(true) ?? "");
    while (out.length && out[out.length - 1] === "") out.pop();
    return out.join("\n");
  }

  /** Waits until pending writes reach the headless terminal (tests). */
  flush(tool) {
    const { term } = this.get(tool);
    return new Promise((resolve) => term.write("", resolve));
  }
}
