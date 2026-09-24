// End-to-end over HTTP: real server, real pseudo-terminals (bash here, ConPTY on Windows), fake desktop.
import { test, after } from "node:test";
import assert from "node:assert/strict";
import { TerminalHost } from "../src/terminal.js";
import { VoxEngine } from "../src/engine.js";
import { Agent } from "../src/agent.js";
import { AppCatalog } from "../src/apps-win.js";
import { createServer, Lockout } from "../src/server.js";
import { normalizeConfig } from "../src/config.js";

import os from "node:os";
// A tool that echoes its input: `cat` on Mac/Linux, `findstr` on Windows (runs under ConPTY in CI).
const win = process.platform === "win32";
const config = normalizeConfig({ tools: [{ name: "echoer", aliases: ["echo tool"], command: win ? 'findstr "^"' : "cat", defaultDirectory: os.tmpdir() }] });
const calls = [];
const fake = new Proxy({}, { get: (_, name) => async (...a) => { calls.push([name, ...a]); return name === "quitApp" ? true : ""; } });

const hosts = [];
after(() => hosts.forEach((h) => h.killAll()));

async function start() {
  const terminals = new TerminalHost({ shell: win ? "cmd.exe" : "/bin/bash" });
  hosts.push(terminals);
  const engine = new VoxEngine({ config, terminals, desktop: fake, apps: new AppCatalog([{ name: "Steam", target: "steam://open", key: "steam" }]), pause: async () => {} });
  const agent = new Agent({ engine, config, host: "test-pc" });
  const server = createServer({ agent, code: () => "secret-code", lockout: new Lockout({ limit: 3 }) });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const api = async (path, body, token = "secret-code") => {
    const res = await fetch(`${base}/api/${path}`, { method: body ? "POST" : "GET", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, json: await res.json() };
  };
  return { server, base, api, terminals, agent };
}

const until = async (check, ms = 4000) => {
  const end = Date.now() + ms;
  while (Date.now() < end) { if (await check()) return true; await new Promise((r) => setTimeout(r, 50)); }
  return false;
};

test("pairing is required and wrong codes lock you out", async () => {
  const { server, api, base } = await start();
  assert.equal((await fetch(`${base}/api/ping`)).status, 200);
  assert.equal((await fetch(`${base}/`)).status, 200);
  assert.equal((await api("state", null, "wrong")).status, 401);
  await api("state", null, "wrong"); await api("state", null, "wrong");
  assert.equal((await api("state", null, "secret-code")).status, 429, "locked out even with the right code");
  server.close();
});

test("run a tool, type into it, see its screen, kill it with a yes", async () => {
  const { server, api, terminals } = await start();
  const launched = await api("command", { text: "run echo tool", source: "phone" });
  assert.equal(launched.json.events[0].kind, "success");
  let state = (await api("state")).json;
  assert.equal(state.lockedTool, "echoer");
  assert.deepEqual(state.tools, ["echoer"]);

  await api("tools/echoer/send", { text: "hello from the phone" });
  assert.ok(await until(async () => (await api("state")).json.screens[0]?.text.includes("hello from the phone")));

  await api("tools/echoer/type", { text: "live" });
  await api("tools/echoer/key", { key: "Enter" });
  assert.ok(await until(async () => ((await api("state")).json.screens[0]?.text.match(/live/g) || []).length >= 2));
  const bad = await api("tools/echoer/key", { key: "rm -rf" });
  assert.equal(bad.json.events[0].kind, "error");

  const nothing = await api("confirm", { yes: true });
  assert.equal(nothing.json.events[0].message, "Nothing to confirm.");
  const kill = await api("tools/echoer/kill", {});
  assert.equal(kill.json.events[0].kind, "confirm");
  state = (await api("state")).json;
  assert.match(state.pendingQuestion, /Kill the echoer session/);
  await api("confirm", { yes: true });
  assert.equal(terminals.list().length, 0);
  server.close();
});

test("desktop commands reach the desktop adapter", async () => {
  const { server, api } = await start();
  calls.length = 0;
  await api("command", { text: "open steam and then set volume to 40" });
  assert.deepEqual(calls[0], ["open", "steam://open"]);
  const answer = await api("command", { text: "what's 12 times 8" });
  assert.equal(answer.json.events[0].message, "That's 96.");
  const state = (await api("state")).json;
  assert.equal(state.history[0].command, "what's 12 times 8");
  server.close();
});
