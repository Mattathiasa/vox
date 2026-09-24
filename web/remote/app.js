// Vox Remote: the phone (and Windows window) controller. Talks to a Vox agent
// (Mac app or Windows agent) over the Remote protocol (docs/ARCHITECTURE.md).
// No framework, no build step: this file is served as-is.

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
  if (listening) return { cls: "listening", label: "Listening…" };
  if (s.busy || sending) return { cls: "busy", label: "Working…" };
  if (s.lockedTool) return { cls: "linked", label: `Talking to ${s.lockedTool}` };
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
let recognizer = null;
let listening = false;

if (!canListen) $("btn-mic").classList.add("off");

$("btn-mic").addEventListener("click", () => {
  if (!canListen) {
    $("cmd").focus();
    toast(window.isSecureContext ? "This browser has no voice input — use your keyboard's mic." : "Voice needs HTTPS: open Vox through Tailscale, or use your keyboard's mic.");
    return;
  }
  listening ? recognizer?.stop() : listen();
});

function listen() {
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
    $("btn-mic").classList.remove("on");
    if (state) render(state);
    if (finalText.trim()) sendCommand(finalText, true);
  };
  listening = true;
  $("btn-mic").classList.add("on");
  $("transcript").textContent = "Listening…";
  if (state) render(state);
  recognizer.start();
}

// Spoken replies, same policy as the Mac: say questions, problems and short answers; stay quiet on success.
function speak(events) {
  if (!speakReplies || !("speechSynthesis" in window)) return;
  for (const event of events) {
    if (event.kind === "success") continue;
    let line = event.message;
    if (event.kind === "confirm") line = `${line.replace(" Say yes to confirm.", "")} Yes or no?`;
    else if (line.length > 120) line = "Done. The details are on screen.";
    speechSynthesis.speak(new SpeechSynthesisUtterance(line));
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
  setLive(false);
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

// Line mode: type a whole command, Enter sends it (with Enter).
// Live mode: every keystroke goes straight to the terminal, like a real one.
const SENTINEL = "  ";

function setLive(on) {
  liveTyping = on;
  $("mode-live").classList.toggle("on", on);
  $("mode-line").classList.toggle("on", !on);
  $("term-text").classList.toggle("live", on);
  const input = $("term-cmd");
  input.value = on ? SENTINEL : "";
  input.placeholder = on ? "Typing goes straight to the terminal…" : "Command…";
  input.focus();
}
$("mode-line").addEventListener("click", () => setLive(false));
$("mode-live").addEventListener("click", () => setLive(true));
$("term-text").addEventListener("click", () => $("term-cmd").focus());

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

$("term-cmd").addEventListener("input", () => {
  if (!liveTyping) return;
  const input = $("term-cmd");
  const value = input.value;
  if (value.length < SENTINEL.length) {
    for (let i = value.length; i < SENTINEL.length; i += 1) pressKey("BSpace");
  } else if (value.length > SENTINEL.length) {
    typeChars(value.slice(SENTINEL.length));
  }
  input.value = SENTINEL;
});

const liveKeys = { Enter: "Enter", Escape: "Escape", Tab: "Tab", ArrowUp: "Up", ArrowDown: "Down", ArrowLeft: "Left", ArrowRight: "Right",
  Backspace: "BSpace", Delete: "DC", Home: "Home", End: "End", PageUp: "PPage", PageDown: "NPage" };

$("term-cmd").addEventListener("keydown", (event) => {
  if (liveTyping) {
    if (event.ctrlKey && event.key.length === 1) {
      const letter = event.key.toLowerCase();
      if (["c", "d", "l"].includes(letter)) { event.preventDefault(); pressKey(`C-${letter}`); }
      return;
    }
    const key = liveKeys[event.key];
    if (key && key !== "BSpace") { event.preventDefault(); pressKey(key); }
    return;
  }
  if (event.key === "Enter") {
    event.preventDefault();
    const value = $("term-cmd").value;
    $("term-cmd").value = "";
    if (value.trim()) enqueue(toolPath(openTool, "send"), { text: value }).then(() => setTimeout(poll, 300));
    else pressKey("Enter");
  }
});
$("term-form").addEventListener("submit", (event) => event.preventDefault());
document.querySelectorAll(".term-keys button").forEach((button) => {
  button.addEventListener("click", () => { pressKey(button.dataset.key); $("term-cmd").focus(); });
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
  } catch (error) {
    if (error instanceof AuthError) return showPairing(error.message);
    $("pair").hidden = true;
    $("app").hidden = false;
    setConnected(false);
    pollTimer = setTimeout(poll, 2000);
  }
}

start();
