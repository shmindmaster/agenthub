import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const validator = join(pkg, "scripts", "validate-narration.mjs");
const storyReview = join(pkg, "scripts", "write-story-review.py");
const scratch = mkdtempSync(join(tmpdir(), "narration-check-"));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const hasPython = spawnSync("python", ["--version"], { windowsHide: true }).status === 0;

let counter = 0;
const sha = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
const writeJson = (root, rel, value) => { const p = join(root, rel); mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof value === "string" ? value : JSON.stringify(value, null, 2)); return p; };
const run = (args) => { const r = spawnSync(process.execPath, [validator, ...args], { encoding: "utf8", windowsHide: true }); return { code: r.status, stdout: r.stdout, stderr: r.stderr, output: `${r.stdout}${r.stderr}` }; };
const report = (root, rel = "qa/narration-check.json") => JSON.parse(readFileSync(join(root, rel), "utf8"));

// The clean six-line script: a hook of 9 words that names the promise, no fluff, no repeats.
const CLEAN = [
  "Stalled approvals cost clinics days; one click clears them.",
  "Each request waits in a queue until a manager notices it.",
  "Managers scan forty rows to find the single blocked request.",
  "Select the blocked request, choose approve, and the plan is released.",
  "Every decision lands in the audit trail with the owner's name.",
  "Open your queue and clear the first stalled request today.",
];
const ROLES = ["hook", "before", "tension", "hero", "trust", "cta"];
function screenplay(lines = CLEAN, extra = {}) {
  return {
    title: "Clear stalled approvals",
    viewerPromise: "Clear stalled approvals in one click",
    syntheticDisclosure: { mode: "end-card", text: "All records shown are synthetic.", placement: "last card" },
    scenes: lines.map((narration, i) => ({ id: `S0${i + 1}`, sceneRole: ROLES[i] || "bridge", narration })),
    ...extra,
  };
}
function makeJob(name, { lines, sp, job = { kind: "explainer", syntheticData: true }, timeline = null, draft = null } = {}) {
  const root = join(scratch, `${name}-${++counter}`);
  mkdirSync(join(root, "story"), { recursive: true });
  mkdirSync(join(root, "qa"), { recursive: true });
  if (job) writeJson(root, "job.json", job);
  if (sp !== null) writeJson(root, "story/screenplay.json", sp || screenplay(lines));
  if (timeline) writeJson(root, "story/narration-timeline.json", timeline);
  if (draft) writeJson(root, "story/screenplay.draft.json", draft);
  return root;
}
// Replace one scene's narration in the clean script.
const withLine = (index, text) => CLEAN.map((l, i) => (i === index ? text : l));

test("clean script passes: hook fits five seconds, names the promise, end-card disclosure, zero fluff", () => {
  const root = makeJob("pass");
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  const rep = report(root);
  assert.equal(rep.generator, "media-studio/validate-narration");
  assert.equal(rep.schemaVersion, "1.0.0");
  assert.equal(rep.ok, true);
  assert.deepEqual(rep.errors, []);
  assert.equal(rep.lines, 6);
  assert.equal(rep.wpm, 150);
  assert.equal(rep.hook.ok, true);
  assert.equal(rep.hook.promiseNamed, true);
  assert.ok(rep.hook.words <= 12);
  assert.equal(rep.fluff.count, 0);
  assert.equal(rep.fluff.perMinute, 0);
  assert.deepEqual(rep.fluff.hits, []);
  assert.equal(rep.syntheticDisclosure.required, true);
  assert.equal(rep.syntheticDisclosure.mode, "end-card");
  assert.equal(rep.syntheticDisclosure.ok, true);
  assert.equal(rep.inputs.screenplay.path, "story/screenplay.json");
  assert.equal(rep.inputs.screenplay.sha256, sha(join(root, "story", "screenplay.json")));
  assert.equal(rep.inputs.job.path, "job.json");
  assert.equal(rep.wordsCut.draft, null);
  const summary = JSON.parse(r.stdout);
  assert.equal(summary.ok, true);
  assert.equal(summary.out, "qa/narration-check.json");
  assert.equal(summary.hits, 0);
});

// One fixture per banned class: [class, replacement for line index 2, the text the matcher must report].
const CLASS_CASES = [
  ["greeting", "Welcome back, managers scan forty rows to find the single blocked request.", "Welcome back"],
  ["greeting", "Hi there, managers scan forty rows to find the single blocked request.", "Hi there"],
  ["meta", "In this video managers scan forty rows to find the single blocked request.", "In this video"],
  ["meta", "As you can see, managers scan forty rows to find the single blocked request.", "As you can see"],
  ["recap", "To recap, managers scan forty rows to find the single blocked request.", "To recap"],
  ["process", "Footage shows managers scanning forty rows to find the single blocked request.", "Footage"],
  ["version", "Managers scan forty rows to find the single blocked request in the new version.", "version"],
  ["version", "Since last time managers scan forty rows to find the single blocked request.", "Since last time"],
  ["synthetic", "Managers scan forty synthetic rows to find the single blocked request.", "synthetic"],
  ["synthetic", "Managers scan forty fake rows to find the single blocked request.", "fake"],
  ["jargon", "Managers leverage forty rows to find the single blocked request.", "leverage"],
  ["jargon", "Managers scan forty rows seamlessly to find the single blocked request.", "seamlessly"],
  ["filler", "Managers really scan forty rows to find the single blocked request.", "really"],
  ["filler", "Managers scan forty rows, of course, to find the single blocked request.", "of course"],
];
for (const [cls, text, match] of CLASS_CASES) {
  test(`fails on ${cls}: "${match}"`, () => {
    const root = makeJob(`cls-${cls}`, { lines: withLine(2, text) });
    const r = run([root]);
    assert.equal(r.code, 1, r.output);
    const rep = report(root);
    assert.equal(rep.ok, false);
    const hit = rep.fluff.hits.find((h) => h.class === cls && h.match === match);
    assert.ok(hit, `no ${cls} hit for ${match}: ${JSON.stringify(rep.fluff.hits)}`);
    assert.equal(hit.sceneId, "S03");
    assert.equal(hit.line, text);
    assert.ok(rep.errors.some((e) => e.includes(`S03 ${cls}: "${match}"`)), JSON.stringify(rep.errors));
    assert.ok(rep.fluff.perMinute > 0);
    assert.ok(rep.fluff.secondsSpent > 0);
  });
}

test("version matching is word-bounded: conversion and diversion do not match", () => {
  const root = makeJob("bounded", { lines: withLine(2, "Managers scan forty rows to find the single blocked request before conversion or diversion.") });
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  assert.equal(report(root).fluff.count, 0);
});

test("fails on a redundant line: 70% or more of its content words repeat one earlier line", () => {
  const root = makeJob("redundant", { lines: [...CLEAN.slice(0, 5), "Every request waits in the queue until managers notice it."] });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const rep = report(root);
  const hit = rep.fluff.hits.find((h) => h.class === "redundant");
  assert.ok(hit, JSON.stringify(rep.fluff.hits));
  assert.equal(hit.sceneId, "S06");
  assert.ok(rep.errors.some((e) => e.includes("S06 redundant")));
});

test("fails on a line that adds no new information across several earlier lines", () => {
  // Every content word appears somewhere earlier, but no single earlier line holds 70% of them.
  const root = makeJob("nonew", {
    lines: [
      CLEAN[0], CLEAN[1], CLEAN[2], CLEAN[3], CLEAN[4],
      "Managers notice stalled approvals blocked forty rows.",
    ],
  });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const rep = report(root);
  const hit = rep.fluff.hits.find((h) => h.class === "no-new-information");
  assert.ok(hit, JSON.stringify(rep.fluff.hits));
  assert.equal(hit.sceneId, "S06");
  assert.ok(!rep.fluff.hits.some((h) => h.class === "redundant" && h.sceneId === "S06"));
  assert.ok(rep.errors.some((e) => e.includes("S06 no-new-information")));
});

test("fails hook-5s when the first sentence needs more than five seconds", () => {
  const long = "Stalled approvals cost clinics days of waiting every single month while managers hunt through long queues for them.";
  const root = makeJob("hook", { lines: withLine(0, long) });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const rep = report(root);
  assert.equal(rep.hook.ok, false);
  assert.ok(rep.hook.words > 12);
  assert.ok(rep.hook.seconds > 5);
  assert.ok(rep.errors.some((e) => e.startsWith("hook-5s:")), JSON.stringify(rep.errors));
});

const SCOPE_LINE = "These are proposed decisions for this client, to be validated with the CTO.";
function scopeFixture({ line = SCOPE_LINE, duplicate = false } = {}) {
  // Reused words across separate claims; no single prior sentence dominates the qualifier.
  const lines = ["The client needs resilient network routing.", "Proposed decisions protect billing records.",
    "The CTO controls validated identity boundaries.", "Operations are to be measured against recovery targets.", line];
  if (duplicate) lines.push(line);
  const root = makeJob("scope", { sp: screenplay(lines, { viewerPromise: "resilient network routing" }) });
  const sceneId = "S05";
  const evidence = writeJson(root, "qa/scope-review.json", { kind: "truthful-scope-qualification", verdict: "PASS",
    assertion: "proposed-not-client-confirmed", sceneId, line,
    reason: "This sentence marks the proposals as subject to client validation; earlier statements name separate responsibilities." });
  const job = { narrationScopeQualifications: [{ sceneId, line, reason: "Truth status qualification prevents an unconfirmed client claim.",
    evidence: { path: "qa/scope-review.json", sha256: sha(evidence) } }] };
  writeJson(root, "job.json", job);
  return { root, evidence, job };
}

test("source-bound proposal qualification adjudicates lexical reuse and records its evidence", () => {
  const { root, evidence } = scopeFixture();
  assert.equal(run([root]).code, 0, run([root]).output);
  const rep = report(root);
  assert.equal(rep.fluff.scopeAdjudications.length, 1);
  assert.equal(rep.inputs.scopeQualification1.sha256, sha(evidence));
  assert.equal(rep.thresholds.noNewInformationMinContentWords, 4);
});

test("proposal qualification fails closed when its evidence changes", () => {
  const { root, evidence } = scopeFixture();
  writeFileSync(evidence, "{}");
  const r = run([root]);
  assert.equal(r.code, 1);
  assert.match(r.output, /current in-job evidence SHA256/);
  assert.ok(report(root).fluff.hits.some((h) => h.class === "no-new-information"));
});

test("proposal qualification cannot suppress a repeated sentence", () => {
  const { root } = scopeFixture({ duplicate: true });
  assert.equal(run([root]).code, 1);
  assert.ok(report(root).fluff.hits.some((h) => h.class === "redundant" && h.sceneId === "S06"));
});

test("a scope receipt cannot exempt ordinary repetition or arbitrary nonqualification", () => {
  const { root } = scopeFixture({ line: "The client needs resilient network routing." });
  const r = run([root]);
  assert.equal(r.code, 1);
  assert.match(r.output, /exact proposal-validation line/);
  assert.ok(report(root).fluff.hits.some((h) => h.class === "redundant"));
});

test("hook limit follows wpm: 12 words at 150, 10 words at 120", () => {
  const root = makeJob("hookwpm"); // clean hook is 9 words
  assert.equal(run([root, "--wpm", "120"]).code, 0);
  const root2 = makeJob("hookwpm2", { lines: withLine(0, "Stalled approvals cost clinics days of waiting each month; one click clears them.") }); // 13 words
  assert.equal(run([root2]).code, 1);
  assert.equal(report(root2).wpm, 150);
});

test("fails promise-5s when the first five seconds never name the promise", () => {
  const root = makeJob("promise", { lines: withLine(0, "Clinics lose days to waiting around."), sp: screenplay(withLine(0, "Clinics lose days to waiting around.")) });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const rep = report(root);
  assert.equal(rep.hook.promiseNamed, false);
  assert.ok(rep.errors.some((e) => e.startsWith("promise-5s:")), JSON.stringify(rep.errors));
});

test("promise-5s is skipped with a warning when there is no viewerPromise or wiifm", () => {
  const sp = screenplay(); delete sp.viewerPromise;
  const root = makeJob("nopromise", { sp });
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  const rep = report(root);
  assert.equal(rep.hook.promiseNamed, null);
  assert.ok(rep.warnings.some((w) => w.includes("promise-5s")), JSON.stringify(rep.warnings));
});

test("promise-5s falls back to the first scene's wiifm", () => {
  const sp = screenplay(); delete sp.viewerPromise; sp.scenes[0].wiifm = "Approvals cleared in a click";
  const root = makeJob("wiifm", { sp });
  assert.equal(run([root]).code, 0);
  assert.equal(report(root).hook.promiseNamed, true);
});

test("fails synthetic-disclosure when a synthetic job uses mode none", () => {
  const sp = screenplay(CLEAN, { syntheticDisclosure: { mode: "none" } });
  const root = makeJob("disclose-none", { sp });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const rep = report(root);
  assert.equal(rep.syntheticDisclosure.required, true);
  assert.equal(rep.syntheticDisclosure.ok, false);
  assert.ok(rep.errors.some((e) => e.startsWith("synthetic-disclosure:") && e.includes("never narration")), JSON.stringify(rep.errors));
});

test("fails synthetic-disclosure when a synthetic job has no disclosure or empty text", () => {
  const sp = screenplay(); delete sp.syntheticDisclosure;
  const noneDeclared = makeJob("disclose-missing", { sp });
  assert.equal(run([noneDeclared]).code, 1);
  assert.equal(report(noneDeclared).syntheticDisclosure.mode, null);
  const emptyText = makeJob("disclose-empty", { sp: screenplay(CLEAN, { syntheticDisclosure: { mode: "caption", text: "  " } }) });
  assert.equal(run([emptyText]).code, 1);
  assert.ok(report(emptyText).errors.some((e) => e.startsWith("synthetic-disclosure:")));
});

test("dataClass matching /synthetic/i requires a disclosure; a real-data job does not", () => {
  const sp = screenplay(); delete sp.syntheticDisclosure;
  const synth = makeJob("dataclass", { sp, job: { kind: "explainer", dataClass: "Synthetic-demo" } });
  assert.equal(run([synth]).code, 1);
  const real = makeJob("realdata", { sp, job: { kind: "explainer", dataClass: "production" } });
  const r = run([real]);
  assert.equal(r.code, 0, r.output);
  const rep = report(real);
  assert.equal(rep.syntheticDisclosure.required, false);
  assert.equal(rep.syntheticDisclosure.ok, true);
});

test("allowlist with a reason suppresses a jargon hit and lists it", () => {
  const text = "Managers scan forty rows to find the single blocked request in a powerful audit trail.";
  const sp = screenplay(withLine(2, text), { narrationAllowlist: [{ phrase: "Powerful", reason: "The vendor's product name contains the word" }] });
  const root = makeJob("allow", { sp });
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  const rep = report(root);
  assert.equal(rep.fluff.count, 0);
  assert.equal(rep.fluff.allowlisted.length, 1);
  assert.equal(rep.fluff.allowlisted[0].class, "jargon");
  assert.equal(rep.fluff.allowlisted[0].match.toLowerCase(), "powerful");
  assert.equal(rep.fluff.allowlisted[0].reason, "The vendor's product name contains the word");
});

test("allowlist only suppresses the phrase it names", () => {
  const text = "Managers really leverage forty rows to find the single blocked request.";
  const sp = screenplay(withLine(2, text), { narrationAllowlist: [{ phrase: "really", reason: "quoted from the customer" }] });
  const root = makeJob("allow-partial", { sp });
  assert.equal(run([root]).code, 1);
  const rep = report(root);
  assert.deepEqual(rep.fluff.hits.map((h) => h.match.toLowerCase()), ["leverage"]);
  assert.equal(rep.fluff.allowlisted.length, 1);
});

test("allowlist never suppresses greeting, meta or other structural classes", () => {
  const text = "Welcome managers scan forty rows to find the single blocked request.";
  const sp = screenplay(withLine(2, text), { narrationAllowlist: [{ phrase: "welcome", reason: "friendly" }] });
  const root = makeJob("allow-greeting", { sp });
  assert.equal(run([root]).code, 1);
  assert.ok(report(root).fluff.hits.some((h) => h.class === "greeting"));
});

test("allowlist entry without a reason is an error", () => {
  const sp = screenplay(CLEAN, { narrationAllowlist: [{ phrase: "powerful" }, { phrase: "robust", reason: "  " }] });
  const root = makeJob("allow-noreason", { sp });
  const r = run([root]);
  assert.equal(r.code, 1, r.output);
  const errs = report(root).errors.filter((e) => e.startsWith("narrationAllowlist:"));
  assert.equal(errs.length, 2, JSON.stringify(report(root).errors));
  assert.ok(errs.every((e) => e.includes("reason")));
});

test("falls back to narration-timeline.json when screenplay.json is absent and uses its duration", () => {
  const timeline = {
    durationSeconds: 40,
    segments: CLEAN.map((text, i) => ({ id: `W0${i + 1}`, scene: `W0${i + 1}`, text, startSeconds: i * 6, durationSeconds: 6 })),
  };
  const root = makeJob("timeline", { sp: null, timeline, job: { kind: "product-screencast" } });
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  const rep = report(root);
  assert.equal(rep.inputs.timeline.path, "story/narration-timeline.json");
  assert.equal(rep.inputs.screenplay, undefined);
  assert.equal(rep.runtimeSeconds, 40);
  assert.equal(rep.lines, 6);
  assert.equal(rep.hook.promiseNamed, null); // no viewerPromise on a timeline
  assert.ok(rep.warnings.some((w) => w.includes("promise-5s")));
});

test("timeline fallback still catches fluff, scene-tagged by the segment's scene", () => {
  const lines = withLine(1, "Let's take a look at how each request waits in a queue.");
  const timeline = { durationSeconds: 40, segments: lines.map((text, i) => ({ id: `W0${i + 1}a`, scene: `W0${i + 1}`, text, startSeconds: i * 6, durationSeconds: 6 })) };
  const root = makeJob("timeline-fluff", { sp: null, timeline, job: { kind: "product-screencast" } });
  assert.equal(run([root]).code, 1);
  const hit = report(root).fluff.hits.find((h) => h.class === "meta");
  assert.ok(hit);
  assert.equal(hit.sceneId, "W02");
});

test("fails closed with an error when neither screenplay nor timeline exists", () => {
  const root = makeJob("nothing", { sp: null, job: null });
  const r = run([root]);
  assert.equal(r.code, 1);
  assert.ok(report(root).errors.some((e) => e.includes("screenplay.json") && e.includes("narration-timeline.json")));
});

test("words-cut report: draft longer than the cut, removed line listed, runtime drops", () => {
  const cut = "Open the queue, then clear the first stalled request.";
  const draftLines = [...CLEAN.slice(0, 5), "As we walk through the whole queue today, please do take a moment to open it and then clear the first stalled request.", "Thanks to the team behind the build for making this possible for clinics everywhere."];
  const root = makeJob("wordscut", { lines: [...CLEAN.slice(0, 5), cut], draft: screenplay(draftLines) });
  const r = run([root]);
  const rep = report(root);
  assert.equal(rep.wordsCut.draft.path, "story/screenplay.draft.json");
  assert.match(rep.wordsCut.draft.sha256, /^[0-9a-f]{64}$/);
  assert.ok(rep.wordsCut.wordsBefore > rep.wordsCut.wordsAfter);
  assert.ok(rep.wordsCut.runtimeBeforeSeconds > rep.wordsCut.runtimeAfterSeconds);
  assert.equal(rep.wordsCut.linesKept, 5);
  const removed = rep.wordsCut.linesRemoved.map((l) => l.line);
  assert.ok(removed.some((l) => l.startsWith("As we walk through")), JSON.stringify(removed));
  assert.ok(removed.some((l) => l.startsWith("Thanks to the team")), JSON.stringify(removed));
  assert.deepEqual(rep.wordsCut.linesAdded.map((l) => l.line), [cut]);
  assert.equal(rep.wordsCut.linesRemoved[0].sceneId, "S06");
  const summary = JSON.parse(r.stdout);
  assert.equal(summary.linesRemoved, 2);
  assert.ok(summary.runtimeBeforeSeconds > summary.runtimeAfterSeconds);
  assert.equal(rep.inputs.draft.path, "story/screenplay.draft.json");
});

test("--before names the draft explicitly and --out redirects the report", () => {
  const root = makeJob("before-flag", {});
  writeJson(root, "story/old.json", screenplay([...CLEAN, "Thanks for watching and see you next time."]));
  const r = run([root, "--before", "story/old.json", "--out", "qa/custom.json"]);
  assert.equal(r.code, 0, r.output);
  assert.ok(!existsSync(join(root, "qa", "narration-check.json")));
  const rep = report(root, "qa/custom.json");
  assert.equal(rep.wordsCut.draft.path, "story/old.json");
  assert.equal(rep.wordsCut.linesRemoved.length, 1);
  assert.equal(JSON.parse(r.stdout).out, "qa/custom.json");
});

test("schemas accept the new optional fields and still accept a document without them", () => {
  const read = (n) => JSON.parse(readFileSync(join(pkg, "schemas", n), "utf8"));
  const sp = read("screenplay.schema.json"), sb = read("storyboard.schema.json"), jb = read("job.schema.json");
  assert.equal(sp.properties.wpm.minimum, 60);
  assert.deepEqual(sp.properties.narrationAllowlist.items.required, ["phrase", "reason"]);
  assert.deepEqual(sp.$defs.syntheticDisclosure.properties.mode.enum, ["caption", "end-card", "none"]);
  assert.deepEqual(sp.$defs.syntheticDisclosure.required, ["mode"]);
  assert.equal(sp.$defs.syntheticDisclosure.additionalProperties, false);
  assert.deepEqual(sp.required, ["title", "scenes"]);
  assert.ok(sb.properties.syntheticDisclosure);
  const beat = sb.properties.beats.items;
  assert.deepEqual(beat.properties.eyePath.required, ["start", "move", "rest"]);
  assert.equal(beat.properties.eyePath.additionalProperties, false);
  assert.equal(beat.properties.pointer.properties.maxTravelRatio.minimum, 1);
  assert.equal(beat.properties.pointer.properties.maxReversals.type, "integer");
  assert.ok(!beat.required.includes("eyePath") && !beat.required.includes("pointer"));
  assert.ok(jb.properties.programForm.enum.includes("marketing-cutdown"));
  assert.equal(jb.properties.syntheticData.type, "boolean");
  assert.equal(jb.properties.marketing.type, "boolean");
  assert.equal(jb.properties.dataClass.type, "string");
  assert.deepEqual(jb.required, ["kind", "title", "workspace", "repositoryWritePolicy"]);
});

// ---- write-story-review.py: the mechanical no-fluff check ------------------------------------------------------

const reviewJob = (name, lines = CLEAN) => {
  const root = makeJob(name, {
    sp: {
      title: "Clear stalled approvals", heroSceneId: "S04", viewerPromise: "Clear stalled approvals in one click",
      syntheticDisclosure: { mode: "end-card", text: "All records shown are synthetic." },
      scenes: lines.map((narration, i) => ({
        id: `S0${i + 1}`, sceneRole: ROLES[i], narration,
        visualMode: i === 0 || i === 5 ? "card" : "screen",
        visualArchetype: ["cold-open", "before-after", "diagram-build", "hero-reveal", "evidence-proof", "cta-end-frame"][i],
        ...(i === 3 ? { heroMoment: true, holdAfterSeconds: 1.2, silenceOnReveal: true } : {}),
        ...(i === 5 ? { holdAfterSeconds: 1.5 } : {}),
      })),
    },
    job: { kind: "explainer", syntheticData: true, deliveryProfile: "briefing-board", craftScoreMin: 85 },
  });
  writeJson(root, "story/storyboard.json", { title: "Clear stalled approvals", protectedHeroBeatId: "S04", beats: [] });
  const verdict = (ev) => ({ verdict: "pass", evidence: ev });
  writeJson(root, "qa/story-judgments.json", {
    schema: "media-studio/story-judgments/1", reviewer: "test",
    judgments: Object.fromEntries(["audience", "outcome", "wiifm", "progressive", "one-idea", "one-promise", "studio-picture", "trust"].map((k) => [k, verdict("S01 and S04 carry it")])),
  });
  return root;
};
const review = (root) => {
  const r = spawnSync("python", [storyReview, root], { encoding: "utf8", windowsHide: true });
  const rep = JSON.parse(readFileSync(join(root, "qa", "story-review.json"), "utf8"));
  return { code: r.status, rep, output: `${r.stdout}${r.stderr}` };
};

test("write-story-review: fixture has a COMPLETE review before no-fluff matters", { skip: !hasPython }, () => {
  const root = reviewJob("sr-base");
  assert.equal(run([root]).code, 0);
  const { rep, output } = review(root);
  assert.equal(rep.status, "COMPLETE", output);
  assert.equal(rep.checks["no-fluff"], "pass");
  assert.equal(rep.score, 100, JSON.stringify(rep.findings));
  assert.equal(rep.pass, true);
  assert.match(rep.reason, /no-fluff: fluff 0\/min, 0 hits/);
});

test("write-story-review: missing narration-check.json fails no-fluff for -15 and says to run the validator", { skip: !hasPython }, () => {
  const root = reviewJob("sr-missing");
  const { rep } = review(root);
  assert.equal(rep.checks["no-fluff"], "fail");
  assert.equal(rep.score, 85);
  const f = rep.findings.find((x) => x.location.includes("narration-check"));
  assert.ok(f, JSON.stringify(rep.findings));
  assert.equal(f.severity, "major");
  assert.equal(f.owner, "media-writer");
  assert.match(`${f.evidence} ${f.fix}`, /run validate-narration\.mjs/);
});

test("write-story-review: a stale narration-check.json (screenplay changed after it ran) fails the same way", { skip: !hasPython }, () => {
  const root = reviewJob("sr-stale");
  assert.equal(run([root]).code, 0);
  const p = join(root, "story", "screenplay.json");
  const sp = JSON.parse(readFileSync(p, "utf8")); sp.title += " v2"; writeFileSync(p, JSON.stringify(sp, null, 2));
  const { rep } = review(root);
  assert.equal(rep.checks["no-fluff"], "fail");
  assert.equal(rep.score, 85);
  assert.ok(rep.findings.some((x) => /stale/i.test(x.evidence) && /run validate-narration\.mjs/.test(x.fix)), JSON.stringify(rep.findings));
});

test("write-story-review: ok:false report fails -15 with the first three hits in the evidence", { skip: !hasPython }, () => {
  const fluffy = [
    CLEAN[0],
    "Each request really waits in a queue until a manager notices it.",
    "Managers leverage forty rows to find the single blocked request.",
    "Select the blocked request, choose approve, and the plan is seamlessly released.",
    "Every decision lands in the audit trail with the owner's name, of course.",
    CLEAN[5],
  ];
  const root = reviewJob("sr-fluff", fluffy);
  assert.equal(run([root]).code, 1);
  const { rep } = review(root);
  assert.equal(rep.checks["no-fluff"], "fail");
  const f = rep.findings.find((x) => x.location.includes("narration-check"));
  assert.ok(f, JSON.stringify(rep.findings));
  assert.equal(f.severity, "major");
  assert.equal(f.owner, "media-writer");
  assert.ok(f.evidence.includes("really") && f.evidence.includes("leverage") && f.evidence.includes("seamlessly"), f.evidence);
  assert.ok(!f.evidence.includes("of course"), "only the first three hits are cited");
  assert.equal(rep.score, 85);
});

test("the locked timeline is checked when it exists: a fluff line rewritten into it fails even with a clean screenplay", () => {
  const lines = withLine(1, "Let's take a look at how each request waits in a queue.");
  const timeline = { durationSeconds: 40, segments: lines.map((text, i) => ({ id: `S0${i + 1}`, scene: `S0${i + 1}`, text, startSeconds: i * 6, durationSeconds: 6 })) };
  const root = makeJob("timeline-wins", { timeline });
  assert.equal(run([root]).code, 1);
  const rep = report(root);
  assert.equal(rep.source, "timeline");
  assert.equal(rep.inputs.timeline.path, "story/narration-timeline.json");
  assert.equal(rep.inputs.screenplay.path, "story/screenplay.json");
  assert.ok(rep.fluff.hits.some((h) => h.class === "meta" && h.sceneId === "S02"), JSON.stringify(rep.fluff.hits));
  assert.equal(rep.hook.promiseNamed, true, "viewerPromise still comes from the screenplay");
  assert.ok(!rep.warnings.some((w) => w.includes("screenplay.json is absent")));
});

test("a storyboard syntheticDisclosure satisfies a synthetic job whose screenplay and job omit it", () => {
  const sp = screenplay(CLEAN);
  delete sp.syntheticDisclosure;
  const root = makeJob("storyboard-disclosure", { sp });
  assert.equal(run([root]).code, 1, "no disclosure anywhere fails");
  writeJson(root, "story/storyboard.json", { syntheticDisclosure: { mode: "caption", text: "Synthetic data." } });
  const r = run([root]);
  assert.equal(r.code, 0, r.output);
  const rep = report(root);
  assert.equal(rep.syntheticDisclosure.ok, true);
  assert.equal(rep.syntheticDisclosure.mode, "caption");
  assert.equal(rep.inputs.storyboard.path, "story/storyboard.json");
});
