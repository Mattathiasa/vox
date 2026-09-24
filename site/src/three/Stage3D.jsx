import React, { useEffect, useRef } from "react";
import { createScene, webglAvailable } from "./scene.js";

/** Fixed full-screen WebGL canvas behind the page. Falls back silently when WebGL isn't available. */
export default function Stage3D({ onUnsupported }) {
  const ref = useRef(null);
  const unsupported = useRef(onUnsupported);
  unsupported.current = onUnsupported;
  useEffect(() => {
    if (!webglAvailable()) { unsupported.current?.(); return undefined; }
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    let scene;
    try {
      scene = createScene(ref.current, { reducedMotion });
    } catch (error) {
      console.warn("Vox: 3D scene disabled", error);
      unsupported.current?.();
      return undefined;
    }
    ref.current.classList.add("ready");
    return () => scene.dispose();
  }, []);
  return <canvas ref={ref} className="stage3d" aria-hidden="true" />;
}
