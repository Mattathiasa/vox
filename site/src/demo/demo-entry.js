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

// The real phone app, unchanged, now talking to the simulated computer.
import("../../../web/remote/app.js");
