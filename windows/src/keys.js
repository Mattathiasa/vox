// Port of KeyCombo, WebAddress and SearchSite from VoxCore/Desktop/DesktopCommand.swift.
import { words } from "./tokenizer.js";

export const SPECIAL_KEYS = new Set(["return", "tab", "space", "delete", "escape", "up", "down", "left", "right",
  "pageup", "pagedown", "home", "end", "leftbracket", "rightbracket", "equal", "minus", "comma"]);

const MODIFIER_WORDS = { command: "command", cmd: "command", commander: "command", shift: "shift",
  option: "option", alt: "option", opt: "option", control: "control", ctrl: "control" };

const KEY_ALIASES = {
  enter: "return", return: "return", backspace: "delete", delete: "delete",
  esc: "escape", escape: "escape", escaped: "escape", spacebar: "space", space: "space", tab: "tab",
  up: "up", down: "down", left: "left", right: "right", pageup: "pageup", pagedown: "pagedown", home: "home", end: "end",
  equal: "equal", equals: "equal", minus: "minus", dash: "minus", comma: "comma",
  zero: "0", one: "1", two: "2", three: "3", four: "4", five: "5", six: "6", seven: "7", eight: "8", nine: "9",
};

const IGNORED = new Set(["the", "key", "button", "plus", "and", "arrow", "keys"]);
const MOD_ORDER = ["control", "option", "shift", "command"];

export function combo(key, modifiers = []) {
  return { key, modifiers: MOD_ORDER.filter((m) => modifiers.includes(m)) };
}

export function describeCombo(c) {
  return [...MOD_ORDER.filter((m) => c.modifiers.includes(m)), c.key].join("+");
}

/** "command shift t", "ctrl+s", "the enter key" -> combo; null unless exactly one non-modifier key. */
export function parseKeyCombo(spoken) {
  const mods = new Set();
  const keys = [];
  const text = ` ${words(spoken).join(" ")} `.replace(" page up ", " pageup ").replace(" page down ", " pagedown ");
  for (const word of text.split(" ").filter(Boolean)) {
    if (IGNORED.has(word)) continue;
    if (Object.hasOwn(MODIFIER_WORDS, word)) mods.add(MODIFIER_WORDS[word]);
    else if (Object.hasOwn(KEY_ALIASES, word)) keys.push(KEY_ALIASES[word]);
    else if ([...word].length === 1 && /[\p{L}\p{N}]/u.test(word)) keys.push(word);
    else return null;
  }
  if (keys.length !== 1) return null;
  return combo(keys[0], [...mods]);
}

const C = (key, ...mods) => combo(key, mods);

/** Named shortcuts, same order as KeyCombo.named (the index is the matcher value). */
export const NAMED_SHORTCUTS = [
  { phrases: ["close window", "close the window", "close this window"], combo: C("w", "command") },
  { phrases: ["close tab", "close the tab", "close this tab"], combo: C("w", "command") },
  { phrases: ["new tab", "open a new tab", "open new tab"], combo: C("t", "command") },
  { phrases: ["new window", "open a new window", "open new window"], combo: C("n", "command") },
  { phrases: ["reopen tab", "reopen closed tab", "reopen the last tab"], combo: C("t", "command", "shift") },
  { phrases: ["next tab"], combo: C("tab", "control") },
  { phrases: ["previous tab", "last tab"], combo: C("tab", "control", "shift") },
  { phrases: ["minimize", "minimise", "minimize window", "minimize this"], combo: C("m", "command") },
  { phrases: ["full screen", "fullscreen", "toggle full screen", "enter full screen", "exit full screen"], combo: C("f", "control", "command") },
  { phrases: ["hide this", "hide this app", "hide window"], combo: C("h", "command") },
  { phrases: ["quit this app", "quit this", "close this app", "quit the app"], combo: C("q", "command") },
  { phrases: ["go back", "back"], combo: C("leftbracket", "command") },
  { phrases: ["go forward", "forward"], combo: C("rightbracket", "command") },
  { phrases: ["reload", "refresh", "reload page", "refresh page", "reload the page", "refresh the page"], combo: C("r", "command") },
  { phrases: ["copy", "copy that", "copy this"], combo: C("c", "command") },
  { phrases: ["paste", "paste it", "paste that"], combo: C("v", "command") },
  { phrases: ["cut", "cut that", "cut this"], combo: C("x", "command") },
  { phrases: ["undo", "undo that"], combo: C("z", "command") },
  { phrases: ["redo", "redo that"], combo: C("z", "command", "shift") },
  { phrases: ["save", "save it", "save this", "save file", "save the file"], combo: C("s", "command") },
  { phrases: ["select all", "select everything"], combo: C("a", "command") },
  { phrases: ["find", "find in page", "search this page"], combo: C("f", "command") },
  { phrases: ["scroll down", "page down"], combo: C("pagedown") },
  { phrases: ["scroll up", "page up"], combo: C("pageup") },
  { phrases: ["scroll to top", "go to top", "go to the top", "scroll to the top"], combo: C("up", "command") },
  { phrases: ["scroll to bottom", "go to bottom", "go to the bottom", "scroll to the bottom"], combo: C("down", "command") },
  { phrases: ["zoom in"], combo: C("equal", "command") },
  { phrases: ["zoom out"], combo: C("minus", "command") },
  { phrases: ["take a screenshot", "screenshot", "take screenshot"], combo: C("3", "command", "shift") },
  { phrases: ["screenshot selection", "screenshot part of the screen"], combo: C("4", "command", "shift") },
  { phrases: ["lock screen", "lock the screen", "lock my mac", "lock the computer", "lock computer"], combo: C("q", "control", "command") },
  { phrases: ["spotlight", "open spotlight", "search my mac"], combo: C("space", "command") },
  { phrases: ["mission control", "show all windows"], combo: C("up", "control") },
  { phrases: ["app windows", "show app windows"], combo: C("down", "control") },
  { phrases: ["next desktop", "desktop right", "switch desktop right", "next space"], combo: C("right", "control") },
  { phrases: ["previous desktop", "desktop left", "switch desktop left", "previous space"], combo: C("left", "control") },
  { phrases: ["emoji", "emojis", "show emoji", "open emoji picker"], combo: C("space", "control", "command") },
  { phrases: ["switch app", "switch apps", "last app", "previous app"], combo: C("tab", "command") },
  { phrases: ["new line", "newline", "next line"], combo: C("return") },
  { phrases: ["new paragraph"], combo: C("return", "shift") },
  { phrases: ["delete word", "delete last word", "delete the last word"], combo: C("delete", "option") },
  { phrases: ["delete line", "delete the line", "clear line"], combo: C("delete", "command") },
  { phrases: ["bold", "make it bold"], combo: C("b", "command") },
  { phrases: ["italic", "italics", "make it italic"], combo: C("i", "command") },
  { phrases: ["underline", "underline it"], combo: C("u", "command") },
  { phrases: ["go to start of line", "start of line", "beginning of line"], combo: C("left", "command") },
  { phrases: ["go to end of line", "end of line"], combo: C("right", "command") },
  { phrases: ["preferences", "settings for this app", "open preferences", "app settings"], combo: C("comma", "command") },
  { phrases: ["print", "print this"], combo: C("p", "command") },
  { phrases: ["close all windows"], combo: C("w", "command", "option") },
  { phrases: ["new folder"], combo: C("n", "command", "shift") },
  { phrases: ["new document", "new file"], combo: C("n", "command") },
  { phrases: ["open file", "open a file"], combo: C("o", "command") },
  { phrases: ["private window", "new private window", "incognito"], combo: C("n", "command", "shift") },
  { phrases: ["address bar", "focus address bar", "go to address bar"], combo: C("l", "command") },
  { phrases: ["bookmark this", "bookmark this page", "add bookmark"], combo: C("d", "command") },
];

// MARK: Web addresses

export function urlFromSpoken(spoken) {
  let s = ` ${spoken.toLowerCase()} `;
  s = s.split(" dot ").join(".");
  s = s.split(" slash ").join("/");
  s = s.split(/\s+/).join("");
  s = s.replace(/^[.,!?;:]+|[.,!?;:]+$/g, "");
  if (!(s.startsWith("http://") || s.startsWith("https://"))) s = `https://${s}`;
  let url;
  try { url = new URL(s); } catch { return null; }
  if (!["http:", "https:"].includes(url.protocol)) return null;
  const host = url.hostname;
  if (!host.includes(".") || !/^[a-z0-9.-]+$/i.test(host) || host.split(".").some((part) => part === "")) return null;
  return url.href;
}

export const encodeQuery = (query) => encodeURIComponent(query.trim());
export const searchURL = (query) => `https://www.google.com/search?q=${encodeQuery(query)}`;

export const KNOWN_SITES = {
  youtube: "https://www.youtube.com", "you tube": "https://www.youtube.com",
  gmail: "https://mail.google.com", google: "https://www.google.com",
  "google drive": "https://drive.google.com", drive: "https://drive.google.com",
  "google docs": "https://docs.google.com", "google calendar": "https://calendar.google.com",
  github: "https://github.com", "git hub": "https://github.com",
  chatgpt: "https://chatgpt.com", "chat gpt": "https://chatgpt.com",
  "claude dot ai": "https://claude.ai", "claude ai": "https://claude.ai",
  twitter: "https://x.com", linkedin: "https://www.linkedin.com", "linked in": "https://www.linkedin.com",
  facebook: "https://www.facebook.com", instagram: "https://www.instagram.com",
  reddit: "https://www.reddit.com", netflix: "https://www.netflix.com",
  "stack overflow": "https://stackoverflow.com", stackoverflow: "https://stackoverflow.com",
  "whatsapp web": "https://web.whatsapp.com", "telegram web": "https://web.telegram.org",
  vercel: "https://vercel.com", supabase: "https://supabase.com/dashboard",
  firebase: "https://console.firebase.google.com", lovable: "https://lovable.dev",
  twitch: "https://www.twitch.tv", discord: "https://discord.com/app",
};

export function knownSite(spoken) {
  const list = words(spoken);
  while (list.length && ["website", "site", "dot", "com"].includes(list[list.length - 1])) list.pop();
  return KNOWN_SITES[list.join(" ")] || null;
}

export const SEARCH_SITES = {
  youtube: { phrases: ["youtube", "you tube"], base: "https://www.youtube.com/results?search_query=" },
  github: { phrases: ["github", "git hub"], base: "https://github.com/search?q=" },
  amazon: { phrases: ["amazon"], base: "https://www.amazon.com/s?k=" },
  wikipedia: { phrases: ["wikipedia", "wiki"], base: "https://en.wikipedia.org/w/index.php?search=" },
  maps: { phrases: ["maps", "the map", "apple maps", "google maps", "map"], base: "https://www.google.com/maps/search/" },
  images: { phrases: ["images", "google images", "pictures"], base: "https://www.google.com/search?tbm=isch&q=" },
  reddit: { phrases: ["reddit"], base: "https://www.reddit.com/search/?q=" },
  stackoverflow: { phrases: ["stack overflow", "stackoverflow"], base: "https://stackoverflow.com/search?q=" },
};

export const siteURL = (site, query) => SEARCH_SITES[site].base + encodeQuery(query);
