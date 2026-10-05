// Port of VoxCore/Engine/ScreenReader.swift (Phase 12.3): the last answer on a coding agent's
// screen as plain text to speak. Claude Code marks answers with "⏺", Gemini "✦", Codex "•";
// tool calls ("⏺ Bash(npm test)"), their results ("⎿ …"), the input box and status lines are skipped.
const ANSWER_MARKERS = new Set(["⏺", "●", "✦", "•"]);
const BOX = new Set([..."─│╭╮╰╯┌┐└┘├┤┬┴┼═║╔╗╚╝▌▐█▏▕━┃┏┓┗┛"]);
const CHROME = ["? for shortcuts", "esc to interrupt", "esc to cancel", "shift+tab", "bypass permissions", "auto-accept",
  "accept edits", "context left", "ctrl+", "tokens)", "press esc", "/help for help"];

function clean(raw) {
  const text = [...raw].filter((ch) => !BOX.has(ch)).join("").trim();
  return {
    text,
    isPrompt: text === ">" || text.startsWith("> ") || text === "❯" || text.startsWith("❯ "),
    isResult: text.startsWith("⎿"),
  };
}

const dropMarker = (text) => { let i = 0; const chars = [...text]; while (i < chars.length && (ANSWER_MARKERS.has(chars[i]) || chars[i] === " ")) i += 1; return chars.slice(i).join(""); };
const isToolCall = (line) => /^[A-Za-z_]+\(/.test(dropMarker(line.text));
const isAnswerStart = (line) => line.text.length > 0 && ANSWER_MARKERS.has([...line.text][0]) && !isToolCall(line);
const isChrome = (text) => { const lower = text.toLowerCase(); return CHROME.some((c) => lower.includes(c)); };

export function lastAnswer(screen, maxCharacters = 700) {
  const lines = screen.split("\n").map(clean);
  let picked = [];
  let start = -1;
  for (let i = lines.length - 1; i >= 0; i -= 1) if (isAnswerStart(lines[i])) { start = i; break; }
  if (start >= 0) {
    for (const line of lines.slice(start)) {
      if (!line.text || line.isResult) continue;
      if (line.isPrompt || isChrome(line.text)) break;
      if (line.text !== lines[start].text && isToolCall(line)) break;
      picked.push(line.text);
    }
    if (picked.length) picked[0] = dropMarker(picked[0]);
  } else {
    picked = lines.filter((l) => l.text && !l.isPrompt && !l.isResult && !isChrome(l.text)).map((l) => l.text).slice(-6);
  }
  let text = picked.join(" ").replace(/[*`#]/g, "").split(" ").filter(Boolean).join(" ");
  if ([...text].length > maxCharacters) {
    const cut = [...text].slice(0, maxCharacters).join("");
    const end = Math.max(cut.lastIndexOf("."), cut.lastIndexOf("!"), cut.lastIndexOf("?"));
    text = `${end >= 0 ? cut.slice(0, end + 1) : cut} …`;
  }
  return text;
}
