// Hands-free wake word for the web app: "Balcha, run claude in chirp".
// Pure functions only (no DOM), so windows/test/wake.test.js can test them in Node.

// Same list as VoxCore WakeWordConfig.defaultPhrases, plus what browser recognizers
// tend to hear. The agent's config can add more (state.wake.phrases).
export const DEFAULT_PHRASES = [
  "balcha", "bal cha", "balch", "belcha", "bulcha", "balcher", "baltcha", "ball cha",
  "bolcha", "bulcher", "ball char", "bal char", "balchah",
];

const norm = (word) => word.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");

/** Text after the LAST wake word: null if there is none, "" if nothing follows it yet. */
export function afterWake(transcript, phrases = DEFAULT_PHRASES) {
  const tokens = String(transcript || "").split(/\s+/).filter(Boolean);
  const normed = tokens.map(norm);
  const lists = phrases.map((p) => String(p).split(/\s+/).map(norm).filter(Boolean)).filter((l) => l.length)
    .sort((a, b) => b.length - a.length);   // "bal cha" before "bal"
  for (let i = tokens.length - 1; i >= 0; i -= 1) {
    for (const list of lists) {
      if (list.every((word, k) => normed[i + k] === word)) {
        return tokens.slice(i + list.length).join(" ").replace(/^[\s,.!?;:-]+/, "").replace(/[\s,.!?;:-]+$/, "");
      }
    }
  }
  return null;
}

const YES = new Set(["yes", "yeah", "yep", "yup", "sure", "confirm", "do it", "go ahead", "ok", "okay", "yes please"]);
const NO = new Set(["no", "nope", "cancel", "stop", "don't", "dont", "no thanks", "never mind", "nevermind"]);

/** While Vox is waiting for a yes/no, a bare "yes"/"no" (no wake word) answers it. */
export function yesNo(text) {
  const phrase = String(text || "").toLowerCase().replace(/[^\p{L}\p{N}' ]+/gu, " ").replace(/\s+/g, " ").trim();
  if (YES.has(phrase)) return true;
  if (NO.has(phrase)) return false;
  return null;
}

/** Merge agent phrases with the defaults (lowercased, no duplicates). */
export function phrasesFrom(state) {
  const extra = (state && state.wake && Array.isArray(state.wake.phrases)) ? state.wake.phrases : [];
  const name = state && state.wake && state.wake.name ? [state.wake.name] : [];
  return [...new Set([...DEFAULT_PHRASES, ...name, ...extra].map((p) => String(p).toLowerCase().trim()).filter(Boolean))];
}

/**
 * Live typing without a real terminal widget: the phone keyboard edits a hidden text field and
 * we send the difference as keystrokes. Works with autocorrect and suggestions, which replace
 * whole words (we send backspaces, then the new word, like a person would).
 */
export function typingDiff(previous, next) {
  let prefix = 0;
  const max = Math.min(previous.length, next.length);
  while (prefix < max && previous[prefix] === next[prefix]) prefix += 1;
  return { backspaces: [...previous.slice(prefix)].length, text: next.slice(prefix) };
}
