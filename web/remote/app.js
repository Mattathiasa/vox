// Vox Remote: the phone (and Windows window) controller. Talks to a Vox agent
// (Mac app or Windows agent) over the Remote protocol (docs/ARCHITECTURE.md).
// No framework, no build step: this file is served as-is.

import { afterWake, yesNo, phrasesFrom, typingDiff } from "./wake.js";

const $ = (id) => document.getElementById(id);
const store = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch { /* private mode: keep in memory */ } },
  remove(key) { try { localStorage.removeItem(key); } catch { /* ignore */ } },
};

let token = store.get("voxToken");
let state = null;
let pollTimer = null;
let openTool = null;          // tool shown full-screen
let liveTyping = false;
let speakReplies = store.get("voxSpeak") !== "off";
let lastResultKey = "";

// MARK: Pairing

function takePairingFromURL() {
  const match = location.hash.match(/pair=([^&]+)/);
  if (!match) return;
  token = decodeURIComponent(match[1]).trim();
  store.set("voxToken", token);
  history.replaceState(null, "", location.pathname + location.search);
}

function showPairing(message = "") {
  stopPolling();
  $("app").hidden = true;
  $("term").hidden = true;
  $("pair").hidden = false;
  $("pair-error").textContent = message;
}

$("pair-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const code = $("pair-code").value.trim();
  if (!code) return;
  token = code;
  store.set("voxToken", token);
  await start();
});

// MARK: API

class AuthError extends Error {}

async function api(path, body) {
  const options = { method: body === undefined ? "GET" : "POST", headers: { Authorization: `Bearer ${token}` }, cache: "no-store" };
  if (body !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  const response = await fetch(`api/${path}`, options);
  if (response.status === 401) throw new AuthError("That pairing code isn't right (or it was changed).");
  if (response.status === 429) throw new AuthError("Too many wrong codes. Wait a minute and try again.");
  if (!response.ok) throw new Error(`${response.status} ${await response.text()}`);
  return response.json();
}

function toolPath(tool, action) {
  return `tools/${encodeURIComponent(tool)}/${action}`;
}

// MARK: Polling

function stopPolling() {
  clearTimeout(pollTimer);
  pollTimer = null;
}

async function poll() {
  stopPolling();
  try {
    const next = await api(`state?lines=${openTool ? 200 : 60}`);
    setConnected(true);
    render(next);
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    setConnected(false, error);
  }
  if (document.visibilityState === "visible") pollTimer = setTimeout(poll, openTool ? 700 : 1100);
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && token && !$("app").hidden) poll();
});

function setConnected(ok) {
  $("conn-dot").className = `dot ${ok ? "ok" : "bad"}`;
  if (!ok) $("host-sub").textContent = "Can't reach Vox — is it running?";
}

// MARK: Rendering

const slug = (tool) => tool.toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "");

function phaseOf(s) {
  if (s.pendingQuestion) return { cls: "confirm", label: "Needs your OK" };
  if (listening || hf.mode === "command") return { cls: "listening", label: "Listening…" };
  if (s.busy || sending) return { cls: "busy", label: "Working…" };
  if (s.lockedTool) return { cls: `linked${hf.on ? " handsfree" : ""}`, label: hf.on ? `Say “${wakeName()}” · talking to ${s.lockedTool}` : `Talking to ${s.lockedTool}` };
  if (hf.on) return { cls: "handsfree", label: hf.running ? `Say “${wakeName()}”…` : "Hands-free paused" };
  return { cls: "", label: "Ready" };
}

function render(s) {
  state = s;
  $("host-name").textContent = s.host || "Vox";
  const platform = s.platform === "windows" ? "Windows" : "Mac";
  $("host-sub").textContent = `${platform} · ${s.screens.length} terminal${s.screens.length === 1 ? "" : "s"}`;

  const phase = phaseOf(s);
  $("orb").className = `orb ${phase.cls}`;
  $("phase").textContent = phase.label;

  // Confirmation sheet
  $("confirm").hidden = !s.pendingQuestion;
  if (s.pendingQuestion) $("confirm-text").textContent = s.pendingQuestion;

  // Last result banner
  const last = s.history && s.history[0];
  if (last && last.reply && !s.pendingQuestion) {
    const key = `${last.command}|${last.reply}`;
    const banner = $("reply");
    banner.hidden = false;
    banner.className = `banner glass ${last.kind}`;
    banner.replaceChildren(icon(last.kind), text(last.reply));
    lastResultKey = key;
  } else {
    $("reply").hidden = true;
  }

  // Stop-talking chip
  $("btn-exit").hidden = !s.lockedTool;
  $("locked-name").textContent = s.lockedTool || "";

  renderLaunch(s);
  renderTerminals(s);
  renderHistory(s);
  if (openTool) renderTerminalScreen();
}

function icon(kind) {
  const span = document.createElement("span");
  span.className = "ico";
  span.textContent = { success: "✓", warning: "!", confirm: "?", error: "×" }[kind] || "i";
  return span;
}

function text(value) {
  const span = document.createElement("span");
  span.textContent = value;
  return span;
}

function renderLaunch(s) {
  const running = new Set(s.screens.map((screen) => screen.tool));
  const idle = (s.tools || []).filter((tool) => !running.has(slug(tool)));
  const box = $("launch");
  box.replaceChildren(...idle.map((tool) => {
    const button = document.createElement("button");
    button.className = "chip launch glass";
    button.textContent = tool;
    button.addEventListener("click", () => act(toolPath(tool, "launch"), {}, `Starting ${tool}…`));
    return button;
  }));
}

function renderTerminals(s) {
  const box = $("terminals");
  $("no-terminals").hidden = s.screens.length > 0;
  const cards = s.screens.map((screen) => {
    const card = document.createElement("button");
    card.className = `tcard glass${s.lockedTool && slug(s.lockedTool) === screen.tool ? " linked" : ""}`;
    const head = document.createElement("div");
    head.className = "tcard-head";
    const dot = document.createElement("span");
    dot.className = `dot ${screen.exited ? "bad" : "ok"}`;
    const state = document.createElement("span");
    state.className = "state";
    state.textContent = screen.exited ? "Exited" : "Tap to open";
    head.append(dot, text(screen.tool), state);
    const pre = document.createElement("pre");
    pre.textContent = tail(screen.text, 14);
    card.append(head, pre);
    card.addEventListener("click", () => openTerminal(screen.tool));
    return card;
  });
  box.replaceChildren(...cards);
}

function tail(value, lines) {
  const all = (value || "").split("\n");
  return all.slice(-lines).join("\n");
}

function renderHistory(s) {
  const items = (s.history || []).slice(0, 8).map((item) => {
    const li = document.createElement("li");
    li.className = `glass ${item.kind}`;
    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = item.source === "phone" ? "📱" : item.spoken ? "🎙" : "⌨︎";
    const body = document.createElement("div");
    const cmd = document.createElement("div");
    cmd.className = "cmd";
    cmd.textContent = item.command;
    const rep = document.createElement("div");
    rep.className = "rep";
    rep.textContent = item.reply;
    body.append(cmd, rep);
    li.append(badge, body);
    return li;
  });
  $("history").replaceChildren(...items);
}

// MARK: Commands

let sending = false;

async function sendCommand(value, spoken = false) {
  const command = value.trim();
  if (!command) return;
  sending = true;
  $("transcript").textContent = command;
  $("transcript").classList.add("heard");
  if (state) render(state);
  try {
    const result = await api("command", { text: command, spoken, source: "phone" });
    if (spoken) speak(result.events || []);
    const bad = (result.events || []).find((event) => event.kind === "error");
    if (bad) toast(bad.message);
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    toast(`Couldn't send: ${error.message}`);
  } finally {
    sending = false;
    poll();
  }
}

async function act(path, body, message) {
  if (message) toast(message);
  try {
    const result = await api(path, body);
    const bad = (result.events || []).find((event) => event.kind === "error" || event.kind === "warning");
    if (bad) toast(bad.message);
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    toast(error.message);
  }
  poll();
}

$("dock").addEventListener("submit", (event) => {
  event.preventDefault();
  const value = $("cmd").value;
  $("cmd").value = "";
  sendCommand(value);
});
$("confirm-yes").addEventListener("click", () => act("confirm", { yes: true }));
$("confirm-no").addEventListener("click", () => act("confirm", { yes: false }));
$("btn-exit").addEventListener("click", () => act("exit", {}));

// MARK: Voice (Web Speech API; needs HTTPS or localhost)

const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const canListen = Boolean(Recognition) && window.isSecureContext;
const voiceHelp = () => (window.isSecureContext ? "This browser has no voice input — use your keyboard's mic." : "Voice needs HTTPS: open Vox through Tailscale, or use your keyboard's mic.");
let recognizer = null;
let listening = false;

if (!canListen) { $("btn-mic").classList.add("off"); $("btn-wake").classList.add("off"); }

$("btn-mic").addEventListener("click", () => {
  if (!canListen) {
    $("cmd").focus();
    toast(voiceHelp());
    return;
  }
  listening ? recognizer?.stop() : listen();
});

// Push-to-talk: one phrase, then send it. Pauses hands-free while it runs.
function listen() {
  pauseHandsFree();
  recognizer = new Recognition();
  recognizer.lang = navigator.language || "en-US";
  recognizer.interimResults = true;
  recognizer.continuous = false;
  let finalText = "";
  recognizer.onresult = (event) => {
    let interim = "";
    for (let i = event.resultIndex; i < event.results.length; i += 1) {
      const piece = event.results[i][0].transcript;
      if (event.results[i].isFinal) finalText += piece; else interim += piece;
    }
    $("transcript").textContent = (finalText + interim).trim() || "Listening…";
    $("transcript").classList.add("heard");
  };
  recognizer.onerror = (event) => {
    if (event.error === "not-allowed") toast("Microphone permission is off for this site.");
    else if (event.error !== "no-speech" && event.error !== "aborted") toast(`Voice: ${event.error}`);
  };
  recognizer.onend = () => {
    listening = false;
    recognizer = null;
    $("btn-mic").classList.remove("on");
    if (state) render(state);
    // A leading "Balcha" is fine here too.
    const heard = finalText.trim();
    const command = afterWake(heard, phrasesFrom(state)) ?? heard;
    if (command) sendCommand(command, true);
    resumeHandsFree();
  };
  listening = true;
  $("btn-mic").classList.add("on");
  $("transcript").textContent = "Listening…";
  if (state) render(state);
  recognizer.start();
}

// MARK: Hands-free ("Balcha, …")
// Continuous recognition while the page is open and visible. Browsers stop it now and then
// (silence, time limits, the screen locking), so it restarts itself. Phones cut the mic when
// the screen locks or you switch apps: this works while Vox is on screen (we keep it awake).

const hf = {
  on: store.get("voxHandsFree") === "on",
  running: false,       // a recognizer is active
  paused: 0,            // >0 while push-to-talk or a spoken reply is using the mic/speaker
  mode: "wait",         // "wait" for the wake word, "command" after hearing it
  rec: null,
  startedAt: 0,
  quickEnds: 0,
  sendTimer: null,
  commandTimer: null,
  wakeLock: null,
};
const wakeName = () => state?.wake?.name || "Balcha";

function updateWakeButton() {
  $("btn-wake").setAttribute("aria-pressed", String(hf.on));
  $("btn-wake").classList.toggle("hearing", hf.on && hf.mode === "command");
}

$("btn-wake").addEventListener("click", () => {
  if (!canListen) { toast(voiceHelp()); return; }
  setHandsFree(!hf.on);
});

function setHandsFree(on) {
  hf.on = on;
  store.set("voxHandsFree", on ? "on" : "off");
  hf.quickEnds = 0;
  updateWakeButton();
  if (on) {
    toast(`Hands-free on: say “${wakeName()}” and then your command.`);
    startHandsFree();
  } else {
    stopHandsFree();
    toast("Hands-free off");
  }
  if (state) render(state);
}

function startHandsFree() {
  if (!hf.on || hf.running || hf.paused > 0 || listening || document.visibilityState !== "visible" || !canListen || !token) return;
  const rec = new Recognition();
  rec.lang = navigator.language || "en-US";
  rec.interimResults = true;
  rec.continuous = true;
  let consumed = 0;                 // results before this index are already handled
  rec.onresult = (event) => {
    let text = "";
    let lastFinal = false;
    for (let i = consumed; i < event.results.length; i += 1) {
      text += ` ${event.results[i][0].transcript}`;
      lastFinal = event.results[i].isFinal;
    }
    text = text.trim();
    if (!text) return;
    const command = afterWake(text, phrasesFrom(state));

    if (command === null) {
      // No wake word. A bare "yes"/"no" still answers a pending question.
      if (lastFinal && state?.pendingQuestion) {
        const answer = yesNo(text);
        if (answer !== null) { consumed = event.results.length; act("confirm", { yes: answer }); return; }
      }
      if (lastFinal && hf.mode === "wait") consumed = event.results.length;   // forget chatter
      return;
    }
    if (hf.mode !== "command") heardWake();
    $("transcript").textContent = command || "Listening…";
    $("transcript").classList.add("heard");
    clearTimeout(hf.sendTimer);
    if (command && lastFinal) {
      // Wait a moment: more words may still arrive as another final result.
      hf.sendTimer = setTimeout(() => {
        consumed = event.results.length;
        finishCommand(command);
      }, 650);
    }
  };
  rec.onerror = (event) => {
    if (event.error === "not-allowed" || event.error === "service-not-allowed") {
      hf.running = false;
      setHandsFree(false);
      toast("Microphone permission is off for this site.");
    } else if (event.error === "network") {
      hf.quickEnds += 1;
    }
  };
  rec.onend = () => {
    hf.running = false;
    hf.rec = null;
    if (Date.now() - hf.startedAt < 1500) hf.quickEnds += 1; else hf.quickEnds = 0;
    if (hf.quickEnds >= 6) {
      toast("Voice keeps stopping on this browser. Tap the ear to try again.");
      hf.quickEnds = 0;
      setHandsFree(false);
      return;
    }
    if (state) render(state);
    // Restart unless something else is using the mic. Back off a little after quick failures.
    setTimeout(startHandsFree, 250 + hf.quickEnds * 600);
  };
  try {
    rec.start();
  } catch {
    return;   // already started, or the browser wants a tap first (iOS after the page was hidden)
  }
  hf.rec = rec;
  hf.running = true;
  hf.startedAt = Date.now();
  holdScreenAwake();
  if (state) render(state);
}

function heardWake() {
  hf.mode = "command";
  navigator.vibrate?.(30);
  updateWakeButton();
  clearTimeout(hf.commandTimer);
  // "Balcha" and then nothing: give up after a while.
  hf.commandTimer = setTimeout(() => backToWaiting(), 9000);
  if (state) render(state);
}

function backToWaiting() {
  hf.mode = "wait";
  clearTimeout(hf.commandTimer);
  clearTimeout(hf.sendTimer);
  updateWakeButton();
  if (state) render(state);
}

function finishCommand(command) {
  backToWaiting();
  sendCommand(command, true);
}

function stopHandsFree() {
  clearTimeout(hf.sendTimer);
  clearTimeout(hf.commandTimer);
  hf.mode = "wait";
  const rec = hf.rec;
  hf.rec = null;
  hf.running = false;
  if (rec) { rec.onend = null; rec.onresult = null; try { rec.abort(); } catch { /* ignore */ } }
  releaseScreen();
  updateWakeButton();
}

function pauseHandsFree() {
  hf.paused += 1;
  if (hf.rec) {
    const rec = hf.rec;
    hf.rec = null;
    hf.running = false;
    rec.onend = null;
    rec.onresult = null;
    try { rec.abort(); } catch { /* ignore */ }
  }
}

function resumeHandsFree() {
  hf.paused = Math.max(0, hf.paused - 1);
  if (hf.paused === 0) setTimeout(startHandsFree, 300);
}

// Keep the screen on while hands-free is listening (Screen Wake Lock: Safari 16.4+, Chrome, Edge).
async function holdScreenAwake() {
  if (hf.wakeLock || !("wakeLock" in navigator)) return;
  try {
    hf.wakeLock = await navigator.wakeLock.request("screen");
    hf.wakeLock.addEventListener?.("release", () => { hf.wakeLock = null; });
  } catch { /* not allowed right now (e.g. low battery) */ }
}
function releaseScreen() {
  hf.wakeLock?.release?.().catch(() => {});
  hf.wakeLock = null;
}

document.addEventListener("visibilitychange", () => {
  if (!hf.on) return;
  if (document.visibilityState === "visible") { hf.quickEnds = 0; setTimeout(startHandsFree, 300); }
  else { pauseHandsFree(); hf.paused = Math.max(0, hf.paused - 1); releaseScreen(); }
});

// iOS won't start the mic again without a tap after the page was hidden: any tap retries.
document.addEventListener("pointerdown", () => { if (hf.on && !hf.running && hf.paused === 0) startHandsFree(); }, { passive: true });

// Spoken replies, same policy as the Mac: say questions, problems and short answers; stay quiet on success.
function speak(events) {
  if (!speakReplies || !("speechSynthesis" in window)) return;
  for (const event of events) {
    if (event.kind === "success") continue;
    let line = event.message;
    if (event.kind === "confirm") line = `${line.replace(" Say yes to confirm.", "")} Yes or no?`;
    else if (line.length > 120) line = "Done. The details are on screen.";
    const utterance = new SpeechSynthesisUtterance(line);
    // Don't let hands-free hear Vox talking.
    pauseHandsFree();
    let resumed = false;
    const done = () => { if (!resumed) { resumed = true; resumeHandsFree(); } };
    utterance.onend = done;
    utterance.onerror = done;
    setTimeout(done, 1500 + line.length * 90);   // some browsers never fire onend
    speechSynthesis.speak(utterance);
  }
}

function updateSpeakButton() {
  $("btn-speak").setAttribute("aria-pressed", String(speakReplies));
}
$("btn-speak").addEventListener("click", () => {
  speakReplies = !speakReplies;
  store.set("voxSpeak", speakReplies ? "on" : "off");
  updateSpeakButton();
  toast(speakReplies ? "Spoken replies on" : "Spoken replies off");
});

// MARK: Full-screen terminal

function openTerminal(tool) {
  openTool = tool;
  $("term").hidden = false;
  $("term-name").textContent = tool;
  setLive(store.get("voxTermMode") !== "line");
  renderTerminalScreen(true);
  poll();
}

function closeTerminal() {
  openTool = null;
  $("term").hidden = true;
  poll();
}

function renderTerminalScreen(forceBottom = false) {
  const screen = state?.screens.find((item) => item.tool === openTool);
  const pre = $("term-text");
  if (!screen) {
    $("term-state").textContent = "Not running";
    $("term-dot").className = "dot bad";
    return;
  }
  const nearBottom = pre.scrollHeight - pre.scrollTop - pre.clientHeight < 40;
  if (pre.textContent !== screen.text) pre.textContent = screen.text;
  if (forceBottom || nearBottom) pre.scrollTop = pre.scrollHeight;
  const linked = state.lockedTool && slug(state.lockedTool) === screen.tool;
  $("term-state").textContent = screen.exited ? "Exited" : linked ? "Talking" : "Running";
  $("term-dot").className = `dot ${screen.exited ? "bad" : "ok"}`;
}

$("term-back").addEventListener("click", closeTerminal);
$("term-kill").addEventListener("click", () => act(toolPath(openTool, "kill"), {}));

// Live mode (default): every keystroke goes straight to the terminal, like a real one.
// Line mode: type a whole command, Enter sends it.
// The phone keyboard edits a hidden field; we send the difference (see typingDiff), so
// autocorrect and suggestions work. Two zero-width spaces sit in front so Backspace on an
// "empty" field still reaches the terminal, and iOS doesn't turn double spaces into ". ".
const SENTINEL = "\u200B\u200B";
let lastValue = SENTINEL;
let composing = false;

function resetLiveField() {
  const input = $("term-cmd");
  input.value = liveTyping ? SENTINEL : "";
  lastValue = input.value;
}

function setLive(on) {
  liveTyping = on;
  store.set("voxTermMode", on ? "live" : "line");
  $("mode-live").classList.toggle("on", on);
  $("mode-line").classList.toggle("on", !on);
  $("term-text").classList.toggle("live", on);
  const input = $("term-cmd");
  resetLiveField();
  input.placeholder = on ? "Type — keys go straight to the terminal" : "Command… (Enter sends it)";
  input.focus();
}
$("mode-line").addEventListener("click", () => setLive(false));
$("mode-live").addEventListener("click", () => setLive(true));
$("term-text").addEventListener("click", () => {
  // Tapping the screen brings up the keyboard, like a real terminal (but not while selecting text).
  if (!window.getSelection()?.toString()) $("term-cmd").focus();
});

// Keystrokes are sent in order through one queue; typed characters are batched.
let queue = Promise.resolve();
let pendingText = "";
let flushTimer = null;

function enqueue(path, body) {
  queue = queue.then(() => api(path, body).catch((error) => toast(error.message)));
  return queue;
}

function typeChars(chars) {
  pendingText += chars;
  clearTimeout(flushTimer);
  flushTimer = setTimeout(flushTyping, 35);
}

function flushTyping() {
  clearTimeout(flushTimer);
  if (!pendingText || !openTool) return;
  const chunk = pendingText;
  pendingText = "";
  enqueue(toolPath(openTool, "type"), { text: chunk });
}

function pressKey(key) {
  if (!openTool) return;
  flushTyping();
  enqueue(toolPath(openTool, "key"), { key }).then(() => setTimeout(poll, 150));
}

function syncLive() {
  const input = $("term-cmd");
  const value = input.value;
  const { backspaces, text } = typingDiff(lastValue, value);
  for (let i = 0; i < backspaces; i += 1) pressKey("BSpace");
  const typed = text.replace(/\u200B/g, "");
  if (typed.includes("\n")) {
    typed.split("\n").forEach((part, index) => { if (index > 0) pressKey("Enter"); if (part) typeChars(part); });
  } else if (typed) {
    typeChars(typed);
  }
  lastValue = value;
  // Keep the field short, and put the sentinel back once it's been deleted into.
  if (!value.startsWith(SENTINEL) || value.length > 80) resetLiveField();
}

const input = $("term-cmd");
input.addEventListener("compositionstart", () => { composing = true; });
input.addEventListener("compositionend", () => { composing = false; if (liveTyping) syncLive(); });
input.addEventListener("input", (event) => {
  if (!liveTyping || composing || event.isComposing) return;
  syncLive();
});

const liveKeys = { Escape: "Escape", Tab: "Tab", ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right",
  Delete: "DC", Home: "Home", End: "End", PageUp: "PPage", PageDown: "NPage" };
let lastEnterAt = 0;

function liveEnter() {
  if (Date.now() - lastEnterAt < 120) return;   // keydown and form submit both fire on some keyboards
  lastEnterAt = Date.now();
  if (composing) { composing = false; syncLive(); }
  pressKey("Enter");
  resetLiveField();
}

function lineEnter() {
  const value = input.value;
  input.value = "";
  if (value.trim()) enqueue(toolPath(openTool, "send"), { text: value }).then(() => setTimeout(poll, 300));
  else pressKey("Enter");
}

input.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.isComposing) {
    event.preventDefault();
    liveTyping ? liveEnter() : lineEnter();
    return;
  }
  if (!liveTyping) return;
  if (event.ctrlKey && event.key.length === 1) {
    const letter = event.key.toLowerCase();
    if (["c", "d", "l"].includes(letter)) { event.preventDefault(); pressKey(`C-${letter}`); }
    return;
  }
  if (event.key === "Tab" && event.shiftKey) { event.preventDefault(); pressKey("BTab"); return; }
  if (event.key === "Backspace" && input.value === SENTINEL) {
    // Nothing of ours to delete: send it straight on (and keep the sentinel).
    event.preventDefault();
    pressKey("BSpace");
    return;
  }
  const key = liveKeys[event.key];
  if (key) { event.preventDefault(); pressKey(key); }
});
$("term-form").addEventListener("submit", (event) => {
  event.preventDefault();
  liveTyping ? liveEnter() : lineEnter();
});
document.querySelectorAll(".term-keys button").forEach((button) => {
  // Keep the keyboard up: don't let the button steal focus from the field.
  button.addEventListener("pointerdown", (event) => event.preventDefault());
  button.addEventListener("click", () => { pressKey(button.dataset.key); input.focus(); });
});

// MARK: Menu, log, toast

$("btn-menu").addEventListener("click", () => { $("menu").hidden = false; });
$("menu-close").addEventListener("click", () => { $("menu").hidden = true; });
$("menu-help").addEventListener("click", () => { $("menu").hidden = true; sendCommand("help"); });
$("menu-unpair").addEventListener("click", () => {
  $("menu").hidden = true;
  store.remove("voxToken");
  token = null;
  showPairing();
});
$("menu-log").addEventListener("click", () => {
  $("menu").hidden = true;
  $("log").hidden = false;
  const items = (state?.log || []).map((line) => {
    const li = document.createElement("li");
    li.className = line.kind;
    const time = document.createElement("time");
    time.textContent = line.time || "";
    li.append(time, text(line.text));
    return li;
  });
  $("log-list").replaceChildren(...items);
  $("log-list").scrollTop = $("log-list").scrollHeight;
});
$("log-back").addEventListener("click", () => { $("log").hidden = true; });

// "Pair a phone": the Windows agent serves /api/pairing; the Mac pairs from Vox → Settings → Phone.
$("menu-pair").addEventListener("click", async () => {
  $("menu").hidden = true;
  try {
    const info = await api("pairing");
    $("pairing-qr").src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(info.qrSvg)}`;
    $("pairing-urls").replaceChildren(...(info.urls || []).map((u) => {
      const li = document.createElement("li");
      li.textContent = `${u.label}: ${u.url.replace(/#pair=.*/, "")}`;
      return li;
    }));
    $("pairing-hint").textContent = info.hint || "";
    $("pairing").hidden = false;
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    toast(state?.platform === "mac" ? "On the Mac, pair from Vox → Settings → Phone." : `Couldn't get pairing info: ${error.message}`);
  }
});
$("pairing-back").addEventListener("click", () => { $("pairing").hidden = true; });

let toastTimer = null;
function toast(message) {
  const box = $("toast");
  box.textContent = message;
  box.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { box.hidden = true; }, 2600);
}

// MARK: Start

async function start() {
  takePairingFromURL();
  updateSpeakButton();
  if (!token) return showPairing();
  try {
    const first = await api("state?lines=60");
    $("pair").hidden = true;
    $("app").hidden = false;
    render(first);
    setConnected(true);
    poll();
    updateWakeButton();
    if (hf.on) startHandsFree();
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    $("pair").hidden = true;
    $("app").hidden = false;
    setConnected(false);
    pollTimer = setTimeout(poll, 2000);
  }
}

start();
