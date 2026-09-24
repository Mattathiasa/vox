// Vox for Windows: starts the agent and opens its window.
//   node src/main.js            normal start
//   node src/main.js --no-window   server only
//   node src/main.js --demo     any OS: fake desktop, bash terminals (for trying the UI)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile, spawn } from "node:child_process";
import QRCode from "qrcode";
import { loadConfig, configDir } from "./config.js";
import { TerminalHost } from "./terminal.js";
import { AppCatalog } from "./apps-win.js";
import { WindowsDesktop } from "./desktop-win.js";
import { VoxEngine } from "./engine.js";
import { Agent } from "./agent.js";
import { createServer, newPairingCode } from "./server.js";

const args = new Set(process.argv.slice(2));
const demo = args.has("--demo");
const { file: configFile, config } = loadConfig(process.env.VOX_CONFIG || undefined);

// Pairing code: %APPDATA%\Vox\remote-token (only readable by you on a normal Windows profile).
const tokenFile = path.join(configDir(), "remote-token");
if (!fs.existsSync(tokenFile)) fs.writeFileSync(tokenFile, newPairingCode(), { mode: 0o600 });
let code = fs.readFileSync(tokenFile, "utf8").trim();
if (args.has("--new-code")) { code = newPairingCode(); fs.writeFileSync(tokenFile, code, { mode: 0o600 }); }

let agent;
const desktop = demo ? demoDesktop() : new WindowsDesktop({ apps: null, onAlert: (m) => agent?.alert(m) });
const apps = demo ? new AppCatalog([{ name: "Steam", target: "steam://open/main", key: "steam" }]) : AppCatalog.scan(config.apps);
const terminals = new TerminalHost({ shell: demo ? "/bin/bash" : (config.shell === "powershell.exe" ? "cmd.exe" : config.shell) });
const engine = new VoxEngine({ config, terminals, desktop, apps });
agent = new Agent({ engine, config, platform: demo ? "windows" : "windows" });

const port = Number(process.env.VOX_PORT || config.remote.port || 7788);
const host = config.remote.allowLAN ? "0.0.0.0" : "127.0.0.1";

function addresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) if (a.family === "IPv4" && !a.internal) out.push(a.address);
  }
  return out;
}

function tailscaleName() {
  return new Promise((resolve) => {
    execFile("tailscale", ["status", "--json"], { timeout: 3000, windowsHide: true }, (error, stdout) => {
      if (error) return resolve(null);
      try { resolve(JSON.parse(stdout).Self?.DNSName?.replace(/\.$/, "") || null); } catch { resolve(null); }
    });
  });
}

async function pairing() {
  const urls = [];
  const ts = await tailscaleName();
  if (ts) urls.push({ label: "Tailscale (HTTPS, voice works)", url: `https://${ts}/#pair=${code}` });
  if (config.remote.allowLAN) for (const ip of addresses()) urls.push({ label: "Home Wi-Fi", url: `http://${ip}:${port}/#pair=${code}` });
  const best = urls[0]?.url ?? `http://localhost:${port}/#pair=${code}`;
  return { code, urls, qrSvg: await QRCode.toString(best, { type: "svg", margin: 1 }), tailscale: Boolean(ts),
    hint: ts ? "" : "Install Tailscale on this PC and your phone, then run Remote-Tailscale.cmd for an HTTPS link." };
}

const server = createServer({ agent, code: () => code, pairing });
server.listen(port, host, async () => {
  const local = `http://localhost:${port}/#pair=${code}`;
  console.log(`Vox for Windows is running.\n  Config: ${configFile}\n  This PC: ${local}`);
  const info = await pairing();
  for (const u of info.urls) console.log(`  ${u.label}: ${u.url}`);
  if (info.hint) console.log(`  ${info.hint}`);
  if (!args.has("--no-window") && process.platform === "win32") openWindow(local);
});

for (const signal of ["SIGINT", "SIGTERM", "SIGBREAK"]) {
  process.on(signal, () => { terminals.killAll(); process.exit(0); });
}

function openWindow(url) {
  // Edge/Chrome "app" window: looks like a normal app, and the mic works on localhost.
  const candidates = [
    path.join(process.env["ProgramFiles(x86)"] || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramFiles || "", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramFiles || "", "Google", "Chrome", "Application", "chrome.exe"),
  ];
  const browser = candidates.find((p) => p && fs.existsSync(p));
  const profile = path.join(configDir(), "window-profile");
  if (browser) spawn(browser, [`--app=${url}`, `--user-data-dir=${profile}`, "--window-size=1280,860"], { detached: true, stdio: "ignore" }).unref();
  else spawn("cmd.exe", ["/c", "start", "", url], { detached: true, stdio: "ignore" }).unref();
}

function demoDesktop() {
  const ok = async () => {};
  return { open: ok, openURL: ok, pressKey: ok, typeText: ok, quitApp: async () => true, focusApp: async () => true,
    minimizeApp: async () => true, volume: ok, media: ok, battery: async () => "Battery is at 87%.", clipboard: async () => "demo",
    setClipboard: ok, runningApps: async () => ["Steam", "Discord"], darkMode: ok, screenOff: ok, lock: ok, createNote: ok,
    startTimer: (s, label) => setTimeout(() => agent.alert(label), s * 1000), cancelTimers: () => 0 };
}
