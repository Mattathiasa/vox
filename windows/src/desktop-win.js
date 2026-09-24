// Windows desktop control. Every PowerShell script here is FIXED text; anything that came
// from speech (app names, text to type, URLs) is passed in environment variables
// (security invariant 7), so it can never become code.
import { execFile } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const POWERSHELL = "powershell.exe";

export function runPowerShell(script, env = {}, { timeout = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    execFile(POWERSHELL, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script],
      { env: { ...process.env, ...env }, windowsHide: true, timeout, maxBuffer: 1024 * 1024 },
      (error, stdout, stderr) => {
        if (error) reject(new Error((stderr || error.message).trim().split("\n")[0]));
        else resolve(stdout.trim());
      });
  });
}

// Keyboard: presses a list of virtual-key codes (modifiers first), releases in reverse.
const KEYS_SCRIPT = `
Add-Type -Namespace Vox -Name Kb -MemberDefinition '[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);'
$codes = $env:VOX_KEYS.Split(',') | ForEach-Object { [byte][Convert]::ToInt32($_, 16) }
$repeat = [int]$env:VOX_REPEAT
for ($r = 0; $r -lt $repeat; $r++) {
  foreach ($c in $codes) { [Vox.Kb]::keybd_event($c, 0, 0, [System.UIntPtr]::Zero) }
  [array]::Reverse($codes)
  foreach ($c in $codes) { [Vox.Kb]::keybd_event($c, 0, 2, [System.UIntPtr]::Zero) }
  [array]::Reverse($codes)
  Start-Sleep -Milliseconds 15
}`;

const VK = {
  control: 0x11, shift: 0x10, option: 0x12, win: 0x5b,
  return: 0x0d, tab: 0x09, space: 0x20, delete: 0x08, escape: 0x1b, up: 0x26, down: 0x28, left: 0x25, right: 0x27,
  pageup: 0x21, pagedown: 0x22, home: 0x24, end: 0x23, leftbracket: 0xdb, rightbracket: 0xdd, equal: 0xbb, minus: 0xbd,
  comma: 0xbc, period: 0xbe, f4: 0x73, f11: 0x7a, printscreen: 0x2c, forwarddelete: 0x2e,
  volumeMute: 0xad, volumeDown: 0xae, volumeUp: 0xaf, mediaNext: 0xb0, mediaPrevious: 0xb1, mediaPlayPause: 0xb3,
};

/** Mac shortcuts (the shared grammar speaks Mac) that mean something else on Windows. */
const WINDOWS_EQUIVALENTS = {
  "control+command+q": ["win", "l"],               // lock screen
  "command+space": ["win"],                          // spotlight -> Start
  "control+up": ["win", "tab"],                      // mission control -> Task View
  "control+down": ["win", "tab"],
  "control+command+f": ["f11"],                      // full screen
  "command+q": ["option", "f4"],                     // quit this app
  "command+h": ["win", "down"],                      // hide this -> minimize
  "command+m": ["win", "down"],                      // minimize
  "command+tab": ["option", "tab"],                  // switch app
  "command+leftbracket": ["option", "left"],         // back
  "command+rightbracket": ["option", "right"],       // forward
  "command+up": ["control", "home"],                 // scroll to top
  "command+down": ["control", "end"],
  "command+left": ["home"],                          // start of line
  "command+right": ["end"],
  "option+delete": ["control", "delete"],            // delete word
  "shift+command+3": ["printscreen"],                // screenshot
  "shift+command+4": ["win", "shift", "s"],          // screenshot selection (Snipping Tool)
  "control+command+space": ["win", "period"],        // emoji picker
  "control+right": ["win", "control", "right"],      // next desktop
  "control+left": ["win", "control", "left"],
  "option+command+w": ["control", "shift", "w"],     // close all windows (browsers)
  "shift+command+n": ["control", "shift", "n"],      // new folder / private window
};

const MOD_TO_WINDOWS = { command: "control", control: "control", option: "option", shift: "shift" };

/** Combo from the grammar -> Windows virtual-key codes. */
export function comboToVirtualKeys(combo) {
  const description = [...["control", "option", "shift", "command"].filter((m) => combo.modifiers.includes(m)), combo.key].join("+");
  const names = WINDOWS_EQUIVALENTS[description]
    ?? [...new Set(combo.modifiers.map((m) => MOD_TO_WINDOWS[m]))].concat([combo.key]);
  return names.map((name) => {
    if (Object.hasOwn(VK, name)) return VK[name];
    if (/^[a-z]$/.test(name)) return name.toUpperCase().charCodeAt(0);
    if (/^[0-9]$/.test(name)) return name.charCodeAt(0);
    throw new Error(`No Windows key for "${name}".`);
  });
}

const hexList = (codes) => codes.map((c) => c.toString(16)).join(",");

/** SendKeys treats + ^ % ~ ( ) { } [ ] as syntax; wrap them so text types literally. */
export function escapeSendKeys(text) {
  return text.replace(/[+^%~(){}[\]]/g, (ch) => `{${ch}}`).replace(/\r?\n/g, "{ENTER}");
}

export class WindowsDesktop {
  constructor({ apps, onAlert = () => {} }) {
    this.apps = apps;
    this.onAlert = onAlert;
    this.timers = new Set();
  }

  async open(target, args = null) {
    // Start-Process opens exes, .lnk shortcuts, folders and URLs (http, steam://, ms-settings:).
    const script = args
      ? "Start-Process -FilePath $env:VOX_TARGET -ArgumentList ('\"' + $env:VOX_ARGS + '\"')"
      : "Start-Process -FilePath $env:VOX_TARGET";
    await runPowerShell(script, { VOX_TARGET: target, ...(args ? { VOX_ARGS: args } : {}) });
  }

  async openURL(url) { await this.open(url); }

  async pressKeys(codes, repeat = 1) {
    await runPowerShell(KEYS_SCRIPT, { VOX_KEYS: hexList(codes), VOX_REPEAT: String(repeat) });
  }

  async pressKey(combo) { await this.pressKeys(comboToVirtualKeys(combo)); }

  async typeText(text) {
    await runPowerShell("Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait($env:VOX_TEXT)",
      { VOX_TEXT: escapeSendKeys(text) });
  }

  /** Windows process names are rarely the display name; match loosely on the squashed name. */
  async quitApp(name) {
    const out = await runPowerShell(`
$want = ($env:VOX_NAME -replace '[^a-zA-Z0-9]', '').ToLower()
$hits = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ((($_.ProcessName -replace '[^a-zA-Z0-9]', '').ToLower() -like "*$want*") -or (($_.MainWindowTitle -replace '[^a-zA-Z0-9]', '').ToLower() -like "*$want*")) }
foreach ($p in $hits) { [void]$p.CloseMainWindow() }
$hits.Count`, { VOX_NAME: name });
    return Number(out) > 0;
  }

  async focusApp(name) {
    const out = await runPowerShell("$s = New-Object -ComObject WScript.Shell; $s.AppActivate($env:VOX_NAME)", { VOX_NAME: name });
    return out.toLowerCase() === "true";
  }

  async minimizeApp(name) {
    if (!(await this.focusApp(name))) return false;
    await this.pressKeys([VK.win, VK.down]);
    return true;
  }

  async volume(change) {
    if (change === "up") return this.pressKeys([VK.volumeUp], 5);
    if (change === "down") return this.pressKeys([VK.volumeDown], 5);
    if (change === "mute" || change === "unmute") return this.pressKeys([VK.volumeMute]);
    const level = Number(change.split(" ")[1]);
    await this.pressKeys([VK.volumeDown], 50);
    if (level > 0) await this.pressKeys([VK.volumeUp], Math.round(level / 2));
  }

  async media(key) {
    const code = { playPause: VK.mediaPlayPause, next: VK.mediaNext, previous: VK.mediaPrevious }[key];
    await this.pressKeys([code]);
  }

  async battery() {
    const out = await runPowerShell("$b = Get-CimInstance Win32_Battery | Select-Object -First 1; if ($b) { \"$($b.EstimatedChargeRemaining)|$($b.BatteryStatus)\" }");
    if (!out) return "This PC doesn't report a battery.";
    const [percent, status] = out.split("|");
    return Number(status) === 2 ? `Battery is at ${percent}% and plugged in.` : `Battery is at ${percent}%.`;
  }

  async clipboard() { return runPowerShell("Get-Clipboard -Raw"); }
  async setClipboard(text) { await runPowerShell("Set-Clipboard -Value $env:VOX_TEXT", { VOX_TEXT: text }); }

  async runningApps() {
    const out = await runPowerShell("Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -ExpandProperty ProcessName -Unique");
    return out.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  }

  async darkMode(on) {
    await runPowerShell(`
$key = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize'
$light = (Get-ItemProperty -Path $key -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
if ($env:VOX_MODE -eq 'toggle') { $value = if ($light -eq 0) { 1 } else { 0 } } elseif ($env:VOX_MODE -eq 'on') { $value = 0 } else { $value = 1 }
Set-ItemProperty -Path $key -Name AppsUseLightTheme -Value $value
Set-ItemProperty -Path $key -Name SystemUsesLightTheme -Value $value`, { VOX_MODE: on === null ? "toggle" : on ? "on" : "off" });
  }

  async screenOff() {
    await runPowerShell(`
Add-Type -Namespace Vox -Name Mon -MemberDefinition '[DllImport("user32.dll")] public static extern int SendMessage(int h, int m, int w, int l);'
[void][Vox.Mon]::SendMessage(0xFFFF, 0x0112, 0xF170, 2)`);
  }

  async lock() { await runPowerShell("rundll32.exe user32.dll,LockWorkStation"); }

  /** No Notes app on Windows: append to Documents\Vox Notes.txt and open it. */
  async createNote(text) {
    const file = path.join(os.homedir(), "Documents", "Vox Notes.txt");
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.appendFileSync(file, `${new Date().toLocaleString()}  ${text}\r\n`);
    await this.open(file);
  }

  startTimer(seconds, label) {
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      this.onAlert(label);
      runPowerShell("(New-Object Media.SoundPlayer 'C:\\Windows\\Media\\Alarm01.wav').PlaySync()").catch(() => {});
    }, seconds * 1000);
    this.timers.add(timer);
  }

  cancelTimers() {
    const count = this.timers.size;
    for (const t of this.timers) clearTimeout(t);
    this.timers.clear();
    return count;
  }
}
