import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { render } from "../../scripts/embed-web.mjs";

test("the Mac's embedded copy of web/remote is up to date", () => {
  const file = new URL("../../Packages/VoxCore/Sources/VoxCore/Remote/RemoteWebAssets.swift", import.meta.url);
  assert.equal(fs.readFileSync(file, "utf8"), render(), "run: node scripts/embed-web.mjs");
});
