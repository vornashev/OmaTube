import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const sandbox = { URL };
vm.runInNewContext(readFileSync(new URL("./time.js", import.meta.url), "utf8"), Object.assign(sandbox, { globalThis: sandbox }));
const { parseTimestamp, parseVideoUrl, resumePosition, formatClock } = sandbox.OmaTubeTime;

test("parses YouTube timestamps", () => {
  const cases = { "90": 90, "90s": 90, "1m30s": 90, "1h2m3s": 3723, "2m": 120, "0": null, "": null, "abc": null, "-5": null, "100000": null };
  for (const [raw, expected] of Object.entries(cases)) assert.equal(parseTimestamp(raw), expected, raw);
});

test("parses video links", () => {
  assert.deepEqual({ ...parseVideoUrl("https://www.youtube.com/watch?v=BaW_jenozKc&t=1m5s&list=PL1") }, { videoId: "BaW_jenozKc", start: 65 });
  assert.deepEqual({ ...parseVideoUrl("https://youtu.be/BaW_jenozKc?t=42") }, { videoId: "BaW_jenozKc", start: 42 });
  assert.equal(parseVideoUrl("https://www.youtube.com/shorts/BaW_jenozKc").videoId, "BaW_jenozKc");
  assert.equal(parseVideoUrl("https://music.youtube.com/watch?v=BaW_jenozKc").videoId, "BaW_jenozKc");
  assert.equal(parseVideoUrl("https://m.youtube.com/watch?v=BaW_jenozKc").start, null);
  for (const raw of ["https://evil.example/watch?v=BaW_jenozKc", "https://www.youtube.com/playlist?list=PL1", "not a url", "https://youtu.be/../x"])
    assert.equal(parseVideoUrl(raw), null, raw);
});

test("chooses resume position", () => {
  assert.equal(resumePosition({ current: 312.9, duration: 900, rewind: 3 }), 309);
  assert.equal(resumePosition({ current: 2, duration: 900, rewind: 5 }), 0);
  assert.equal(resumePosition({ current: 898, duration: 900 }), 0);
  assert.equal(resumePosition({ current: 900, duration: 900, ended: true }), 0);
  assert.equal(resumePosition({ current: 1000, live: true }), null);
  assert.equal(resumePosition({ current: 14, adShowing: true, lastContent: 120, duration: 30 }), 120);
  assert.equal(resumePosition({ current: 14, adShowing: true, urlStart: 60 }), 60);
  assert.equal(resumePosition({ current: 14, adShowing: true }), 0);
});

test("formats clock", () => {
  assert.equal(formatClock(65), "1:05");
  assert.equal(formatClock(3723), "1:02:03");
  assert.equal(formatClock(-1), "0:00");
});
