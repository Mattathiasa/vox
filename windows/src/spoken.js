// Port of VoxCore/Parsing/SpokenValues.swift.

export const numberWords = {
  a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18,
  nineteen: 19, twenty: 20, thirty: 30, forty: 40, "forty five": 45, fifty: 50, sixty: 60, ninety: 90,
  hundred: 100, "a hundred": 100, half: 0.5, couple: 2, "a couple": 2, few: 3, "a few": 3,
};

export function spokenNumber(word) {
  const cleaned = word.replace(/,/g, "");
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(cleaned)) return Number(cleaned);
  return Object.hasOwn(numberWords, word) ? numberWords[word] : null;
}

const UNITS = {
  second: 1, seconds: 1, sec: 1, secs: 1,
  minute: 60, minutes: 60, min: 60, mins: 60,
  hour: 3600, hours: 3600, hr: 3600, hrs: 3600,
};

/** "5 minutes", "an hour and a half", "half an hour". Returns {seconds, end} or null. */
export function parseDuration(tokens, start) {
  let i = start;
  let total = 0;
  let lastUnit = 0;
  let matched = false;
  while (i < tokens.length) {
    if (tokens[i].norm === "half" && i + 2 < tokens.length && ["an", "a"].includes(tokens[i + 1].norm)
        && Object.hasOwn(UNITS, tokens[i + 2].norm)) {
      const unit = UNITS[tokens[i + 2].norm];
      total += 0.5 * unit;
      lastUnit = unit;
      i += 3;
      matched = true;
      continue;
    }
    if (matched && tokens[i].norm === "and" && i + 2 < tokens.length && tokens[i + 1].norm === "a"
        && tokens[i + 2].norm === "half" && lastUnit > 0) {
      total += 0.5 * lastUnit;
      i += 3;
      continue;
    }
    let j = i;
    if (matched && tokens[j].norm === "and") j += 1;
    if (j >= tokens.length) break;
    let n = spokenNumber(tokens[j].norm);
    if (n === null) break;
    let k = j + 1;
    if (["a", "an"].includes(tokens[j].norm) && k < tokens.length && Object.hasOwn(numberWords, `a ${tokens[k].norm}`)) {
      n = numberWords[`a ${tokens[k].norm}`];
      k += 1;
    }
    if (k < tokens.length && tokens[k].norm === "of") k += 1;
    if (k >= tokens.length || !Object.hasOwn(UNITS, tokens[k].norm)) break;
    const unit = UNITS[tokens[k].norm];
    total += n * unit;
    lastUnit = unit;
    i = k + 1;
    matched = true;
  }
  if (!matched || total < 1) return null;
  return { seconds: Math.round(total), end: i };
}

export function describeDuration(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  const parts = [];
  if (h > 0) parts.push(`${h} hour${h === 1 ? "" : "s"}`);
  if (m > 0) parts.push(`${m} minute${m === 1 ? "" : "s"}`);
  if (s > 0 || parts.length === 0) parts.push(`${s} second${s === 1 ? "" : "s"}`);
  return parts.join(" ");
}

/** Tiny calculator: numbers and + − × ÷, percent, square root, squared. null for anything else. */
export function evaluateMath(spoken) {
  let text = ` ${spoken.toLowerCase()} `;
  const symbols = [["×", " times "], ["*", " times "], ["÷", " divided by "], ["/", " divided by "],
    ["+", " plus "], ["−", " minus "], ["%", " percent "], ["?", " "], ["=", " "]];
  for (const [a, b] of symbols) text = text.split(a).join(b);
  text = text.split(" - ").join(" minus ");

  let list = text.split(" ").filter(Boolean);
  const filler = new Set(["what's", "what’s", "whats", "what", "is", "calculate", "compute", "how", "much",
    "equals", "equal", "the", "answer", "to", "please", "of", "by"]);
  const keepOf = list.includes("percent") || list.includes("root");
  list = list.filter((word) => (word === "of" ? keepOf : !filler.has(word)));

  let i = 0;
  const number = () => {
    if (i >= list.length) return null;
    if (list[i] === "square" && i + 1 < list.length && list[i + 1] === "root") {
      i += 2;
      if (i < list.length && list[i] === "of") i += 1;
      const n = number();
      if (n === null || n < 0) return null;
      return Math.sqrt(n);
    }
    let n = spokenNumber(list[i]);
    if (n === null) return null;
    i += 1;
    if (i < list.length && list[i] === "squared") { n *= n; i += 1; }
    if (i < list.length && list[i] === "percent") {
      i += 1;
      if (i < list.length && list[i] === "of") {
        i += 1;
        const base = number();
        if (base === null) return null;
        return (n / 100) * base;
      }
      return n / 100;
    }
    return n;
  };

  const first = number();
  if (first === null) return null;
  const numbers = [first];
  const ops = [];
  const opWords = { plus: "+", add: "+", minus: "-", less: "-", times: "*", x: "*", multiplied: "*", divided: "/", over: "/" };
  while (i < list.length) {
    const op = opWords[list[i]];
    if (!op) return null;
    i += 1;
    const n = number();
    if (n === null) return null;
    ops.push(op);
    numbers.push(n);
  }
  if (!ops.length && !list.includes("root") && !list.includes("percent") && !list.includes("squared")) return null;

  const nums = [numbers[0]];
  const addOps = [];
  for (let k = 0; k < ops.length; k += 1) {
    const n = numbers[k + 1];
    if (ops[k] === "*") nums[nums.length - 1] *= n;
    else if (ops[k] === "/") {
      if (n === 0) return null;
      nums[nums.length - 1] /= n;
    } else {
      addOps.push(ops[k]);
      nums.push(n);
    }
  }
  let result = nums[0];
  addOps.forEach((op, k) => { result = op === "+" ? result + nums[k + 1] : result - nums[k + 1]; });
  return Number.isFinite(result) ? result : null;
}

export function formatNumber(value) {
  if (value === Math.round(value) && Math.abs(value) < 1e15) return String(Math.round(value));
  return String(Number(value.toFixed(4)));
}
