// The Vox world: one WebGL canvas fixed behind the page.
//   • a shader "voice orb" (noise-displaced, iridescent, pulses with the voice bar)
//   • sound-wave particle rings + ambient dust
//   • three terminal cards (Claude, Kilo, Freebuff) orbiting the orb, typing live
// Scroll decides where it sits: big on the right in the hero, pinned beside the story steps,
// then a faint ambient glow behind the rest of the page.
import {
  AdditiveBlending, BufferAttribute, BufferGeometry, CanvasTexture, Clock, Color, Group, IcosahedronGeometry, Mesh, MeshBasicMaterial, PerspectiveCamera, PlaneGeometry, Points, SRGBColorSpace, Scene, ShaderMaterial, Sprite, SpriteMaterial, WebGLRenderer,
} from "three";
import noise from "./noise.glsl.js";
import { stage } from "../stage.js";

const PALETTES = {
  // [c1, c2, c3, c4] for the orb, [glow] tint
  idle: [["#ff5ea0", "#8e5cff", "#2f8fff", "#46e3ff"], "#8e5cff"],
  hear: [["#46e3ff", "#2f8fff", "#8e5cff", "#b9f3ff"], "#2f8fff"],
  understand: [["#8e5cff", "#ff5ea0", "#5e5ce6", "#d1b3ff"], "#8e5cff"],
  check: [["#ff9f0a", "#ff5ea0", "#ffd60a", "#ffe0a3"], "#ff9f0a"],
  act: [["#30d158", "#46e3ff", "#2f8fff", "#b8ffcf"], "#30d158"],
};
const STEP_PALETTE = ["hear", "understand", "check", "act"];

const CARD_SCRIPTS = {
  claude: { color: "#30d158", lines: ["✻ Welcome to Claude Code!", "> add tests for login", "● Reading src/auth/ …", "  ⎿ Read 6 files", "● Writing login.test.ts", "  ⎿ 4 passed ✓", "● Done."] },
  kilo: { color: "#46e3ff", lines: ["Kilo Code CLI · ready", "> write the README", "▸ Drafting sections…", "  ⎿ Install · Usage", "▸ README.md written"] },
  freebuff: { color: "#ff5ea0", lines: ["freebuff ▸ ready", "> clean up auth.ts", "▸ 2 files changed", "▸ running tests…", "▸ all green ✓"] },
};

function glowTexture() {
  const c = document.createElement("canvas");
  c.width = c.height = 256;
  const g = c.getContext("2d");
  const grad = g.createRadialGradient(128, 128, 0, 128, 128, 128);
  grad.addColorStop(0, "rgba(255,255,255,0.9)");
  grad.addColorStop(0.25, "rgba(255,255,255,0.35)");
  grad.addColorStop(0.6, "rgba(255,255,255,0.08)");
  grad.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 256);
  const t = new CanvasTexture(c);
  t.colorSpace = SRGBColorSpace;
  return t;
}

function makeCard(name) {
  const W = 520, H = 320;
  const canvas = document.createElement("canvas");
  canvas.width = W; canvas.height = H;
  const ctx = canvas.getContext("2d");
  const texture = new CanvasTexture(canvas);
  texture.colorSpace = SRGBColorSpace;
  texture.anisotropy = 4;
  const script = CARD_SCRIPTS[name];
  const state = { shown: 1 };
  const draw = () => {
    ctx.clearRect(0, 0, W, H);
    const r = 28;
    ctx.beginPath();
    ctx.roundRect(4, 4, W - 8, H - 8, r);
    ctx.fillStyle = "rgba(14, 14, 24, 0.78)";
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = `${script.color}aa`;
    ctx.stroke();
    ctx.fillStyle = script.color;
    ctx.beginPath(); ctx.arc(36, 38, 8, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "rgba(255,255,255,0.95)";
    ctx.font = "700 26px -apple-system, 'Inter Tight Variable', system-ui, sans-serif";
    ctx.fillText(name, 56, 47);
    ctx.fillStyle = "rgba(235,235,245,0.55)";
    ctx.font = "500 18px -apple-system, system-ui, sans-serif";
    ctx.fillText("live", W - 70, 46);
    ctx.fillStyle = "rgba(0,0,0,0.55)";
    ctx.beginPath(); ctx.roundRect(20, 70, W - 40, H - 92, 16); ctx.fill();
    ctx.font = "500 21px ui-monospace, 'SF Mono', Menlo, Consolas, monospace";
    const lines = script.lines.slice(0, state.shown).slice(-7);
    lines.forEach((line, i) => {
      ctx.fillStyle = line.startsWith(">") ? "#b79cff" : line.includes("✓") ? "#7ff0a0" : "rgba(255,255,255,0.88)";
      ctx.fillText(line, 38, 106 + i * 29);
    });
    texture.needsUpdate = true;
  };
  draw();
  const material = new MeshBasicMaterial({ map: texture, transparent: true, depthWrite: false, opacity: 1 });
  const mesh = new Mesh(new PlaneGeometry(2.05, 1.26), material);
  return {
    mesh, material,
    tick() { state.shown = state.shown >= script.lines.length ? 1 : state.shown + 1; draw(); },
    dispose() { texture.dispose(); material.dispose(); mesh.geometry.dispose(); },
  };
}

export function createScene(canvas, { reducedMotion = false } = {}) {
  const renderer = new WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
  renderer.setClearColor(0x000000, 0);

  const scene = new Scene();
  const camera = new PerspectiveCamera(35, 1, 0.1, 100);
  camera.position.set(0, 0, 10);

  const world = new Group();
  scene.add(world);

  // Orb
  const orbUniforms = {
    uTime: { value: 0 }, uLevel: { value: 0 }, uFade: { value: 1 },
    uC1: { value: new Color() }, uC2: { value: new Color() }, uC3: { value: new Color() }, uC4: { value: new Color() },
  };
  const orb = new Mesh(
    new IcosahedronGeometry(1.35, 48),
    new ShaderMaterial({
      uniforms: orbUniforms,
      transparent: true,
      vertexShader: /* glsl */ `
        ${noise}
        uniform float uTime; uniform float uLevel;
        varying vec3 vNormal; varying vec3 vView; varying float vNoise;
        void main() {
          float n = snoise(normal * 1.3 + vec3(uTime * 0.32));
          float n2 = snoise(normal * 3.2 - vec3(uTime * 0.55));
          vec3 p = position + normal * (n * (0.055 + uLevel * 0.2) + n2 * 0.025 * (0.6 + uLevel));
          vNoise = n;
          vNormal = normalize(normalMatrix * normal);
          vec4 mv = modelViewMatrix * vec4(p, 1.0);
          vView = -mv.xyz;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */ `
        uniform vec3 uC1; uniform vec3 uC2; uniform vec3 uC3; uniform vec3 uC4;
        uniform float uTime; uniform float uLevel; uniform float uFade;
        varying vec3 vNormal; varying vec3 vView; varying float vNoise;
        void main() {
          vec3 v = normalize(vView);
          float fres = pow(1.0 - max(dot(v, vNormal), 0.0), 2.4);
          // Iridescence: hue shifts with noise AND viewing angle.
          float t = clamp(vNoise * 0.45 + 0.5 + fres * 0.35 + vNormal.x * 0.22, 0.0, 1.0);
          vec3 col = mix(uC1, uC2, smoothstep(0.05, 0.55, t));
          col = mix(col, uC3, smoothstep(0.45, 1.0, t));
          col = mix(col, uC4, clamp(vNormal.y * 0.5 + 0.35, 0.0, 1.0) * 0.45);
          float band = sin((vNormal.x + vNormal.y) * 9.0 + uTime * 1.4) * 0.5 + 0.5;
          col += band * 0.06 * (0.5 + uLevel);
          col += fres * mix(vec3(0.95, 0.9, 1.0), uC4, 0.5) * (0.55 + uLevel * 0.45);
          float spec = pow(max(dot(normalize(vNormal), normalize(vec3(-0.4, 0.7, 0.6))), 0.0), 40.0);
          col += spec * 0.55;
          gl_FragColor = vec4(col, uFade);
        }`,
    }),
  );
  world.add(orb);

  // Glow halo
  const glow = new Sprite(new SpriteMaterial({ map: glowTexture(), color: new Color("#8e5cff"), transparent: true, blending: AdditiveBlending, depthWrite: false, opacity: 0.7 }));
  glow.scale.set(8.5, 8.5, 1);
  glow.position.z = -0.8;
  world.add(glow);

  // Sound-wave rings + dust (one Points object, attribute-driven)
  const RING = 2400, DUST = 1400;
  const count = RING + DUST;
  const positions = new Float32Array(count * 3);
  const seeds = new Float32Array(count * 4); // ring index / angle / radius / kind
  for (let i = 0; i < count; i += 1) {
    if (i < RING) {
      const ring = i % 3;
      const a = Math.random() * Math.PI * 2;
      const r = 2.05 + ring * 0.42 + (Math.random() - 0.5) * 0.12;
      seeds.set([ring, a, r, 0], i * 4);
    } else {
      const u = Math.random() * 2 - 1, th = Math.random() * Math.PI * 2, rr = 5 + Math.random() * 11;
      const s = Math.sqrt(1 - u * u);
      positions.set([rr * s * Math.cos(th), rr * u * 0.6, rr * s * Math.sin(th) - 4], i * 3);
      seeds.set([Math.random(), Math.random(), rr, 1], i * 4);
    }
  }
  const pGeo = new BufferGeometry();
  pGeo.setAttribute("position", new BufferAttribute(positions, 3));
  pGeo.setAttribute("seed", new BufferAttribute(seeds, 4));
  const pUniforms = { uTime: { value: 0 }, uLevel: { value: 0 }, uWave: { value: 10 }, uPixel: { value: 1 }, uFade: { value: 1 }, uTint: { value: new Color("#b79cff") } };
  const points = new Points(pGeo, new ShaderMaterial({
    uniforms: pUniforms, transparent: true, depthWrite: false, blending: AdditiveBlending,
    vertexShader: /* glsl */ `
      attribute vec4 seed;
      uniform float uTime; uniform float uLevel; uniform float uWave; uniform float uPixel;
      varying float vAlpha;
      void main() {
        vec3 p = position;
        float size = 2.0;
        if (seed.w < 0.5) {
          float ring = seed.x;
          float a = seed.y + uTime * (0.10 + ring * 0.05) * (mod(ring, 2.0) < 0.5 ? 1.0 : -1.0);
          float wave = exp(-pow((uWave - ring * 0.18) * 2.4, 2.0)) * 0.9;           // outward pulse
          float r = seed.z + wave + sin(a * 6.0 + uTime * 2.0 + ring) * 0.05 * (0.4 + uLevel * 2.0);
          p = vec3(cos(a) * r, sin(a) * r, 0.0);
          float tilt = 1.1 + ring * 0.35;
          p = vec3(p.x, p.y * cos(tilt), p.y * sin(tilt));
          float spin = ring * 2.1;
          p = vec3(p.x * cos(spin) - p.z * sin(spin), p.y, p.x * sin(spin) + p.z * cos(spin));
          vAlpha = 0.55 + wave * 0.8;
          size = 2.4 + wave * 3.0;
        } else {
          p.y += sin(uTime * 0.2 + seed.x * 30.0) * 0.15;
          vAlpha = 0.25 + 0.35 * sin(uTime * 1.3 + seed.y * 40.0) * 0.5 + 0.2;
          size = 1.6 + seed.x * 1.6;
        }
        vec4 mv = modelViewMatrix * vec4(p, 1.0);
        gl_PointSize = size * uPixel * (7.0 / -mv.z);
        gl_Position = projectionMatrix * mv;
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uTint; uniform float uFade;
      varying float vAlpha;
      void main() {
        vec2 c = gl_PointCoord - 0.5;
        float d = length(c);
        if (d > 0.5) discard;
        float a = smoothstep(0.5, 0.0, d) * vAlpha * uFade;
        gl_FragColor = vec4(mix(uTint, vec3(1.0), 0.35), a);
      }`,
  }));
  world.add(points);

  // Orbiting terminal cards
  const cards = ["claude", "kilo", "freebuff"].map(makeCard);
  cards.forEach((c) => world.add(c.mesh));

  // Colors: current (lerped) toward target palette
  const current = { cols: PALETTES.idle[0].map((h) => new Color(h)), glow: new Color(PALETTES.idle[1]) };
  const target = { cols: PALETTES.idle[0].map((h) => new Color(h)), glow: new Color(PALETTES.idle[1]) };
  const setPalette = (name) => {
    const [cols, g] = PALETTES[name];
    cols.forEach((h, i) => target.cols[i].set(h));
    target.glow.set(g);
  };

  // Layout
  const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
  const onPointer = (e) => { pointer.tx = (e.clientX / window.innerWidth) * 2 - 1; pointer.ty = (e.clientY / window.innerHeight) * 2 - 1; };
  window.addEventListener("pointermove", onPointer, { passive: true });

  let width = 1, height = 1;
  const resize = () => {
    width = window.innerWidth; height = window.innerHeight;
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    pUniforms.uPixel.value = renderer.getPixelRatio() * (height / 900);
  };
  resize();
  window.addEventListener("resize", resize);

  const layout = { x: 0, y: 0, z: 0, s: 1, fade: 1, cards: 1 };
  const goal = { ...layout };

  const clock = new Clock();
  let raf = 0;
  let running = true;
  let lastCardTick = 0;
  let cardIndex = 0;
  let lastT = 0;
  let first = true;

  const frame = () => {
    raf = running ? requestAnimationFrame(frame) : 0;
    const t = reducedMotion ? 2.0 : clock.getElapsedTime();
    const wide = width >= 1000;

    // Where should the world be?
    if (stage.mode === "hero") Object.assign(goal, { x: wide ? 2.55 : 0, y: wide ? 0.1 : 1.35, z: 0, s: wide ? 0.8 : 0.6, fade: 1, cards: 1 });
    else if (stage.mode === "story") Object.assign(goal, { x: wide ? 2.5 : 0, y: wide ? 0 : 1.6, z: 0.3, s: wide ? 0.9 : 0.55, fade: 1, cards: stage.step === 3 ? 1 : 0.3 });
    else Object.assign(goal, { x: 0, y: 0.4, z: -5, s: 1.2, fade: 0.28, cards: 0 });
    const dt = Math.min(0.1, Math.max(0, t - lastT));
    lastT = t;
    // Frame-rate independent easing; jump straight into place on the first frame.
    const k = reducedMotion || first ? 1 : 1 - Math.pow(0.94, dt * 60);
    first = false;
    for (const key of Object.keys(layout)) layout[key] += (goal[key] - layout[key]) * k;
    world.position.set(layout.x, layout.y, layout.z);
    world.scale.setScalar(layout.s);

    setPalette(stage.mode === "story" ? STEP_PALETTE[stage.step] : "idle");
    const kc = 1 - Math.pow(0.95, dt * 60);
    current.cols.forEach((c, i) => c.lerp(target.cols[i], kc));
    current.glow.lerp(target.glow, kc);
    orbUniforms.uC1.value.copy(current.cols[0]); orbUniforms.uC2.value.copy(current.cols[1]);
    orbUniforms.uC3.value.copy(current.cols[2]); orbUniforms.uC4.value.copy(current.cols[3]);
    glow.material.color.copy(current.glow);
    pUniforms.uTint.value.copy(current.glow).lerp(new Color("#ffffff"), 0.25);

    // Voice energy: decays; a gentle idle breath keeps it alive.
    stage.level *= Math.pow(0.94, dt * 60);
    const breath = 0.12 + 0.08 * Math.sin(t * 1.3);
    const level = Math.min(1, breath + stage.level + (stage.mode === "story" && stage.step === 0 ? 0.35 + 0.25 * Math.sin(t * 6) : 0));
    orbUniforms.uLevel.value += (level - orbUniforms.uLevel.value) * 0.2;
    orbUniforms.uTime.value = t;
    orbUniforms.uFade.value = layout.fade;
    pUniforms.uTime.value = t;
    pUniforms.uLevel.value = orbUniforms.uLevel.value;
    pUniforms.uWave.value = performance.now() / 1000 - stage.pulseAt;
    pUniforms.uFade.value = 0.35 + layout.fade * 0.65;
    glow.material.opacity = (0.45 + orbUniforms.uLevel.value * 0.5) * layout.fade;
    const beat = 1 + orbUniforms.uLevel.value * 0.06;
    orb.scale.setScalar(beat);
    orb.rotation.y = t * 0.12;
    orb.rotation.x = Math.sin(t * 0.2) * 0.15;

    // Cards orbit and face the camera
    cards.forEach((c, i) => {
      const a = t * 0.22 + (i * Math.PI * 2) / 3;
      // Ellipse that stays on the orb's side of the page (never over the headline).
      c.mesh.position.set(Math.cos(a) * 2.1, Math.sin(a * 1.3 + i) * 0.45 + (i - 1) * 0.55, Math.sin(a) * 2.0);
      c.mesh.quaternion.copy(camera.quaternion);
      const front = (Math.sin(a) + 1) / 2; // farther back = dimmer
      c.material.opacity = layout.cards * (0.35 + front * 0.65);
      c.mesh.visible = c.material.opacity > 0.02;
      c.mesh.scale.setScalar(0.8 + front * 0.25);
    });
    if (!reducedMotion && t - lastCardTick > 0.9) {
      lastCardTick = t;
      cards[cardIndex % cards.length].tick();
      cardIndex += 1;
    }

    // Pointer parallax
    pointer.x += (pointer.tx - pointer.x) * 0.04;
    pointer.y += (pointer.ty - pointer.y) * 0.04;
    camera.position.x = pointer.x * 0.6;
    camera.position.y = -pointer.y * 0.4;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  };

  const onVisibility = () => {
    const visible = document.visibilityState === "visible";
    if (visible && !running) { running = true; clock.start(); frame(); }
    else if (!visible) { running = false; cancelAnimationFrame(raf); }
  };
  document.addEventListener("visibilitychange", onVisibility);

  if (reducedMotion) {
    // Settle a few frames, then stop animating (static but still themed per section).
    running = false;
    for (let i = 0; i < 3; i += 1) frame();
    const rerender = () => frame();
    window.addEventListener("scroll", rerender, { passive: true });
  } else {
    frame();
  }

  return {
    dispose() {
      running = false;
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", onPointer);
      window.removeEventListener("resize", resize);
      document.removeEventListener("visibilitychange", onVisibility);
      cards.forEach((c) => c.dispose());
      pGeo.dispose();
      renderer.dispose();
    },
  };
}

export function webglAvailable() {
  try {
    const c = document.createElement("canvas");
    return Boolean(window.WebGLRenderingContext && (c.getContext("webgl2") || c.getContext("webgl")));
  } catch {
    return false;
  }
}
