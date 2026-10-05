// Phase 12.4: several sessions of one tool, one per project (same rules as InstanceTests.swift).
import test from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import { TerminalHost, slug } from "../src/terminal.js";
import { VoxEngine } from "../src/engine.js";
import { normalizeConfig } from "../src/config.js";

// A pseudo-terminal that does nothing: these tests are about which session a name means.
const spawn = () => ({ onData() {}, onExit() {}, resize() {}, kill() {}, write() {} });

function setup() {
  const terminals = new TerminalHost({ spawn });
  const config = normalizeConfig({
    tools: [{ name: "claude", command: "claude", defaultDirectory: os.tmpdir() }],
    projects: [{ name: "chirp", path: os.tmpdir() }, { name: "cbs", path: os.tmpdir() }],
  });
  const engine = new VoxEngine({ config, terminals, desktop: {}, apps: { find: () => null }, pause: async () => {} });
  return { terminals, engine };
}

test("session keys", () => {
  assert.equal(slug("claude@chirp"), "claude--chirp");
  assert.equal(slug("free--buff"), "free-buff");
});

test("two projects side by side, bare name asks which", async () => {
  const { terminals, engine } = setup();
  await engine.handle("run claude in chirp");
  await engine.handle("exit");
  const second = await engine.handle("run claude in cbs");
  assert.equal(second[0].kind, "success");
  assert.deepEqual(terminals.list().sort(), ["claude@cbs", "claude@chirp"]);
  await engine.handle("exit");
  const which = await engine.handle("switch to claude");
  assert.equal(which[0].message, 'claude is running in cbs and chirp. Say "claude in cbs" to pick one.');
  assert.equal(engine.lockedTool, null);
  const focus = await engine.handle("claude in cbs");
  assert.equal(focus[0].message, 'Talking to claude in cbs. Say "exit" to stop.');
});

test("bare name finds the only session", async () => {
  const { terminals, engine } = setup();
  await engine.handle("run claude in chirp");
  await engine.handle("exit");
  await engine.handle("switch to claude");
  assert.equal(engine.lockedTool, "claude@chirp");
  const sent = await engine.send("hello", "claude@chirp");
  assert.equal(sent[0].message, "→ claude in chirp: hello");
  await engine.handle("vox kill claude");
  const killed = await engine.handle("yes");
  assert.equal(killed[0].message, "Killed claude in chirp.");
  assert.equal(engine.lockedTool, null);
  assert.deepEqual(terminals.list(), []);
});
