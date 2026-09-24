// Vox IDE bridge: lets the Vox voice assistant open split terminals and send
// text to them in this VS Code–based IDE (Antigravity, Kiro, VS Code, Cursor…).
//
// Security:
// - The server listens on 127.0.0.1 only, on a random port.
// - Every request must carry a random token that is written, with 0600
//   permissions, to ~/Library/Application Support/Vox/bridges/<ide>-<pid>.json.
//   Only processes running as you can read it.
'use strict';

const vscode = require('vscode');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const BRIDGE_DIR = path.join(os.homedir(), 'Library', 'Application Support', 'Vox', 'bridges');
const MAX_TERMINALS = 8;

let server;
let infoFile;
let info;

/** Terminals Vox created, in order. "terminal 1" is voxTerminals[0]. */
const voxTerminals = [];
/** Terminals Vox already sent a command to ("one of the terminals" picks an unused one). */
const used = new WeakSet();
let nextNumber = 1;

function activate(context) {
  const token = crypto.randomBytes(24).toString('hex');
  const ide = vscode.env.appName || 'IDE';
  const slug = ide.toLowerCase().replace(/[^a-z0-9]+/g, '-');

  server = http.createServer((req, res) => handle(req, res, token));
  server.listen(0, '127.0.0.1', () => {
    const port = server.address().port;
    fs.mkdirSync(BRIDGE_DIR, { recursive: true });
    infoFile = path.join(BRIDGE_DIR, `${slug}-${process.pid}.json`);
    info = {
      ide,
      port,
      token,
      pid: process.pid,
      workspace: workspacePath(),
      focusedAt: Date.now() / 1000
    };
    writeInfo();
  });

  context.subscriptions.push(
    vscode.window.onDidChangeWindowState((state) => {
      if (state.focused && info) {
        info.focusedAt = Date.now() / 1000;
        writeInfo();
      }
    }),
    vscode.workspace.onDidChangeWorkspaceFolders(() => {
      if (info) {
        info.workspace = workspacePath();
        writeInfo();
      }
    }),
    vscode.window.onDidCloseTerminal((terminal) => {
      const index = voxTerminals.indexOf(terminal);
      if (index >= 0) voxTerminals.splice(index, 1);
    }),
    { dispose: cleanup }
  );
  process.on('exit', cleanup);
}

function deactivate() {
  cleanup();
}

function cleanup() {
  try { if (infoFile) fs.unlinkSync(infoFile); } catch (_) { /* already gone */ }
  try { if (server) server.close(); } catch (_) { /* ignore */ }
}

function writeInfo() {
  if (!infoFile || !info) return;
  const tmp = infoFile + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(info), { mode: 0o600 });
  fs.renameSync(tmp, infoFile);
}

function workspacePath() {
  const folders = vscode.workspace.workspaceFolders;
  return folders && folders.length ? folders[0].uri.fsPath : null;
}

// ---------------------------------------------------------------- HTTP

function handle(req, res, token) {
  if (req.method !== 'POST' || req.url !== '/command') {
    return reply(res, 404, { ok: false, message: 'not found' });
  }
  let body = '';
  req.on('data', (chunk) => {
    body += chunk;
    if (body.length > 64 * 1024) req.destroy();
  });
  req.on('end', async () => {
    let msg;
    try { msg = JSON.parse(body); } catch (_) { return reply(res, 400, { ok: false, message: 'bad json' }); }
    if (!safeEqual(String(msg.token || ''), token)) {
      return reply(res, 403, { ok: false, message: 'bad token' });
    }
    try {
      const result = await run(msg);
      reply(res, 200, Object.assign({ ok: true, ide: vscode.env.appName }, result));
    } catch (error) {
      reply(res, 200, { ok: false, ide: vscode.env.appName, message: String((error && error.message) || error) });
    }
  });
}

function safeEqual(a, b) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function reply(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

// ---------------------------------------------------------------- Actions

async function run(msg) {
  switch (msg.action) {
    case 'ping':
      return { message: 'pong', terminals: voxTerminals.length, workspace: workspacePath() };

    case 'openTerminals':
      return openTerminals(Number(msg.count) || 1, Array.isArray(msg.commands) ? msg.commands : [], msg.cwd);

    case 'send':
      return send(msg.terminal, String(msg.text || ''), msg.submit !== false);

    case 'list':
      return { terminals: voxTerminals.map((t) => t.name) };

    case 'closeTerminals': {
      const count = voxTerminals.length;
      voxTerminals.slice().forEach((t) => t.dispose());
      voxTerminals.length = 0;
      nextNumber = 1;
      return { message: count ? `Closed ${count} terminal${count === 1 ? '' : 's'}.` : 'No Vox terminals were open.' };
    }

    case 'focusTerminal': {
      const terminal = pick(msg.terminal, false);
      if (!terminal) throw new Error('No such terminal.');
      terminal.show(false);
      return { message: `Showing ${terminal.name}.` };
    }

    case 'chat':
      return chat(String(msg.message || ''), msg.submit !== false);

    case 'openFile':
      return openFileOrFolder(vscode.Uri.file(resolvePath(String(msg.path || ''))), false);

    case 'openFolder':
      return openFileOrFolder(vscode.Uri.file(resolvePath(String(msg.path || ''))), true);

    case 'runTask':
      return runTask(String(msg.name || ''));

    default:
      throw new Error(`Unknown action: ${msg.action}`);
  }
}

function openTerminals(count, commands, cwd) {
  count = Math.max(1, Math.min(count, MAX_TERMINALS - voxTerminals.length));
  if (count <= 0) throw new Error(`Vox already has ${voxTerminals.length} terminals open.`);
  const options = cwd || workspacePath() ? { cwd: cwd || workspacePath() } : {};

  const created = [];
  let parent;
  for (let i = 0; i < count; i++) {
    const name = `Vox ${nextNumber++}`;
    // The first terminal goes in the panel; the rest split beside it.
    const location = parent ? { parentTerminal: parent } : vscode.TerminalLocation.Panel;
    const terminal = vscode.window.createTerminal(Object.assign({ name, location }, options));
    if (!parent) parent = terminal;
    created.push(terminal);
    voxTerminals.push(terminal);
  }
  parent.show(false);

  const ran = [];
  commands.forEach((command, i) => {
    if (command && created[i]) {
      created[i].sendText(command, true);
      used.add(created[i]);
      ran.push(`${created[i].name}: ${command}`);
    }
  });

  const first = voxTerminals.length - created.length + 1;
  return {
    message: `Opened ${created.length} terminal${created.length === 1 ? '' : 's'}` +
      (ran.length ? ` — ${ran.join(', ')}` : '') + '.',
    terminals: created.map((t) => t.name),
    first
  };
}

/** target: 1-based number, or null/undefined for "any unused one". */
function pick(target, preferUnused) {
  if (typeof target === 'number') return voxTerminals[target - 1];
  if (preferUnused) {
    const free = voxTerminals.find((t) => !used.has(t));
    if (free) return free;
  }
  return voxTerminals[0];
}

function send(target, text, submit) {
  if (!text) throw new Error('Nothing to send.');
  let terminal = pick(target, true);
  if (!terminal && typeof target === 'number') {
    throw new Error(`There is no terminal ${target}. Vox has ${voxTerminals.length} open.`);
  }
  if (!terminal) {
    openTerminals(1, []);
    terminal = voxTerminals[voxTerminals.length - 1];
  }
  terminal.show(false);
  terminal.sendText(text, submit);
  used.add(terminal);
  const number = voxTerminals.indexOf(terminal) + 1;
  return { message: `${submit ? 'Ran' : 'Typed'} “${text}” in terminal ${number}.`, terminal: number };
}

/**
 * Sends a prompt to the IDE's AI chat, dispatching to the right command
 * based on vscode.env.appName. Supports VS Code, Antigravity, and Kiro.
 * https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/chat/browser/actions/chatActions.ts
 */
async function chat(query, submit) {
  if (!query) throw new Error('No message.');
  const ide = (vscode.env.appName || '').toLowerCase();

  if (ide.includes('kiro')) {
    // Kiro: kiro.chat.sendMessage supports submit in one call.
    await vscode.commands.executeCommand('kiro.chat.sendMessage', {
      message: query,
      options: { focus: true, submit: true }
    });
    // If submit was false, Kiro auto-submits — fall back to typing only.
    if (!submit) {
      await vscode.commands.executeCommand('kiro.chat.sendMessage',
        { message: query, options: { focus: true, submit: false } });
    }
    return { message: `Sent to Kiro chat.` };
  }

  if (ide.includes('antigravity')) {
    // Antigravity: antigravity.sendTextToChat(showInChat, query) fills the box.
    await vscode.commands.executeCommand('antigravity.sendTextToChat', true, query);
    if (submit) {
      await vscode.commands.executeCommand('workbench.action.chat.submit');
    }
    return { message: `Sent to Antigravity chat.` };
  }

  // VS Code (and Cursor, Codium, Windsurf — all use the standard chat API).
  await vscode.commands.executeCommand('workbench.action.chat.open', { query });
  if (submit) {
    await vscode.commands.executeCommand('workbench.action.chat.submit');
  }
  return { message: `Sent to chat.` };
}

/**
 * Resolves a spoken path to an absolute filesystem path.
 * Relative paths resolve against the workspace root; tilde expands to home.
 */
function resolvePath(spoken) {
  if (!spoken) throw new Error('No path.');
  if (spoken.startsWith('~/')) {
    return require('os').homedir() + spoken.slice(1);
  }
  const ws = workspacePath();
  if (ws && !path.isAbsolute(spoken)) {
    return path.join(ws, spoken);
  }
  return spoken;
}

/**
 * Opens a file or folder in the IDE.
 */
async function openFileOrFolder(uri, isFolder) {
  if (isFolder) {
    // vscode.openFolder opens in a new window by default in VS Code.
    await vscode.commands.executeCommand('vscode.openFolder', uri, { preview: false });
    return { message: `Opened folder: ${uri.fsPath}.` };
  }
  await vscode.window.showTextDocument(uri, { preview: false });
  return { message: `Opened file: ${uri.fsPath}.` };
}

/**
 * Runs a named task from the IDE's tasks.json.
 */
async function runTask(name) {
  if (!name) throw new Error('No task name.');
  const tasks = await vscode.tasks.fetchTasks();
  const task = tasks.find((t) =>
    t.name.toLowerCase() === name.toLowerCase() ||
    t.detail?.toLowerCase().includes(name.toLowerCase())
  );
  if (!task) throw new Error(`No task called "${name}" found.`);
  await vscode.tasks.executeTask(task);
  return { message: `Ran task: ${task.name}.` };
}

module.exports = { activate, deactivate };
