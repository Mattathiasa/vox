import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { SessionRouter } from "../src/router.js";
import { normalizeConfig } from "../src/config.js";
import { canonicalAction } from "../src/canonical.js";

const shared = new URL("../../shared/", import.meta.url);
const config = normalizeConfig(JSON.parse(fs.readFileSync(new URL("grammar-config.json", shared), "utf8")));
const { cases } = JSON.parse(fs.readFileSync(new URL("grammar-cases.json", shared), "utf8"));

test("shared grammar cases (same file the Swift tests check)", () => {
  assert.ok(cases.length > 50);
  for (const c of cases) {
    const router = new SessionRouter(config);
    for (const step of c.steps) {
      assert.deepEqual(router.handle(step.say).map(canonicalAction), step.expect, `"${step.say}"`);
    }
  }
});
