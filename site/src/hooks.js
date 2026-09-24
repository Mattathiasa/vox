import { useEffect, useRef, useState } from "react";
import { API, CHANGELOG_FALLBACK } from "./data.js";

/** Typewriter over a list of phrases. */
export function useTypewriter(list, { typeMs = 45, holdMs = 1800, eraseMs = 18, onChar, onDone } = {}) {
  const [text, setText] = useState("");
  const [index, setIndex] = useState(0);
  const callbacks = useRef({ onChar, onDone });
  callbacks.current = { onChar, onDone };
  useEffect(() => {
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    if (reduce) { setText(list[index]); const t = setTimeout(() => setIndex((i) => (i + 1) % list.length), 3000); return () => clearTimeout(t); }
    let cancelled = false;
    const target = list[index];
    let i = 0;
    const timers = [];
    const type = () => {
      if (cancelled) return;
      i += 1;
      setText(target.slice(0, i));
      callbacks.current.onChar?.();
      if (i < target.length) timers.push(setTimeout(type, typeMs));
      else { callbacks.current.onDone?.(); timers.push(setTimeout(erase, holdMs)); }
    };
    const erase = () => {
      if (cancelled) return;
      i -= 1;
      setText(target.slice(0, Math.max(0, i)));
      if (i > 0) timers.push(setTimeout(erase, eraseMs));
      else setIndex((n) => (n + 1) % list.length);
    };
    timers.push(setTimeout(type, 300));
    return () => { cancelled = true; timers.forEach(clearTimeout); };
  }, [index, list, typeMs, holdMs, eraseMs]);
  return { text, phrase: list[index] };
}

/** Adds .in to .reveal elements as they scroll into view, including ones rendered later (tabs, releases). */
export function useReveal() {
  useEffect(() => {
    if (!("IntersectionObserver" in window)) {
      document.querySelectorAll(".reveal").forEach((el) => el.classList.add("in"));
      return undefined;
    }
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }, { rootMargin: "0px 0px -6% 0px", threshold: 0.01 });
    document.documentElement.classList.add("js-reveal");
    const scan = () => document.querySelectorAll(".reveal:not(.in):not([data-watched])").forEach((el) => { el.dataset.watched = "1"; io.observe(el); });
    scan();
    const mo = new MutationObserver(scan);
    mo.observe(document.body, { childList: true, subtree: true });
    // Never leave anything hidden: after a few seconds, show whatever hasn't animated in.
    const safety = setTimeout(() => document.querySelectorAll(".reveal:not(.in)").forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.top < window.innerHeight) el.classList.add("in");
    }), 2500);
    return () => { io.disconnect(); mo.disconnect(); clearTimeout(safety); };
  }, []);
}

/** "mac" | "windows" | "phone" | "other" */
export function detectOS() {
  const ua = navigator.userAgent || "";
  if (/iPhone|iPad|Android/i.test(ua)) return "phone";
  if (/Mac/i.test(ua)) return "mac";
  if (/Win/i.test(ua)) return "windows";
  return "other";
}

const cache = (key, value) => { try { sessionStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore */ } };
const cached = (key) => { try { return JSON.parse(sessionStorage.getItem(key) || "null"); } catch { return null; } };

/** Releases + repo stats from the public GitHub API (cached per session; falls back to CHANGELOG). */
export function useGitHub() {
  const [data, setData] = useState(() => cached("vox-gh") ?? { releases: null, stars: null, live: false });
  const fetched = useRef(false);
  useEffect(() => {
    if (fetched.current || data.live) return;
    fetched.current = true;
    Promise.all([
      fetch(`${API}/releases?per_page=6`).then((r) => (r.ok ? r.json() : [])),
      fetch(API).then((r) => (r.ok ? r.json() : null)),
    ]).then(([releases, repo]) => {
      const next = {
        releases: Array.isArray(releases) && releases.length ? releases.map((r) => ({
          tag: r.tag_name, title: r.name || r.tag_name, date: (r.published_at || "").slice(0, 10), url: r.html_url,
          prerelease: r.prerelease, body: r.body || "",
          assets: (r.assets || []).map((a) => ({ name: a.name, url: a.browser_download_url, size: a.size, downloads: a.download_count })),
        })) : null,
        stars: repo?.stargazers_count ?? null,
        live: true,
      };
      setData(next);
      cache("vox-gh", next);
    }).catch(() => setData((d) => ({ ...d, live: true })));
  }, [data.live]);
  const releases = data.releases ?? CHANGELOG_FALLBACK.map((c) => ({ ...c, body: c.notes.map((n) => `- ${n}`).join("\n"), assets: [], fallback: true }));
  return { releases, latest: releases[0], stars: data.stars, fromGitHub: Boolean(data.releases) };
}

export const formatSize = (bytes) => (bytes > 1e6 ? `${(bytes / 1e6).toFixed(1)} MB` : `${Math.round(bytes / 1e3)} KB`);
