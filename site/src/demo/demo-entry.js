import { installDemo } from "./demo-agent.js";
import "./demo.css";

installDemo();

const banner = document.createElement("a");
banner.className = "demo-banner";
banner.href = "../";
banner.textContent = "Live demo · simulated computer · real Vox grammar. Try \"run claude in chirp and add tests\" ›";
document.body.prepend(banner);
// Inside the landing page's phone frame, leave room for the fake notch.
if (window.self !== window.top) document.body.classList.add("embedded");

// The landing page's "try this" buttons send phrases here (same origin only).
window.addEventListener("message", (event) => {
  if (event.origin !== window.location.origin || event.data?.type !== "vox-say") return;
  const input = document.getElementById("cmd");
  const dock = document.getElementById("dock");
  if (!input || !dock) return;
  document.getElementById("term")?.setAttribute("hidden", "");
  input.value = String(event.data.text).slice(0, 200);
  dock.requestSubmit();
});

// The real phone app, unchanged, now talking to the simulated computer.
import("../../../web/remote/app.js");
