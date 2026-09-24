// Shared state between the page (React) and the WebGL scene. Plain object: no re-renders.
export const stage = {
  level: 0,          // 0..1 "voice" energy; decays in the scene loop
  pulseAt: -100,     // seconds (performance.now()/1000) of the last sound-wave pulse
  mode: "hero",      // which part of the page is in view: hero | story | ambient
  step: 0,           // story step 0..3 (Hear, Understand, Check, Act)
  storyProgress: 0,  // 0..1 through the pinned story section
};

/** Called while the voice bar "speaks" (each typed character) and on real commands. */
export function pulse(strength = 0.25) {
  stage.level = Math.min(1, stage.level + strength);
  if (strength >= 0.5) stage.pulseAt = performance.now() / 1000;
}
