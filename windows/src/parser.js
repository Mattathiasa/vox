// Port of VoxCore/Parsing/{CommandParser,MoreCommands,IDECommands}.swift.
// Intents and desktop commands are plain objects; see canonical.js for their one-line form.
import { tokenize, remainder, span, PhraseMatcher, indexedMatcher } from "./tokenizer.js";
import { parseDuration, evaluateMath } from "./spoken.js";
import { NAMED_SHORTCUTS, parseKeyCombo, urlFromSpoken, SEARCH_SITES } from "./keys.js";

const P = (list) => new PhraseMatcher(list);

// MARK: Vocabulary (CommandParser.swift)
const FILLERS = new Set(["please", "hey", "ok", "okay", "um", "uh", "so", "now"]);
const ARTICLES = new Set(["the", "my", "a"]);
const PROJECT_NOUNS = new Set(["project", "folder", "repo", "repository", "directory", "app"]);
const APP_NOUNS = new Set(["app", "application"]);

const launchVerbs = P(["run", "start", "launch", "open", "fire up", "spin up", "boot up", "start up"]);
const focusVerbs = P(["switch to", "go to", "talk to", "use", "attach to", "focus", "focus on", "back to"]);
const killVerbs = P(["kill", "close", "quit", "stop", "end", "shut down", "terminate"]);
const listPhrases = P(["list", "list sessions", "sessions", "show sessions", "status", "whats running", "what is running"]);
const openVerbs = P(["open", "launch", "start", "fire up", "start up", "bring up"]);
const clauseBreaks = P(["and then", "then", "and"]);
const noteVerbs = P(["create a note", "create a new note", "create note", "create new note", "make a note", "make a new note",
  "make note", "new note", "add a note", "write a note", "take a note", "note down", "jot down"]);
const noteConnectors = P(["called", "titled", "named", "saying", "that says", "which says", "with", "about", "to"]);
const searchVerbs = P(["search for", "search the web for", "search google for", "google search", "search", "google", "look up"]);
const urlVerbs = P(["go to", "visit", "browse to", "navigate to", "open website", "open the website", "open site", "open the site"]);
const hideVerbs = P(["hide"]);
const cancelPhrases = P(["never mind", "nevermind", "cancel", "cancel that", "forget it", "nothing", "stop that", "ignore that"]);
const helpPhrases = P(["help", "what can you do", "what can i say", "what can i ask", "show commands", "list commands"]);
const namedShortcuts = indexedMatcher(NAMED_SHORTCUTS);
const VOLUME_COMMANDS = [
  { phrases: ["volume up", "turn up the volume", "turn the volume up", "louder", "increase the volume", "increase volume", "raise the volume"], change: "up" },
  { phrases: ["volume down", "turn down the volume", "turn the volume down", "quieter", "softer", "lower the volume", "decrease the volume", "decrease volume"], change: "down" },
  { phrases: ["mute", "mute sound", "mute the sound", "mute volume", "mute the volume"], change: "mute" },
  { phrases: ["unmute", "unmute sound", "unmute the sound", "unmute volume", "unmute the volume"], change: "unmute" },
];
const volumeMatcher = indexedMatcher(VOLUME_COMMANDS);
const setVolumePrefixes = P(["set volume to", "set the volume to", "set volume", "volume to", "volume at", "volume"]);
const typeVerbs = P(["type", "type in", "type out"]);
const pressVerbs = P(["press", "hit", "push the", "tap"]);
const locationWords = P(["in", "on", "for", "inside", "at"]);
const connectors = P(["and", "then", "and then", "to", "with", "and tell it to", "and ask it to", "tell it to", "ask it to", "and have it", "and say"]);

// MARK: Vocabulary (MoreCommands.swift)
const MEDIA = [
  { phrases: ["play", "pause", "resume", "play music", "pause music", "resume music", "pause the music", "stop the music", "play pause", "play the music"], key: "playPause" },
  { phrases: ["next", "next track", "next song", "skip", "skip song", "skip this song", "skip track"], key: "next" },
  { phrases: ["previous track", "previous song", "last song", "go back a song", "play the last song"], key: "previous" },
];
const mediaMatcher = indexedMatcher(MEDIA);
const QUESTIONS = [
  { phrases: ["what time is it", "whats the time", "what is the time", "tell me the time", "time", "current time", "the time"], q: "time" },
  { phrases: ["whats the date", "what is the date", "what day is it", "whats today", "todays date", "whats todays date", "what is today", "date", "the date"], q: "date" },
  { phrases: ["battery", "how much battery", "how much battery do i have", "battery level", "hows my battery", "battery status", "whats my battery", "whats the battery", "how is the battery"], q: "battery" },
  { phrases: ["read clipboard", "read my clipboard", "read the clipboard", "whats on my clipboard", "whats in my clipboard", "whats on the clipboard", "clipboard"], q: "clipboard" },
  { phrases: ["what apps are open", "which apps are open", "whats open", "list open apps", "open apps", "what apps are running", "which apps are running"], q: "openApps" },
];
const questionMatcher = indexedMatcher(QUESTIONS);
const mathVerbs = P(["whats", "what is", "calculate", "compute", "how much is", "what does"]);
const timerVerbs = P(["set a timer for", "set timer for", "start a timer for", "start timer for", "timer for", "set a timer",
  "start a timer", "set an alarm for", "countdown", "count down"]);
const cancelTimerPhrases = P(["cancel timer", "cancel the timer", "cancel timers", "cancel all timers", "cancel my timer",
  "stop timer", "stop the timer", "stop timers", "stop all timers", "clear timers"]);
const reminderVerbs = P(["remind me to", "remind me", "add a reminder to", "add a reminder", "create a reminder to",
  "create a reminder", "new reminder", "set a reminder to", "set a reminder", "reminder to"]);
const STANDARD_FOLDERS = new Set(["downloads", "documents", "desktop", "home", "applications", "projects", "pictures", "movies", "music"]);
const UNAMBIGUOUS_FOLDERS = new Set(["downloads", "documents", "projects", "home"]);
const FOLDER_NOUNS = new Set(["folder", "directory"]);
const showVerbs = P(["show", "show me", "reveal"]);
const withWords = P(["in", "with", "using"]);
const sitePhrases = new PhraseMatcher(Object.entries(SEARCH_SITES).map(([value, site]) => ({ value, phrases: site.phrases })));
const playVerbs = P(["play", "watch", "find"]);
const directionsVerbs = P(["directions to", "get directions to", "how do i get to", "where is", "show me on the map", "find on the map", "map of"]);
const DARK_MODE = [
  { phrases: ["dark mode", "toggle dark mode", "switch dark mode"], on: null },
  { phrases: ["turn on dark mode", "enable dark mode", "dark mode on", "go dark"], on: true },
  { phrases: ["turn off dark mode", "disable dark mode", "dark mode off", "light mode", "turn on light mode"], on: false },
];
const darkModeMatcher = indexedMatcher(DARK_MODE);
const screenOffPhrases = P(["turn off the screen", "turn off screen", "screen off", "turn off the display", "turn off display",
  "sleep display", "sleep the display", "sleep screen"]);
const interruptPhrases = P(["interrupt", "stop it", "stop generating", "control c", "ctrl c", "abort", "cancel it"]);
const interruptVerbs = P(["interrupt", "stop"]);
const restartVerbs = P(["restart", "relaunch", "reboot", "reload"]);
const watchVerbs = P(["show", "watch", "view", "show me"]);
const tellToolVerbs = P(["tell", "ask", "message", "say to"]);
const ideNames = P(["antigravity", "kiro", "visual studio code", "cursor", "windsurf", "vscodium"]);
const CLAUDE_DESKTOP_NOUNS = new Set(["desktop", "app", "application"]);
const safariTabPhrases = P(["read safari tab", "safari tab", "safari url", "what url is this", "what's the url"]);
const claudeDesktopPhrases = P(["claude desktop", "claude app"]);

// MARK: Vocabulary (IDECommands.swift)
const terminalNouns = P(["terminals", "terminal", "terminal windows", "terminal window", "terminal panes", "terminal pane",
  "terminal tabs", "terminal tab", "terminal splits", "shells", "shell"]);
const openTerminalVerbs = P(["open", "open up", "create", "make", "start", "spawn", "add", "give me", "launch", "bring up"]);
const sideBySide = P(["side by side", "next to each other", "in a split", "split", "in split view", "in parallel", "split side by side", "in a row"]);
const runningWords = P(["running", "that run", "to run", "with"]);
const terminalRunVerbs = P(["run", "start", "execute", "launch", "type and run", "write and run", "enter and run", "send"]);
const terminalTypeVerbs = P(["type", "write", "type in", "enter"]);
const tellVerbs = P(["tell", "ask"]);
const TARGET_PREPOSITIONS = new Set(["in", "on", "inside", "into", "to", "at"]);
const ORDINALS = { first: 1, "1st": 1, second: 2, "2nd": 2, third: 3, "3rd": 3, fourth: 4, "4th": 4, fifth: 5, "5th": 5, sixth: 6, "6th": 6, left: 1, middle: 2 };
const NUMBER_WORDS = { one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8 };
const closeTerminalPhrases = P(["close the terminals", "close all terminals", "close all the terminals", "close terminals",
  "kill the terminals", "kill all terminals", "kill all the terminals", "close the vox terminals", "close all vox terminals"]);

const isInt = (word) => /^[+-]?\d+$/.test(word);
const toInt = (word) => (isInt(word) ? Number(word) : null);

export class CommandParser {
  constructor(config) {
    this.tools = new PhraseMatcher(config.tools.map((t) => ({ value: t.name, phrases: [t.name, ...(t.aliases || [])] })));
    this.projects = new PhraseMatcher(config.projects.map((p) => ({ value: p.name, phrases: [p.name, ...(p.aliases || [])] })));
    this.exitPhrases = P(config.exitPhrases);
    this.prefixes = P(config.commandPrefixes);
    this.affirmatives = P(config.affirmativePhrases);
  }

  isExit(text) { const t = tokenize(text); return t.length > 0 && this.exitPhrases.matchesWhole(t); }
  isAffirmative(text) { const t = tokenize(text); return t.length > 0 && this.affirmatives.matchesWhole(t); }
  isInterrupt(text) { const t = tokenize(text); return t.length > 0 && interruptPhrases.matchesWhole(t); }

  /** Text after a leading command prefix ("vox …"); "" when the prefix is all there is; null without one. */
  strippingPrefix(text) {
    const tokens = tokenize(text);
    const m = this.prefixes.match(tokens, 0);
    if (!m) return null;
    return remainder(text, tokens, m.length) ?? "";
  }

  parse(text) {
    const tokens = tokenize(text);
    let i = 0;
    const p = this.prefixes.match(tokens, i);
    if (p) i += p.length;
    while (i < tokens.length && FILLERS.has(tokens[i].norm)) i += 1;
    if (i >= tokens.length) return { type: "unknown" };
    const rest = tokens.slice(i);

    if (this.exitPhrases.matchesWhole(rest)) return { type: "exit" };
    if (listPhrases.matchesWhole(rest)) return { type: "list" };
    if (cancelPhrases.matchesWhole(rest)) return { type: "cancel" };
    if (helpPhrases.matchesWhole(rest)) return { type: "help" };
    const toolIntent = this.parseToolControl(text, tokens, i);
    if (toolIntent) return toolIntent;

    const commands = this.parseDesktopClause(text, tokens, i);
    if (commands) return { type: "desktop", commands, unparsed: null };

    let verb = launchVerbs.match(tokens, i);
    if (verb) {
      const j = this.skipArticles(tokens, i + verb.length);
      const tool = this.tools.match(tokens, j);
      if (tool && !this.isAppNoun(tokens, j + tool.length)) return this.parseLaunch(text, tokens, i + verb.length);
      if (openVerbs.match(tokens, i)) {
        const intent = this.parseAppClause(text, tokens, j, (name) => ({ type: "openApp", name }));
        if (intent) return intent;
      }
      return this.unknownTool(text, tokens, j);
    }
    verb = focusVerbs.match(tokens, i);
    if (verb) {
      const j = this.skipArticles(tokens, i + verb.length);
      const tool = this.tools.match(tokens, j);
      if (tool && !this.isAppNoun(tokens, j + tool.length)) return { type: "focus", tool: tool.value };
      const intent = this.parseAppClause(text, tokens, j, (name) => ({ type: "focusApp", name }));
      if (intent) return intent;
      return this.unknownTool(text, tokens, j);
    }
    verb = killVerbs.match(tokens, i);
    if (verb) {
      const j = this.skipArticles(tokens, i + verb.length);
      const tool = this.tools.match(tokens, j);
      if (tool && !this.isAppNoun(tokens, j + tool.length)) return { type: "kill", tool: tool.value };
      const intent = this.parseAppClause(text, tokens, j, (name) => ({ type: "quitApp", name }));
      if (intent) return intent;
      return this.unknownTool(text, tokens, j);
    }
    const tool = this.tools.match(tokens, i);
    if (tool && tool.length === rest.length) return { type: "focus", tool: tool.value };
    return { type: "unknown" };
  }

  parseLaunch(text, tokens, start) {
    let j = this.skipArticles(tokens, start);
    const tool = this.tools.match(tokens, j);
    if (!tool) return this.unknownTool(text, tokens, j);
    j += tool.length;
    let project = null;
    const loc = locationWords.match(tokens, j);
    if (loc) {
      let k = this.skipArticles(tokens, j + loc.length);
      const p = this.projects.match(tokens, k);
      if (p) {
        project = p.value;
        k += p.length;
        if (k < tokens.length && PROJECT_NOUNS.has(tokens[k].norm)) k += 1;
        j = k;
      } else {
        return { type: "unknownProject", spoken: remainder(text, tokens, k) ?? "" };
      }
    }
    const c = connectors.match(tokens, j);
    if (c) j += c.length;
    return { type: "launch", tool: tool.value, project, prompt: remainder(text, tokens, j) };
  }

  isAppNoun(tokens, index) { return index < tokens.length && APP_NOUNS.has(tokens[index].norm); }

  parseAppClause(text, tokens, start, make) {
    let k = start;
    const nameTokens = [];
    const breakLength = (at) => {
      const brk = clauseBreaks.match(tokens, at);
      if (brk) return brk.length;
      if (tokens[at].norm === "with" && this.terminalCount(tokens, at + 1)) return 1;
      return null;
    };
    while (k < tokens.length && breakLength(k) === null) { nameTokens.push(tokens[k]); k += 1; }
    while (nameTokens.length && APP_NOUNS.has(nameTokens[nameTokens.length - 1].norm)) nameTokens.pop();
    if (!nameTokens.length) return null;
    const name = text.slice(nameTokens[0].start, nameTokens[nameTokens.length - 1].end);
    let commands = [make(name)];
    let unparsed = null;
    if (k < tokens.length) {
      const length = breakLength(k);
      if (length !== null) {
        const next = k + length;
        const more = this.parseDesktopClause(text, tokens, next);
        if (more) commands = commands.concat(more);
        else unparsed = remainder(text, tokens, next);
      }
    }
    return { type: "desktop", commands, unparsed };
  }

  parseDesktopClause(text, tokens, i) {
    if (i >= tokens.length) return null;
    const extra = this.parseExtraClause(text, tokens, i);
    if (extra) return extra;

    let first = this.wholeClause(namedShortcuts, tokens, i);
    if (first) return this.chain([{ type: "pressKey", combo: NAMED_SHORTCUTS[Number(first.value)].combo }], text, tokens, first.end);
    first = this.wholeClause(volumeMatcher, tokens, i);
    if (first) return this.chain([{ type: "volume", change: VOLUME_COMMANDS[Number(first.value)].change }], text, tokens, first.end);
    const prefix = setVolumePrefixes.match(tokens, i);
    if (prefix) {
      let k = i + prefix.length;
      const level = k < tokens.length ? toInt(tokens[k].norm) : null;
      if (level !== null && level >= 0 && level <= 100) {
        k += 1;
        if (k < tokens.length && tokens[k].norm === "percent") k += 1;
        if (k === tokens.length || clauseBreaks.match(tokens, k)) return this.chain([{ type: "volume", change: `set ${level}` }], text, tokens, k);
      }
    }
    const hide = hideVerbs.match(tokens, i);
    if (hide) {
      const intent = this.parseAppClause(text, tokens, this.skipArticles(tokens, i + hide.length), (name) => ({ type: "hideApp", name }));
      if (intent && intent.unparsed === null) return intent.commands;
    }
    const note = noteVerbs.match(tokens, i);
    if (note) {
      let j = i + note.length;
      const c = noteConnectors.match(tokens, j);
      if (c) j += c.length;
      return [{ type: "createNote", text: remainder(text, tokens, j) ?? "" }];
    }
    const urlVerb = urlVerbs.match(tokens, i);
    if (urlVerb) {
      const rest = remainder(text, tokens, i + urlVerb.length);
      if (rest && urlFromSpoken(rest)) return [{ type: "openURL", spoken: rest }];
    }
    const search = searchVerbs.match(tokens, i);
    if (search) {
      const query = remainder(text, tokens, i + search.length);
      if (query) return [{ type: "webSearch", query }];
    }
    const type = typeVerbs.match(tokens, i);
    if (type) {
      const start = i + type.length;
      if (start >= tokens.length) return null;
      for (let k = start + 1; k < tokens.length; k += 1) {
        const brk = clauseBreaks.match(tokens, k);
        if (!brk) continue;
        const press = pressVerbs.match(tokens, k + brk.length);
        if (!press) continue;
        const keys = remainder(text, tokens, k + brk.length + press.length);
        const combo = keys && parseKeyCombo(keys);
        if (combo) return [{ type: "typeText", text: span(text, tokens, start, k) }, { type: "pressKey", combo }];
      }
      const typed = remainder(text, tokens, start);
      return typed ? [{ type: "typeText", text: typed }] : null;
    }
    const press = pressVerbs.match(tokens, i);
    if (press) {
      const keys = remainder(text, tokens, i + press.length);
      const combo = keys && parseKeyCombo(keys);
      if (combo) return [{ type: "pressKey", combo }];
    }
    return null;
  }

  wholeClause(matcher, tokens, i) {
    const m = matcher.match(tokens, i);
    if (!m) return null;
    const end = i + m.length;
    if (end !== tokens.length && !clauseBreaks.match(tokens, end)) return null;
    return { value: m.value, end };
  }

  chain(commands, text, tokens, end) {
    if (end >= tokens.length) return commands;
    const brk = clauseBreaks.match(tokens, end);
    if (!brk) return commands;
    const more = this.parseDesktopClause(text, tokens, end + brk.length);
    return more ? commands.concat(more) : null;
  }

  skipArticles(tokens, index) {
    let j = index;
    while (j < tokens.length && ARTICLES.has(tokens[j].norm)) j += 1;
    return j;
  }

  unknownTool(text, tokens, index) {
    const spoken = remainder(text, tokens, index);
    return spoken ? { type: "unknownTool", spoken } : { type: "unknown" };
  }

  // MARK: MoreCommands.swift

  parseToolControl(text, tokens, i) {
    const rest = tokens.slice(i);
    if (interruptPhrases.matchesWhole(rest)) return { type: "interrupt", tool: null };

    const tell = tellToolVerbs.match(tokens, i);
    if (tell) {
      let j = this.skipArticles(tokens, i + tell.length);
      const tool = this.tools.match(tokens, j);
      const claudeApp = tool && tool.value === "claude" && j + tool.length < tokens.length && CLAUDE_DESKTOP_NOUNS.has(tokens[j + tool.length].norm);
      if (tool && !claudeApp) {
        j += tool.length;
        if (j < tokens.length && tokens[j].norm === "to") j += 1;
        const message = remainder(text, tokens, j);
        if (message) return { type: "tell", tool: tool.value, text: message };
      } else {
        // No tool here (or "claude desktop"): maybe an IDE's AI chat.
        const ide = ideNames.match(tokens, j);
        if (ide) {
          j += ide.length;
          if (j < tokens.length && tokens[j].norm === "to") j += 1;
          const message = remainder(text, tokens, j);
          if (message) return { type: "desktop", commands: [{ type: "ide", ide: { op: "chat", message, submit: true } }], unparsed: null };
        }
      }
    }

    const interrupt = interruptVerbs.match(tokens, i);
    if (interrupt) {
      const j = this.skipArticles(tokens, i + interrupt.length);
      const tool = this.tools.match(tokens, j);
      if (tool && j + tool.length === tokens.length && interrupt.value === "interrupt") return { type: "interrupt", tool: tool.value };
    }
    const restart = restartVerbs.match(tokens, i);
    if (restart) {
      const j = this.skipArticles(tokens, i + restart.length);
      const tool = this.tools.match(tokens, j);
      if (tool && j + tool.length === tokens.length) return { type: "restart", tool: tool.value };
    }
    const watch = watchVerbs.match(tokens, i);
    if (watch) {
      const j = this.skipArticles(tokens, i + watch.length);
      const tool = this.tools.match(tokens, j);
      if (tool && j + tool.length === tokens.length) return { type: "show", tool: tool.value };
    }
    return null;
  }

  parseExtraClause(text, tokens, i) {
    if (i >= tokens.length) return null;
    const ide = this.parseIDEClause(text, tokens, i);
    if (ide) return ide;

    let m = this.wholeClause(safariTabPhrases, tokens, i);
    if (m) return this.chain([{ type: "safariReadTab" }], text, tokens, m.end);

    const tell = tellToolVerbs.match(tokens, i);
    if (tell) {
      const target = claudeDesktopPhrases.match(tokens, i + tell.length);
      if (target) {
        let j = i + tell.length + target.length;
        if (j < tokens.length && tokens[j].norm === "to") j += 1;
        const message = remainder(text, tokens, j);
        if (message) return [{ type: "sendMessageToApp", app: "claude", text: message }];
      }
    }

    m = this.wholeClause(mediaMatcher, tokens, i);
    if (m) return this.chain([{ type: "media", key: MEDIA[Number(m.value)].key }], text, tokens, m.end);
    m = this.wholeClause(questionMatcher, tokens, i);
    if (m) return this.chain([{ type: "answer", question: QUESTIONS[Number(m.value)].q }], text, tokens, m.end);
    m = this.wholeClause(darkModeMatcher, tokens, i);
    if (m) return this.chain([{ type: "system", action: "darkMode", on: DARK_MODE[Number(m.value)].on }], text, tokens, m.end);
    m = this.wholeClause(screenOffPhrases, tokens, i);
    if (m) return this.chain([{ type: "system", action: "screenOff" }], text, tokens, m.end);
    m = this.wholeClause(cancelTimerPhrases, tokens, i);
    if (m) return this.chain([{ type: "cancelTimers" }], text, tokens, m.end);

    const timer = timerVerbs.match(tokens, i);
    if (timer) {
      let j = i + timer.length;
      if (j < tokens.length && tokens[j].norm === "for") j += 1;
      const d = parseDuration(tokens, j);
      if (d && d.end === tokens.length) return [{ type: "timer", seconds: d.seconds }];
    }
    const lead = parseDuration(tokens, i);
    if (lead && lead.end + 1 === tokens.length && tokens[lead.end].norm === "timer") return [{ type: "timer", seconds: lead.seconds }];

    const reminder = reminderVerbs.match(tokens, i);
    if (reminder) return this.parseReminder(text, tokens, i + reminder.length);

    const search = searchVerbs.match(tokens, i);
    if (search) {
      let j = i + search.length;
      const site = sitePhrases.match(tokens, j);
      if (site) {
        j += site.length;
        if (j < tokens.length && tokens[j].norm === "for") j += 1;
        const query = remainder(text, tokens, j);
        if (query) return [{ type: "siteSearch", site: site.value, query }];
      }
      const split = this.splitTrailingSite(text, tokens, j);
      if (split) return [{ type: "siteSearch", site: split.site, query: split.query }];
    }
    const play = playVerbs.match(tokens, i);
    if (play) {
      const split = this.splitTrailingSite(text, tokens, i + play.length);
      if (split) return [{ type: "siteSearch", site: split.site, query: split.query }];
    }
    const directions = directionsVerbs.match(tokens, i);
    if (directions) {
      const place = remainder(text, tokens, i + directions.length);
      if (place) return [{ type: "siteSearch", site: "maps", query: place }];
    }

    const open = openVerbs.match(tokens, i) || showVerbs.match(tokens, i);
    if (open) {
      const result = this.parseFolderOrProject(text, tokens, this.skipArticles(tokens, i + open.length));
      if (result) return result;
    }

    const math = mathVerbs.match(tokens, i);
    if (math) {
      const expression = remainder(text, tokens, i + math.length);
      if (expression && evaluateMath(expression) !== null) return [{ type: "answer", question: "calculation", expression }];
    }
    const whole = remainder(text, tokens, i);
    if (whole && /^\p{N}/u.test(tokens[i].norm) && evaluateMath(whole) !== null) {
      return [{ type: "answer", question: "calculation", expression: whole }];
    }
    return null;
  }

  parseReminder(text, tokens, start) {
    let j = start;
    let due = null;
    const lead = j < tokens.length && tokens[j].norm === "in" ? parseDuration(tokens, j + 1) : null;
    if (lead) {
      due = lead.seconds;
      j = lead.end;
      if (j < tokens.length && tokens[j].norm === "to") j += 1;
    } else if (j < tokens.length && tokens[j].norm === "to") {
      j += 1;
    }
    if (j >= tokens.length) return null;
    let end = tokens.length;
    if (due === null) {
      for (let k = tokens.length - 2; k > j; k -= 1) {
        if (tokens[k].norm !== "in") continue;
        const d = parseDuration(tokens, k + 1);
        if (d && d.end === tokens.length) { due = d.seconds; end = k; break; }
      }
    }
    if (end <= j) return null;
    return [{ type: "reminder", text: span(text, tokens, j, end), seconds: due }];
  }

  splitTrailingSite(text, tokens, start) {
    for (let k = tokens.length - 1; k > start; k -= 1) {
      if (!["on", "in"].includes(tokens[k].norm)) continue;
      const site = sitePhrases.match(tokens, k + 1);
      if (site && k + 1 + site.length === tokens.length) return { query: span(text, tokens, start, k), site: site.value };
    }
    return null;
  }

  parseFolderOrProject(text, tokens, j) {
    if (j >= tokens.length) return null;
    const name = tokens[j].norm;
    if (STANDARD_FOLDERS.has(name)) {
      let k = j + 1;
      const saidFolder = k < tokens.length && FOLDER_NOUNS.has(tokens[k].norm);
      if (saidFolder) k += 1;
      if ((saidFolder || UNAMBIGUOUS_FOLDERS.has(name)) && (k === tokens.length || clauseBreaks.match(tokens, k))) {
        return this.chain([{ type: "openFolder", name }], text, tokens, k);
      }
    }
    const project = this.projects.match(tokens, j);
    if (!project) return null;
    let k = j + project.length;
    const saidNoun = k < tokens.length && PROJECT_NOUNS.has(tokens[k].norm);
    if (saidNoun) k += 1;
    const w = withWords.match(tokens, k);
    if (w) {
      const appStart = k + w.length;
      let end = appStart;
      while (end < tokens.length && !clauseBreaks.match(tokens, end)) end += 1;
      if (end <= appStart) return null;
      return this.chain([{ type: "openProject", project: project.value, app: span(text, tokens, appStart, end) }], text, tokens, end);
    }
    if (saidNoun && (k === tokens.length || clauseBreaks.match(tokens, k))) {
      return this.chain([{ type: "openFolder", name: project.value }], text, tokens, k);
    }
    return null;
  }

  // MARK: IDECommands.swift

  parseIDEClause(text, tokens, i) {
    if (i >= tokens.length) return null;
    const close = this.wholeClause(closeTerminalPhrases, tokens, i);
    if (close) return this.chain([ideCmd({ op: "closeTerminals" })], text, tokens, close.end);
    const open = this.parseOpenTerminals(text, tokens, i);
    if (open) return open;

    if (tokens[i].norm === "open") {
      const j = i + 1;
      if (j < tokens.length && tokens[j].norm === "file") {
        const path = remainder(text, tokens, j + 1);
        if (path) return [ideCmd({ op: "openFile", path })];
      }
      if (j < tokens.length && tokens[j].norm === "folder") {
        const path = remainder(text, tokens, j + 1);
        if (path) return [ideCmd({ op: "openFolder", path })];
      }
    }
    let run = terminalRunVerbs.match(tokens, i);
    if (run) {
      const j = i + run.length;
      if (j < tokens.length && tokens[j].norm === "task") {
        const name = remainder(text, tokens, j + 1);
        if (name) return [ideCmd({ op: "runTask", name })];
      }
    }
    if (TARGET_PREPOSITIONS.has(tokens[i].norm)) {
      const target = this.parseTerminalTarget(tokens, i + 1);
      if (target) {
        let j = target.end;
        run = terminalRunVerbs.match(tokens, j);
        if (run) {
          j += run.length;
          const command = remainder(text, tokens, j);
          if (!command) return null;
          return [ideCmd({ op: "send", target: target.target, text: command, submit: true })];
        }
        const type = terminalTypeVerbs.match(tokens, j);
        if (type) {
          j += type.length;
          const command = remainder(text, tokens, j);
          if (!command) return null;
          return [ideCmd({ op: "send", target: target.target, text: command, submit: false })];
        }
      }
    }
    const tell = tellVerbs.match(tokens, i);
    if (tell) {
      const target = this.parseTerminalTarget(tokens, i + tell.length);
      if (target) {
        let j = target.end;
        if (j < tokens.length && tokens[j].norm === "to") j += 1;
        const message = remainder(text, tokens, j);
        if (!message) return null;
        return [ideCmd({ op: "send", target: target.target, text: message, submit: true })];
      }
    }
    run = terminalRunVerbs.match(tokens, i);
    if (run) return this.parseSendList(text, tokens, i + run.length, true);
    const type = terminalTypeVerbs.match(tokens, i);
    if (type) return this.parseSendList(text, tokens, i + type.length, false);
    return null;
  }

  parseOpenTerminals(text, tokens, i) {
    let j = i;
    if (tokens[j].norm === "split") {
      let k = this.skipArticles(tokens, j + 1);
      const noun = terminalNouns.match(tokens, k);
      if (noun) {
        k += noun.length;
        if (k < tokens.length && ["into", "in"].includes(tokens[k].norm)) {
          const n = this.count(tokens, k + 1);
          if (n !== null) return this.chain([ideCmd({ op: "openTerminals", count: n, commands: [] })], text, tokens, k + 2);
        }
      }
      return null;
    }
    const verb = openTerminalVerbs.match(tokens, j);
    if (verb) j += verb.length;
    const counted = this.terminalCount(tokens, j);
    if (!counted) return null;
    const [n] = counted;
    let k = counted[1];
    const side = sideBySide.match(tokens, k);
    if (side) k += side.length;
    const running = runningWords.match(tokens, k);
    if (running) {
      const list = remainder(text, tokens, k + running.length);
      if (list) {
        const commands = splitList(list);
        if (commands.length) return [ideCmd({ op: "openTerminals", count: Math.max(n, commands.length), commands })];
      }
    }
    return this.chain([ideCmd({ op: "openTerminals", count: n, commands: [] })], text, tokens, k);
  }

  terminalCount(tokens, k) {
    const n = this.count(tokens, k);
    if (n === null) return null;
    let e = k + 1;
    while (e < tokens.length && ["new", "more", "extra", "separate", "vox"].includes(tokens[e].norm)) e += 1;
    const noun = terminalNouns.match(tokens, e);
    if (!noun) return null;
    return [n, e + noun.length];
  }

  count(tokens, k) {
    if (k >= tokens.length) return null;
    const word = tokens[k].norm;
    const n = toInt(word) ?? NUMBER_WORDS[word] ?? (["a", "an", "another"].includes(word) ? 1 : null);
    if (n === null || n === undefined || n < 1 || n > 8) return null;
    return n;
  }

  parseTerminalTarget(tokens, start) {
    let j = start;
    if (j >= tokens.length) return null;
    if (["one", "any", "either", "each"].includes(tokens[j].norm) && j + 1 < tokens.length && tokens[j + 1].norm === "of") {
      j = this.skipArticles(tokens, j + 2);
      while (j < tokens.length && ["vox", "open", "new"].includes(tokens[j].norm)) j += 1;
      const noun = terminalNouns.match(tokens, j);
      if (!noun) return null;
      return { target: "any", end: j + noun.length };
    }
    let hadArticle = false;
    if (["a", "an", "any", "another", "the", "my"].includes(tokens[j].norm)) { j += 1; hadArticle = true; }
    while (j < tokens.length && ["new", "vox", "free", "empty"].includes(tokens[j].norm)) j += 1;
    if (j >= tokens.length) return null;
    if (Object.hasOwn(ORDINALS, tokens[j].norm)) {
      const n = ORDINALS[tokens[j].norm];
      let e = j + 1;
      const noun = terminalNouns.match(tokens, e);
      if (noun) e += noun.length;
      else if (e < tokens.length && tokens[e].norm === "one") e += 1;
      else if (!hadArticle) return null;
      return { target: n, end: e };
    }
    const noun = terminalNouns.match(tokens, j);
    if (noun) {
      let e = j + noun.length;
      if (e < tokens.length && tokens[e].norm === "number") e += 1;
      if (e < tokens.length) {
        const n = toInt(tokens[e].norm) ?? NUMBER_WORDS[tokens[e].norm];
        if (n !== undefined && n !== null) return { target: n, end: e + 1 };
      }
      return { target: "any", end: e };
    }
    return null;
  }

  parseSendList(text, tokens, start, submit) {
    const commands = [];
    let begin = start;
    let consumed = start;
    let currentSubmit = submit;
    while (begin < tokens.length) {
      let found = null;
      for (let k = begin + 1; k < tokens.length; k += 1) {
        if (!TARGET_PREPOSITIONS.has(tokens[k].norm)) continue;
        const target = this.parseTerminalTarget(tokens, k + 1);
        if (target && this.isClauseBoundary(text, tokens, target.end, target.target !== "any")) {
          found = { prepIndex: k, target: target.target, end: target.end };
          break;
        }
      }
      if (!found) break;
      commands.push(ideCmd({ op: "send", target: found.target, text: span(text, tokens, begin, found.prepIndex), submit: currentSubmit }));
      consumed = found.end;
      let next = found.end;
      const brk = next < tokens.length ? clauseBreaks.match(tokens, next) : null;
      if (brk) next += brk.length;
      if (next >= tokens.length) break;
      const run = terminalRunVerbs.match(tokens, next);
      const type = run ? null : terminalTypeVerbs.match(tokens, next);
      if (run) { next += run.length; currentSubmit = true; } else if (type) { next += type.length; currentSubmit = false; }
      begin = next;
    }
    if (!commands.length) return null;
    if (consumed < tokens.length) return this.chain(commands, text, tokens, consumed) ?? commands;
    return commands;
  }

  isClauseBoundary(text, tokens, index, explicit) {
    if (index >= tokens.length) return true;
    if (clauseBreaks.match(tokens, index)) return true;
    const gap = text.slice(tokens[index - 1].end, tokens[index].start);
    if (gap.includes(",") || gap.includes(";")) return true;
    if (!explicit) return false;
    for (let k = index + 1; k < tokens.length; k += 1) {
      if (!TARGET_PREPOSITIONS.has(tokens[k].norm)) continue;
      const later = this.parseTerminalTarget(tokens, k + 1);
      if (later && later.target !== "any") return true;
    }
    return false;
  }
}

const ideCmd = (ide) => ({ type: "ide", ide });

function splitList(list) {
  return list.replace(/\s+(and then|then|and)\s+/g, ",").split(",").map((s) => s.trim()).filter(Boolean);
}
