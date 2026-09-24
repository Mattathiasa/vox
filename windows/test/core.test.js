import { test } from "node:test";
import assert from "node:assert/strict";
import { tokenize, PhraseMatcher } from "../src/tokenizer.js";
import { parseDuration, evaluateMath } from "../src/spoken.js";
import { parseKeyCombo, urlFromSpoken } from "../src/keys.js";
import { comboToVirtualKeys, escapeSendKeys } from "../src/desktop-win.js";
import { Lockout, sameCode, newPairingCode } from "../src/server.js";
import { slug } from "../src/terminal.js";

test("tokenizer keeps original ranges", () => {
  const t = tokenize("What's up-to-date?");
  assert.deepEqual(t.map((x) => x.norm), ["whats", "up", "to", "date"]);
});
test("phrase matcher prefers the longest phrase", () => {
  const m = new PhraseMatcher([{ value: "claude", phrases: ["claude", "claude code"] }]);
  assert.deepEqual(m.match(tokenize("claude code now"), 0), { value: "claude", length: 2 });
});
test("durations and math", () => {
  assert.equal(parseDuration(tokenize("a couple of minutes"), 0).seconds, 120);
  assert.equal(parseDuration(tokenize("1 hour 30 minutes"), 0).seconds, 5400);
  assert.equal(evaluateMath("15 percent of 80"), 12);
  assert.equal(evaluateMath("2 plus 3 times 4"), 14);
  assert.equal(evaluateMath("hello"), null);
});
test("key combos and addresses", () => {
  assert.deepEqual(parseKeyCombo("command shift t"), { key: "t", modifiers: ["shift", "command"] });
  assert.equal(parseKeyCombo("command shift"), null);
  assert.equal(urlFromSpoken("github dot com slash anthropics"), "https://github.com/anthropics");
  assert.equal(urlFromSpoken("hello world"), null);
});
test("Mac shortcuts map to Windows keys", () => {
  assert.deepEqual(comboToVirtualKeys({ key: "w", modifiers: ["command"] }), [0x11, 0x57]); // Ctrl+W
  assert.deepEqual(comboToVirtualKeys({ key: "tab", modifiers: ["command"] }), [0x12, 0x09]); // Alt+Tab
  assert.deepEqual(comboToVirtualKeys({ key: "3", modifiers: ["shift", "command"] }), [0x2c]); // PrtSc
});
test("SendKeys escaping types syntax characters literally", () => {
  assert.equal(escapeSendKeys("a+b (c) {d} ~ ^ %"), "a{+}b {(}c{)} {{}d{}} {~} {^} {%}");
});
test("pairing codes and lockout", () => {
  const code = newPairingCode();
  assert.equal(code.length, 20);
  assert.ok(sameCode(code, code));
  assert.ok(!sameCode(code, code.slice(1)));
  let now = 0;
  const lock = new Lockout({ limit: 3, windowMs: 1000, banMs: 500, now: () => now });
  lock.fail("x"); lock.fail("x");
  assert.ok(!lock.blocked("x"));
  lock.fail("x");
  assert.ok(lock.blocked("x"));
  now = 600;
  assert.ok(!lock.blocked("x"));
});
test("session names", () => { assert.equal(slug("Free Buff!"), "free-buff"); });

import { defaultProjectsDir, starterConfig } from "../src/config.js";
test("Windows starter uses D:\\Projects when it exists", () => {
  assert.equal(defaultProjectsDir(() => true), "D:\\Projects");
  assert.equal(defaultProjectsDir(() => false), "~/Projects");
  assert.ok(starterConfig("D:\\Projects").tools.every((t) => t.defaultDirectory === "D:\\Projects"));
});
