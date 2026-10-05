// Same fixtures as ReadOutputTests.swift (Phase 12.3).
import test from "node:test";
import assert from "node:assert/strict";
import { lastAnswer } from "../src/reader.js";

const claude = `> add a test for the tokenizer
⏺ I'll look at the tokenizer first.
⏺ Read(Sources/VoxCore/Parsing/Tokenizer.swift)
  ⎿  Read 98 lines
⏺ Update(Tests/TokenizerTests.swift)
  ⎿  Updated with 12 additions
⏺ Added **testApostrophes** to \`TokenizerTests\`.
  It checks that "what's" becomes whats.
╭──────────────────────────────────────────────────╮
│ >                                                │
╰──────────────────────────────────────────────────╯
  ? for shortcuts                       ⧉ In Tokenizer.swift`;

test("reads the last answer like the Mac does", () => {
  assert.equal(lastAnswer(claude), 'Added testApostrophes to TokenizerTests. It checks that "what\'s" becomes whats.');
  assert.equal(lastAnswer("✦ The build passed.\n  All 12 tests are green.\n\n > Type your message\n"), "The build passed. All 12 tests are green.");
  assert.equal(lastAnswer("• Ran npm test\n• Tests pass. I also fixed a typo in README.\n▌ \n"), "Tests pass. I also fixed a typo in README.");
  assert.equal(lastAnswer("$ ls\nfoo bar\n$ echo hi\nhi\n"), "$ ls foo bar $ echo hi hi");
  assert.equal(lastAnswer(""), "");
  const long = lastAnswer(`⏺ ${"This is a sentence. ".repeat(100)}`, 100);
  assert.ok(long.endsWith("sentence. …"), long);
});
