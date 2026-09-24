// Port of VoxCore/Parsing/Tokenizer.swift. Keep behaviour identical: shared/grammar-cases.json checks both.

const WORD_CHAR = /[\p{L}\p{N}'’]/u;

/** Splits on anything that is not a letter, digit or apostrophe; lowercases; drops apostrophes. */
export function tokenize(text) {
  const tokens = [];
  let start = -1;
  const chars = Array.from(text); // code points, like Swift Characters for our purposes
  let offset = 0;
  const flush = (end) => {
    if (start < 0) return;
    const raw = text.slice(start, end);
    const norm = raw.toLowerCase().replace(/['’]/g, "");
    if (norm) tokens.push({ norm, start, end });
    start = -1;
  };
  for (const ch of chars) {
    if (WORD_CHAR.test(ch)) {
      if (start < 0) start = offset;
    } else {
      flush(offset);
    }
    offset += ch.length;
  }
  flush(text.length);
  return tokens;
}

export const words = (phrase) => tokenize(phrase).map((t) => t.norm);
export const normalizedPhrase = (phrase) => words(phrase).join(" ");

/** Original text from token `index` to the end, trimmed. null if nothing left. */
export function remainder(text, tokens, index) {
  if (index >= tokens.length) return null;
  const rest = text.slice(tokens[index].start).trim();
  return rest || null;
}

/** Original text covering tokens[from] … tokens[to - 1]. */
export function span(text, tokens, from, to) {
  return text.slice(tokens[from].start, tokens[to - 1].end);
}

/** Matches multi-word phrases against a token list, longest phrase first. */
export class PhraseMatcher {
  /** @param {{value: string, phrases: string[]}[] | string[]} items */
  constructor(items) {
    const list = items.map((item) => (typeof item === "string" ? { value: item, phrases: [item] } : item));
    const entries = [];
    for (const item of list) {
      for (const phrase of item.phrases) {
        const w = words(phrase);
        if (w.length) entries.push({ words: w, value: item.value });
      }
    }
    this.entries = entries.sort((a, b) => b.words.length - a.words.length);
  }

  match(tokens, index) {
    for (const entry of this.entries) {
      const end = index + entry.words.length;
      if (end > tokens.length) continue;
      let ok = true;
      for (let i = 0; i < entry.words.length; i += 1) {
        if (tokens[index + i].norm !== entry.words[i]) { ok = false; break; }
      }
      if (ok) return { value: entry.value, length: entry.words.length };
    }
    return null;
  }

  matchesWhole(tokens) {
    const m = this.match(tokens, 0);
    return Boolean(m) && m.length === tokens.length;
  }
}

/** Indexed matcher helper: phrases grouped by position in `table`, value = String(index). */
export function indexedMatcher(table) {
  return new PhraseMatcher(table.map((row, index) => ({ value: String(index), phrases: row.phrases })));
}
