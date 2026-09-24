// The web app's hands-free wake word and live-typing helpers (web/remote/wake.js).
import { test } from "node:test";
import assert from "node:assert/strict";
import { afterWake, yesNo, phrasesFrom, typingDiff, DEFAULT_PHRASES } from "../../web/remote/wake.js";

test("finds the command after the last wake word", () => {
  assert.equal(afterWake("Balcha, run claude in chirp."), "run claude in chirp");
  assert.equal(afterWake("so um balcha open safari"), "open safari");
  assert.equal(afterWake("Bal cha what's 15% of 80?"), "what's 15% of 80");
  assert.equal(afterWake("balcha stop balcha kill freebuff"), "kill freebuff");
  assert.equal(afterWake("Balcha"), "");
  assert.equal(afterWake("balcha."), "");
  assert.equal(afterWake("run claude"), null);
  assert.equal(afterWake(""), null);
  assert.equal(afterWake("balchamber is not a wake word"), null, "whole words only");
});

test("agent phrases extend the defaults", () => {
  const phrases = phrasesFrom({ wake: { name: "Balcha", phrases: ["Hey Vox"] } });
  assert.ok(phrases.includes("hey vox"));
  assert.ok(DEFAULT_PHRASES.every((p) => phrases.includes(p)));
  assert.equal(afterWake("hey vox open notes", phrases), "open notes");
  assert.deepEqual(phrasesFrom(null), DEFAULT_PHRASES);
});

test("bare yes/no answers a pending question", () => {
  assert.equal(yesNo("Yes."), true);
  assert.equal(yesNo("go ahead"), true);
  assert.equal(yesNo("No thanks"), false);
  assert.equal(yesNo("yes kill it and delete everything"), null, "only short, unambiguous answers");
});

test("typing diff: plain typing, backspace, autocorrect", () => {
  const z = "​​";
  assert.deepEqual(typingDiff(z, `${z}l`), { backspaces: 0, text: "l" });
  assert.deepEqual(typingDiff(`${z}ls -l`, `${z}ls -`), { backspaces: 1, text: "" });
  assert.deepEqual(typingDiff(`${z}teh `, `${z}the `), { backspaces: 3, text: "he " }, "autocorrect retypes from the change");
  assert.deepEqual(typingDiff(z, "​"), { backspaces: 1, text: "" }, "backspace on an empty field still reaches the terminal");
});
