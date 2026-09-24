// The Remote protocol (docs/ARCHITECTURE.md "Remote protocol"), same as the Mac app:
// static web app (web/remote) + JSON API behind a bearer pairing code.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const DEFAULT_WEB_DIR = [path.join(HERE, "..", "public"), path.join(HERE, "..", "..", "web", "remote")]
  .find((dir) => fs.existsSync(path.join(dir, "index.html")));

const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".webmanifest": "application/manifest+json", ".json": "application/json" };
const SECURITY_HEADERS = {
  "Content-Security-Policy": "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
};

export function newPairingCode() {
  // 20 chars from an unambiguous alphabet ≈ 100 bits.
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  const bytes = crypto.randomBytes(20);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}

/** Constant-time comparison (hash first so lengths don't leak). */
export function sameCode(given, expected) {
  const a = crypto.createHash("sha256").update(String(given)).digest();
  const b = crypto.createHash("sha256").update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
}

/** Too many wrong codes from one address -> locked out for a while. */
export class Lockout {
  constructor({ limit = 10, windowMs = 5 * 60_000, banMs = 60_000, now = () => Date.now() } = {}) {
    Object.assign(this, { limit, windowMs, banMs, now, failures: new Map() });
  }
  blocked(ip) {
    const entry = this.failures.get(ip);
    return Boolean(entry && entry.bannedUntil > this.now());
  }
  fail(ip) {
    const t = this.now();
    const entry = this.failures.get(ip) ?? { times: [], bannedUntil: 0 };
    entry.times = entry.times.filter((x) => t - x < this.windowMs).concat(t);
    if (entry.times.length >= this.limit) { entry.bannedUntil = t + this.banMs; entry.times = []; }
    this.failures.set(ip, entry);
  }
  succeed(ip) { this.failures.delete(ip); }
}

function send(res, status, body, headers = {}) {
  const isJSON = typeof body !== "string" && !Buffer.isBuffer(body);
  const payload = isJSON ? JSON.stringify(body) : body;
  res.writeHead(status, { ...SECURITY_HEADERS, "Cache-Control": "no-store",
    "Content-Type": isJSON ? "application/json" : headers["Content-Type"] || "text/plain; charset=utf-8", ...headers });
  res.end(payload);
}

function readBody(req, limit = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > limit) { reject(Object.assign(new Error("Body too large"), { status: 413 })); req.destroy(); return; }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (!chunks.length) return resolve({});
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); } catch { reject(Object.assign(new Error("Bad JSON"), { status: 400 })); }
    });
    req.on("error", reject);
  });
}

/**
 * @param {object} options
 * @param {import('./agent.js').Agent} options.agent
 * @param {() => string} options.code   current pairing code
 * @param {() => Promise<object>} [options.pairing]  pairing info for "Pair a phone"
 */
export function createServer({ agent, code, webDir = DEFAULT_WEB_DIR, lockout = new Lockout(), pairing = null }) {
  const handler = async (req, res) => {
    const url = new URL(req.url, "http://vox.local");
    const ip = req.socket.remoteAddress || "?";
    try {
      if (!url.pathname.startsWith("/api/")) return serveStatic(res, webDir, url.pathname);
      if (url.pathname === "/api/ping") {
        return send(res, 200, { name: "Vox", platform: agent.platform, host: agent.host, version: 1 });
      }
      if (lockout.blocked(ip)) return send(res, 429, { error: "Too many wrong pairing codes. Wait a minute." });
      const auth = req.headers.authorization || "";
      const given = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
      if (!given || !sameCode(given, code())) {
        lockout.fail(ip);
        return send(res, 401, { error: "Pairing code required." });
      }
      lockout.succeed(ip);
      return await api(req, res, url, agent, pairing);
    } catch (error) {
      return send(res, error.status || 500, { error: error.message });
    }
  };
  return http.createServer(handler);
}

async function api(req, res, url, agent, pairing) {
  const route = url.pathname.slice("/api/".length);
  if (req.method === "GET" && route === "state") {
    const lines = Math.max(10, Math.min(400, Number(url.searchParams.get("lines")) || 60));
    return send(res, 200, agent.state(lines));
  }
  if (req.method === "GET" && route === "pairing" && pairing) return send(res, 200, await pairing());
  if (req.method !== "POST") return send(res, 405, { error: "Use POST." });
  const body = await readBody(req);
  const text = typeof body.text === "string" ? body.text.slice(0, 4000) : "";

  if (route === "command") {
    const events = await agent.command(text, { spoken: Boolean(body.spoken), source: body.source === "phone" ? "phone" : "local" });
    return send(res, 200, { events });
  }
  if (route === "confirm") {
    // Only answers a pending question; otherwise "yes" would go to the tool you're talking to.
    if (!agent.engine.pendingQuestion) return send(res, 200, { events: [{ kind: "info", message: "Nothing to confirm." }] });
    return send(res, 200, { events: await agent.command(body.yes ? "yes" : "no", { source: "phone" }) });
  }
  if (route === "exit") {
    agent.engine.exitPassThrough();
    agent.append("info", "Back to commands.");
    return send(res, 200, { events: [] });
  }
  const match = route.match(/^tools\/([^/]+)\/(launch|kill|focus|send|type|key)$/);
  if (!match) return send(res, 404, { error: "No such endpoint." });
  const tool = decodeURIComponent(match[1]);
  const action = match[2];
  let events;
  switch (action) {
    case "launch": events = await agent.command(`vox run ${tool}`, { source: "phone" }); break;
    case "kill": events = await agent.command(`vox kill ${tool}`, { source: "phone" }); break;
    case "focus": events = await agent.command(`vox switch to ${tool}`, { source: "phone" }); break;
    case "send": events = await agent.sendToTool(tool, text); break;
    case "type": events = agent.engine.type(text, tool); break;
    case "key": events = agent.engine.press(String(body.key || ""), tool); break;
    default: events = [];
  }
  return send(res, 200, { events });
}

function serveStatic(res, webDir, pathname) {
  if (!webDir) return send(res, 500, "Web app files are missing.");
  const name = pathname === "/" ? "index.html" : decodeURIComponent(pathname.slice(1));
  if (name.includes("..") || name.includes("\\") || name.includes("/")) return send(res, 404, "Not found");
  const file = path.join(webDir, name);
  if (!fs.existsSync(file)) return send(res, 404, "Not found");
  return send(res, 200, fs.readFileSync(file), { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-cache" });
}
