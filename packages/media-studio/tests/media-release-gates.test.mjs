import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const scenarioValidator = join(pkg, "scripts", "validate-demo-scenario.mjs");
const releaseValidator = join(pkg, "scripts", "validate-viewer-release.mjs");
const scaffold = join(pkg, "scripts", "scaffold-video-workspace.mjs");
const scratch = mkdtempSync(join(tmpdir(), "media-release-"));
test.after(async () => {
  // Windows media scanners can retain the last ffmpeg output briefly after the encoder exits.
  await new Promise((done) => setTimeout(done, 1500));
  rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
});
const sha = (file) => createHash("sha256").update(readFileSync(file)).digest("hex");
const writePictureReport = (root, candidate) => writeFileSync(join(root, 'qa', 'encoded-picture.json'), JSON.stringify({ generator: 'media-studio/validate-encoded-picture', ok: true, errors: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, thresholds: { maxStaticSeconds: 6, bindMaxHamming: 12 }, screenRatio: 1, segments: [{ id: 'hero', mode: 'screen', bound: true }] }));
const syncReport = (candidate, over = {}) => ({ generator: 'media-studio/validate-sync', ok: true, degraded: false, errors: [], warnings: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, thresholds: { actionToleranceMs: 300, screenToleranceMs: 40, resultHoldMinSeconds: 1.5, driftMaxMs: 40, maxFreezeSeconds: 4, maxHoldSeconds: 6.5, maxDroppedFrames: 3 }, precision: { allWordLevel: true, degradedBeats: [] }, beats: [{ beat: 'hero', status: 'pass', findings: [{ check: 'action-timing', status: 'pass' }] }], checks: { performed: ['screen-on', 'action-timing', 'result-hold', 'narration-order', 'av-sync', 'frozen-frames', 'dropped-frames'], notPerformed: [{ check: 'text-clipping', reason: 'no OCR' }] }, ...over });
const writeSyncReport = (root, candidate, over) => writeFileSync(join(root, 'qa', 'sync.json'), JSON.stringify(syncReport(candidate, over)));
// Video-standard reports (owner direction 2026-10-20): each is produced by its own gate; the release gate only checks the binding.
const writeStandardReports = (root, candidate) => {
  mkdirSync(join(root, 'capture'), { recursive: true });
  const screenplay = join(root, 'story', 'screenplay.json');
  if (!existsSync(screenplay)) writeFileSync(screenplay, JSON.stringify({ title: 't', scenes: [{ id: 'hero', narration: 'The plan is ready after approval.' }] }));
  const receipt = join(root, 'capture', 'receipt.json');
  if (!existsSync(receipt)) writeFileSync(receipt, JSON.stringify({ schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips: {} }));
  writeFileSync(join(root, 'qa', 'narration-check.json'), JSON.stringify({ generator: 'media-studio/validate-narration', ok: true, thresholds: { hookSeconds: 5, redundantOverlap: 0.7, redundantMinContentWords: 3, noNewInformationMinContentWords: 4 }, errors: [], warnings: [], inputs: { screenplay: { path: 'story/screenplay.json', sha256: sha(screenplay) } }, fluff: { perMinute: 0, count: 0, hits: [] } }));
  writeFileSync(join(root, 'qa', 'frame-integrity.json'), JSON.stringify({ generator: 'media-studio/validate-frame-integrity', ok: true, thresholds: { tilePsnr: 32, lumaJump: 40, contrastFloor: 12, cutWindow: 0.25, sampleFps: 2 }, errors: [], warnings: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, tiled: [], lumaJumps: [] }));
  writeFileSync(join(root, 'qa', 'pointer-path.json'), JSON.stringify({ generator: 'media-studio/validate-pointer-path', ok: true, thresholds: { maxReversals: 0, maxTravelRatio: 1.35, maxScrollReversals: 0, maxUnnamedMoves: 0, turnCos: -0.5 }, errors: [], warnings: [], inputs: { receipt: { path: 'capture/receipt.json', sha256: sha(receipt) } }, windows: [] }));
  writeFileSync(join(root, 'qa', 'picture-integrity.json'), JSON.stringify({ generator: 'media-studio/validate-picture-integrity', ok: true, thresholds: { scaleTolerance: 0.005, barVariance: 4, barMinPx: 6, ratioTolerance: 0.02 }, errors: [], warnings: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, clips: [] }));
};
const run = (script, args) => { const result = spawnSync(process.execPath, [script, ...args], { encoding: "utf8" }); return { code: result.status, output: `${result.stdout}${result.stderr}` }; };
function job(root) {
  mkdirSync(join(root, "evidence"), { recursive: true }); mkdirSync(join(root, "qa"), { recursive: true }); mkdirSync(join(root, "story"), { recursive: true });
  writeFileSync(join(root, "job.json"), JSON.stringify({ kind: "product-screencast", intent: "viewer-facing" }));
  const runtimePath = join(root, "evidence", "runtime-outcome.json");
  writeFileSync(runtimePath, JSON.stringify({ result: "authenticated picker selected, approval criteria persisted, and resolution visibly completed" }));
  const sourcePath = join(root, "evidence", "source.json");
  writeFileSync(sourcePath, JSON.stringify({ status: "DEMO-READY", workflow: { authenticated: true, actionResultObserved: true }, runtimeOutcome: { status: "PASS", path: "evidence/runtime-outcome.json", sha256: sha(runtimePath) } }));
  const proof = { scenarioId: "synthetic-clinic-aria-01", synthetic: true, persona: "Clinical lead", problem: "A staff member needs a usable assessment and approved plan.", hero: { segmentId: "hero", beforeState: "blocked", action: "approve", visibleResult: "plan ready" }, outcome: { statement: "The owner can act from the resolved queue.", evidence: "visible status" }, continuity: { entities: [{ type: "client", id: "aria-01" }, { type: "goal", id: "requesting-help" }] }, source: { kind: "product-readiness-handoff", status: "DEMO-READY", path: "evidence/source.json", sha256: sha(sourcePath), verifiedAt: "2026-09-22T12:00:00Z" } };
  writeFileSync(join(root, "evidence", "demo-scenario-proof.json"), JSON.stringify(proof));
  writeFileSync(join(root, "story", "storyboard.json"), JSON.stringify({ scenarioId: proof.scenarioId, cta: "Review your workflow", beats: [{ id: "hero", scenarioId: proof.scenarioId, entityRefs: [{ type: "goal", id: "requesting-help" }] }] }));
}
function release(root) {
  const candidate = join(root, "output.mp4"), script = join(root, "story", "screenplay.txt"), captions = join(root, "qa", "captions.srt"), analyzer = join(root, "qa", "loudness.json");
  writeFileSync(candidate, "encoded candidate bytes"); writeFileSync(script, "The plan is ready after approval."); writeFileSync(captions, "1\n00:00:00,000 --> 00:00:02,000\nThe plan is ready.\n");
  const candidateSha256 = sha(candidate); writeFileSync(analyzer, JSON.stringify({ tool: "ffmpeg-loudnorm", candidateSha256, integratedLufs: -16, truePeakDbtp: -1.5 }));
  writePictureReport(root, candidate);
  writeSyncReport(root, candidate);
  writeStandardReports(root, candidate);
  const pass = { status: "PASS", candidateSha256 };
  const evidence = { candidate: { sha256: candidateSha256 }, captions: { ...pass, path: "qa/captions.srt", sha256: sha(captions) }, audio: { ...pass, integratedLufs: -16, truePeakDbtp: -1.5, analyzerReport: { path: "qa/loudness.json", sha256: sha(analyzer) } }, pronunciation: { ...pass, reference: "authored-script", scriptPath: "story/screenplay.txt", scriptSha256: sha(script), releaseEligible: true }, encodedVisualReview: pass, titleReview: { ...pass, titleCount: 1 }, actionResultReview: { ...pass, events: [{ segmentId: "hero", actionAtSeconds: 2, resultVisibleAtSeconds: 3, spokenResultAtSeconds: 3.1 }] }, storyReview: { ...pass, cta: "Review your workflow", sequence: { seriesId: "operations", chapter: 2 } } };
  writeFileSync(join(root, "qa", "viewer-release-evidence.json"), JSON.stringify(evidence)); return candidate;
}
test("scenario gate accepts generic entity continuity and rejects an undeclared entity", () => {
  const root = join(scratch, "scenario"); job(root); let result = run(scenarioValidator, [root]); assert.equal(result.code, 0, result.output);
  const board = JSON.parse(readFileSync(join(root, "story", "storyboard.json"), "utf8")); board.beats[0].entityRefs = [{ type: "goal", id: "unrelated-trend" }]; writeFileSync(join(root, "story", "storyboard.json"), JSON.stringify(board));
  result = run(scenarioValidator, [root]); assert.notEqual(result.code, 0); assert.match(result.output, /outside the proven scenario/);
});
test("scenario gate rejects arbitrary source hashes without a readiness handoff and runtime outcome", () => {
  const root = join(scratch, "handoff"); job(root); const source = join(root, "evidence", "source.json"); writeFileSync(source, JSON.stringify({ status: "VERIFIED" }));
  const proofPath = join(root, "evidence", "demo-scenario-proof.json"); const proof = JSON.parse(readFileSync(proofPath, "utf8")); proof.source.sha256 = sha(source); writeFileSync(proofPath, JSON.stringify(proof));
  const result = run(scenarioValidator, [root]); assert.notEqual(result.code, 0); assert.match(result.output, /authenticated workflow/);
});
test("release gate catches voice-before-picture and circular ASR", () => {
  const root = join(scratch, "alignment"); job(root); const candidate = release(root), evidencePath = join(root, "qa", "viewer-release-evidence.json"), evidence = JSON.parse(readFileSync(evidencePath, "utf8"));
  evidence.pronunciation.reference = "asr-transcript"; evidence.actionResultReview.events[0].spokenResultAtSeconds = 2.5; writeFileSync(evidencePath, JSON.stringify(evidence));
  const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /authored script/); assert.match(result.output, /before the picture proves it/);
});
test("release gate rejects unreadable captions, quiet audio, and stale candidate evidence", () => {
  const root = join(scratch, "quality"); job(root); const candidate = release(root), evidencePath = join(root, "qa", "viewer-release-evidence.json"), evidence = JSON.parse(readFileSync(evidencePath, "utf8"));
  writeFileSync(join(root, "qa", "captions.srt"), "1\n00:00:00,000 --> 00:00:01,000\nThis is a very long paragraph subtitle that is deliberately too long for a viewer to read while the product action happens on screen.\n"); evidence.audio.integratedLufs = -26; evidence.titleReview.candidateSha256 = "old-master"; writeFileSync(evidencePath, JSON.stringify(evidence));
  const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /paragraph/); assert.match(result.output, /-16 LUFS/); assert.match(result.output, /not bound/);
});
test("release gate rejects empty captions and invalid timestamp values", () => {
  const root = join(scratch, "timestamps"); job(root); const candidate = release(root), evidencePath = join(root, "qa", "viewer-release-evidence.json"), evidence = JSON.parse(readFileSync(evidencePath, "utf8"));
  writeFileSync(join(root, "qa", "captions.srt"), ""); evidence.captions.sha256 = sha(join(root, "qa", "captions.srt")); evidence.actionResultReview.events[0].spokenResultAtSeconds = "NaN"; writeFileSync(evidencePath, JSON.stringify(evidence));
  const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /no readable cues/); assert.match(result.output, /finite nonnegative/);
});
test("release gate rejects invalid minutes and overlapping caption cues", () => {
  const root = join(scratch, "caption-order"); job(root); const candidate = release(root), evidencePath = join(root, "qa", "viewer-release-evidence.json"), evidence = JSON.parse(readFileSync(evidencePath, "utf8"));
  writeFileSync(join(root, "qa", "captions.srt"), "1\n00:00:61,000 --> 00:01:02,000\nInvalid clock.\n\n2\n00:00:01,000 --> 00:00:03,000\nOverlapping cue.\n"); evidence.captions.sha256 = sha(join(root, "qa", "captions.srt")); writeFileSync(evidencePath, JSON.stringify(evidence));
  const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /invalid or nonpositive/); assert.match(result.output, /overlaps or is out of order/);
});test("release gate passes only with candidate-bound analyzer and reviews", () => { const root = join(scratch, "pass"); job(root); const candidate = release(root); const result = run(releaseValidator, [root, candidate]); assert.equal(result.code, 0, result.output); });
test('release gate consumes exact encoded-picture evidence and rejects lax thresholds', () => {
  const root = join(scratch, 'picture-report'); job(root); const candidate = release(root);
  const picturePath = join(root, 'qa', 'encoded-picture.json');
  let picture = JSON.parse(readFileSync(picturePath, 'utf8'));
  picture.candidate.sha256 = '0'.repeat(64);
  writeFileSync(picturePath, JSON.stringify(picture));
  let result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /exact candidate SHA-256 and byte count/);
  picture.candidate.sha256 = sha(candidate); picture.candidate.bytes += 1;
  writeFileSync(picturePath, JSON.stringify(picture));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /exact candidate SHA-256 and byte count/);
  picture.candidate.bytes = statSync(candidate).size; picture.thresholds.maxStaticSeconds = 999;
  writeFileSync(picturePath, JSON.stringify(picture));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /canonical static and source-binding thresholds/);
  picture.thresholds.maxStaticSeconds = 6; picture.thresholds.bindMaxHamming = 64;
  writeFileSync(picturePath, JSON.stringify(picture));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /canonical static and source-binding thresholds/);
  picture.thresholds.bindMaxHamming = 12; picture.screenRatio = .2;
  writeFileSync(picturePath, JSON.stringify(picture));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /screen coverage and source-bound segments/);
  picture.screenRatio = 1; picture.ok = false; picture.errors = ['source mismatch'];
  writeFileSync(picturePath, JSON.stringify(picture));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /must be a PASS with no errors/);
  rmSync(picturePath);
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /missing qa\/encoded-picture.json/);
});
test("scaffold generates parseable release-gate instructions in an external workspace", () => {
  const product = join(scratch, "product-repo"); const output = join(scratch, "scaffolded"); mkdirSync(product, { recursive: true });
  const result = run(scaffold, ["--repo", product, "--workspace", output]);
  assert.equal(result.code, 0, result.output);
  const readme = readFileSync(join(output, "README.md"), "utf8");
  assert.match(readme, /demo-scenario-proof\.json/);
  assert.match(readme, /viewer-release-evidence\.json/);
});

test("scaffold prefills a capture skeleton from a demo-harness/v1 product without touching the product", () => {
  const product = join(scratch, "harness-product"); const output = join(scratch, "harness-scaffolded");
  mkdirSync(join(product, "demo"), { recursive: true });
  const harness = { harnessVersion: "demo-harness/v1", product: "fixture-app", demoTenant: { id: "t-demo", name: "Fixture Demo Org" },
    reset: { full: "pnpm demo:reset", beat: null }, services: [], baseUrl: "http://127.0.0.1:5173",
    versionEndpoints: [{ service: "api", url: "http://127.0.0.1:8000/api/version" }],
    syntheticLabel: { testId: "synthetic-data-label", text: "Synthetic demo data" }, truthTable: "docs/demo/TRUTH_TABLE.md" };
  const harnessFile = join(product, "demo", "harness.json"); writeFileSync(harnessFile, JSON.stringify(harness));
  const before = sha(harnessFile);
  const result = run(scaffold, ["--repo", product, "--workspace", output]);
  assert.equal(result.code, 0, result.output);
  const scenes = readFileSync(join(output, "capture", "scenes.mjs"), "utf8");
  assert.match(scenes, /baseUrl: "http:\/\/127\.0\.0\.1:5173"/);
  assert.match(scenes, /getByTestId\("synthetic-data-label"\)/);
  assert.match(scenes, /pnpm demo:reset/);
  assert.match(scenes, /api\/version/);
  assert.equal(sha(harnessFile), before);
});

test('campaign release probes exact encoded profile and duration', { skip: spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' }).status !== 0 }, () => {
  const root = join(scratch, 'campaign-encoded'); job(root); const candidate = release(root);
  mkdirSync(join(root, 'capture'), { recursive: true });
  const sourceAsset = join(root, 'capture', 'source-capture.webm'); writeFileSync(sourceAsset, 'synthetic receipt-bound capture fixture');
  writeFileSync(join(root, 'capture', 'manifest.json'), JSON.stringify({ clips: [{ id: 'hero', file: 'source-capture.webm', segments: ['hero'] }] }));
  const jobPath = join(root, 'job.json');
  const jobData = JSON.parse(readFileSync(jobPath, 'utf8'));
  jobData.programForm = 'campaign-flagship'; jobData.deliveryProfile = 'linkedin-4x5'; jobData.durationSeconds = 65;
  jobData.campaign = {
    continuity: { mode: 'single-record', recordId: 'aria-01', scenarioId: 'synthetic-clinic-aria-01' },
    claims: [{ id: 'approval', text: 'Approval is visible.', asOf: '2026-09-22', segmentIds: ['hero'], evidence: { path: 'evidence/source.json', sha256: sha(join(root, 'evidence', 'source.json')) } }],
    assets: [{ id: 'capture', path: 'capture/source-capture.webm', sha256: sha(sourceAsset), origin: 'captured-ui', rights: 'synthetic fixture' }],
    captionRegion: { x: 100, y: 900, width: 700, height: 120 },
  };
  writeFileSync(jobPath, JSON.stringify(jobData));
  writeFileSync(join(root, 'story', 'narration-timeline.json'), JSON.stringify({ durationSeconds: 65, segments: [{ id: 'hero' }] }));
  const encode = (size) => {
    const result = spawnSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i', `color=c=blue:s=${size}:r=1:d=65`, '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', candidate], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const evidencePath = join(root, 'qa', 'viewer-release-evidence.json');
    const releaseEvidence = JSON.parse(readFileSync(evidencePath, 'utf8'));
    releaseEvidence.captions.placementReviewed = true;
    releaseEvidence.captions.region = jobData.campaign.captionRegion;
    const candidateSha256 = sha(candidate);
    writePictureReport(root, candidate);
    writeSyncReport(root, candidate);
    writeStandardReports(root, candidate);
    // campaign-flagship is a marketing cut: the marketing floor report is bound to each encode
    writeFileSync(join(root, 'qa', 'marketing-readiness-check.json'), JSON.stringify({ generator: 'media-studio/validate-marketing-readiness', ok: true, thresholds: { hookMaxSeconds: 2, endCardWindowSeconds: 8, beatToleranceMs: 80, beatHitRatio: 0.9, referencesRequired: 3 }, applies: true, errors: [], warnings: [], candidate: { sha256: candidateSha256, bytes: statSync(candidate).size }, checks: {} }));
    releaseEvidence.candidate.sha256 = candidateSha256;
    for (const key of ['captions', 'audio', 'pronunciation', 'encodedVisualReview', 'titleReview', 'actionResultReview', 'storyReview']) releaseEvidence[key].candidateSha256 = candidateSha256;
    const analyzer = join(root, 'qa', 'loudness.json');
    const report = JSON.parse(readFileSync(analyzer, 'utf8')); report.candidateSha256 = candidateSha256; writeFileSync(analyzer, JSON.stringify(report));
    releaseEvidence.audio.analyzerReport.sha256 = sha(analyzer);
    writeFileSync(evidencePath, JSON.stringify(releaseEvidence));
  };
  encode('1080x1350');
  let result = run(releaseValidator, [root, candidate]); assert.equal(result.code, 0, result.output);
  const evidencePath = join(root, 'qa', 'viewer-release-evidence.json');
  const evidence = JSON.parse(readFileSync(evidencePath, 'utf8'));
  evidence.captions.region.y = 100; writeFileSync(evidencePath, JSON.stringify(evidence));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /placement review matching captionRegion/);
  encode('1080x1350');
  encode('1920x1080');
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /encoded frame/);
  encode('1080x1350'); jobData.durationSeconds = 61; writeFileSync(jobPath, JSON.stringify(jobData));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /differs from job.durationSeconds/);
  jobData.durationSeconds = 65; jobData.programForm = 'campaign-short'; writeFileSync(jobPath, JSON.stringify(jobData));
  result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, /encoded duration must be 10–20 seconds/);
});
test('release gate requires a PASS qa/sync.json bound to the exact candidate with canonical thresholds', () => {
  const root = join(scratch, 'sync-report'); job(root); const candidate = release(root);
  const syncPath = join(root, 'qa', 'sync.json');
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'a canonical PASS report releases');
  const base = JSON.parse(readFileSync(syncPath, 'utf8'));
  const expectFail = (mutate, pattern) => {
    const report = structuredClone(base); mutate(report); writeFileSync(syncPath, JSON.stringify(report));
    const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, pattern);
  };
  expectFail((r) => { r.candidate.sha256 = '0'.repeat(64); }, /sync report is not bound to the exact candidate/);
  expectFail((r) => { r.candidate.bytes += 1; }, /sync report is not bound to the exact candidate/);
  expectFail((r) => { r.ok = false; r.errors = ['beat S02: action-timing: late']; }, /sync report must be a PASS/);
  expectFail((r) => { r.degraded = true; }, /degraded \(non word-level\)/);
  expectFail((r) => { r.thresholds.actionToleranceMs = 1000; }, /canonical thresholds/);
  expectFail((r) => { r.thresholds.driftMaxMs = 200; }, /canonical thresholds/);
  expectFail((r) => { r.thresholds.resultHoldMinSeconds = 0.2; }, /canonical thresholds/);
  expectFail((r) => { r.checks.performed = r.checks.performed.filter((c) => c !== 'av-sync'); }, /did not perform: av-sync/);
  expectFail((r) => { r.beats = [{ beat: 'hero', findings: [] }]; }, /at least one passed action-timing finding/);
  writeFileSync(syncPath, JSON.stringify(base));
  assert.equal(run(releaseValidator, [root, candidate]).code, 0);
  rmSync(syncPath);
  const missing = run(releaseValidator, [root, candidate]); assert.notEqual(missing.code, 0); assert.match(missing.output, /missing qa\/sync.json/);
});

test('release gate requires the video-standard reports bound to the script, receipt and candidate', () => {
  const root = join(scratch, 'video-standard'); job(root); const candidate = release(root);
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'all standard reports bound → releases');
  const expectFail = (mutate, pattern) => {
    writeStandardReports(root, candidate); mutate();
    const result = run(releaseValidator, [root, candidate]); assert.notEqual(result.code, 0); assert.match(result.output, pattern);
  };
  const nc = join(root, 'qa', 'narration-check.json'), fi = join(root, 'qa', 'frame-integrity.json'), pp = join(root, 'qa', 'pointer-path.json');
  const edit = (path, mutate) => { const r = JSON.parse(readFileSync(path, 'utf8')); mutate(r); writeFileSync(path, JSON.stringify(r)); };
  // no fluff
  expectFail(() => rmSync(nc), /missing qa\/narration-check.json; the locked script must pass the no-fluff check/);
  expectFail(() => edit(nc, (r) => { r.ok = false; r.errors = ['S02: version: "since last time"']; }), /narration-check.json must be a PASS with no errors from validate-narration/);
  expectFail(() => writeFileSync(join(root, 'story', 'screenplay.json'), JSON.stringify({ title: 't', scenes: [{ id: 'hero', narration: 'Welcome back. Since last time the plan is ready.' }] })), /narration-check.json is stale: story\/screenplay.json changed/);
  // frame integrity
  expectFail(() => rmSync(fi), /missing qa\/frame-integrity.json/);
  expectFail(() => edit(fi, (r) => { r.candidate.sha256 = '0'.repeat(64); }), /frame-integrity.json is not bound to the exact candidate/);
  expectFail(() => edit(fi, (r) => { r.ok = false; r.errors = ['tiled-frame at 3.5s']; }), /frame-integrity.json must be a PASS/);
  // purposeful cursor (product-screencast)
  expectFail(() => rmSync(pp), /missing qa\/pointer-path.json; every take must pass the pointer-path gate/);
  expectFail(() => edit(pp, (r) => { r.ok = false; r.errors = ['W01: scroll-return']; }), /pointer-path.json must be a PASS/);
  expectFail(() => writeFileSync(join(root, 'capture', 'receipt.json'), JSON.stringify({ clips: { W01: {} } })), /pointer-path.json is stale: capture\/receipt.json changed/);
  expectFail(() => edit(pp, (r) => { delete r.inputs; }), /pointer-path.json does not record the capture receipt it read/);
  // nothing morphed or cropped (product-screencast)
  const pi = join(root, 'qa', 'picture-integrity.json');
  expectFail(() => rmSync(pi), /missing qa\/picture-integrity.json; product footage must pass the picture-integrity gate/);
  expectFail(() => edit(pi, (r) => { r.ok = false; r.errors = ['W03: upscale 1.2x']; }), /picture-integrity.json must be a PASS/);
  expectFail(() => edit(pi, (r) => { r.candidate.bytes += 1; }), /picture-integrity.json is not bound to the exact candidate/);
  // a non-screencast kind inherits no-fluff and frame integrity but not the pointer gate
  writeStandardReports(root, candidate); rmSync(pp); rmSync(pi);
  const jobPath = join(root, 'job.json'); const base = JSON.parse(readFileSync(jobPath, 'utf8'));
  writeFileSync(jobPath, JSON.stringify({ ...base, kind: 'explainer' }));
  rmSync(join(root, 'qa', 'encoded-picture.json')); rmSync(join(root, 'qa', 'sync.json'));
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'explainer without pointer report releases');
  rmSync(nc);
  assert.match(run(releaseValidator, [root, candidate]).output, /missing qa\/narration-check.json/);
  writeFileSync(jobPath, JSON.stringify(base));
});

test('release gate holds marketing cuts to the marketing floor', () => {
  const root = join(scratch, 'marketing-floor'); job(root); const candidate = release(root);
  const jobPath = join(root, 'job.json'); const base = JSON.parse(readFileSync(jobPath, 'utf8'));
  const mk = join(root, 'qa', 'marketing-readiness-check.json');
  const writeMk = (over = {}) => writeFileSync(mk, JSON.stringify({ generator: 'media-studio/validate-marketing-readiness', ok: true, thresholds: { hookMaxSeconds: 2, endCardWindowSeconds: 8, beatToleranceMs: 80, beatHitRatio: 0.9, referencesRequired: 3 }, applies: true, errors: [], warnings: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, checks: {}, ...over }));
  for (const form of ['marketing-cutdown', 'campaign-short', 'social-clip', 'hero']) {
    writeFileSync(jobPath, JSON.stringify({ ...base, programForm: form }));
    if (mk && existsSync(mk)) rmSync(mk);
    const missing = run(releaseValidator, [root, candidate]); assert.notEqual(missing.code, 0, form); assert.match(missing.output, /missing qa\/marketing-readiness-check.json; a marketing cut releases only at or above the marketing floor/);
  }
  writeFileSync(jobPath, JSON.stringify({ ...base, marketing: true }));
  writeMk(); assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'marketing: true with a bound PASS releases');
  writeMk({ ok: false, errors: ['hook-2s: hook lands at 3.2s'] }); assert.match(run(releaseValidator, [root, candidate]).output, /marketing-readiness-check.json must be a PASS/);
  writeMk({ applies: false }); assert.match(run(releaseValidator, [root, candidate]).output, /did not apply the marketing floor/);
  writeMk({ candidate: { sha256: '0'.repeat(64), bytes: 1 } }); assert.match(run(releaseValidator, [root, candidate]).output, /marketing-readiness-check.json is not bound to the exact candidate/);
  writeMk({ thresholds: { hookMaxSeconds: 30, endCardWindowSeconds: 8, beatToleranceMs: 80, beatHitRatio: 0.9, referencesRequired: 3 } }); assert.match(run(releaseValidator, [root, candidate]).output, /marketing-readiness-check.json was not run at the canonical thresholds: hookMaxSeconds 30 \(at most 2\)/, 'a loosened hook floor is not a PASS');
  writeFileSync(jobPath, JSON.stringify(base)); rmSync(mk);
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'a non-marketing role-demo is not held to the floor');
});

test('release gate refuses video-standard reports run with loosened thresholds', () => {
  const root = join(scratch, 'loosened-thresholds'); job(root); const candidate = release(root);
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'canonical thresholds release');
  const fi = join(root, 'qa', 'frame-integrity.json');
  const original = readFileSync(fi, 'utf8');
  const loosened = JSON.parse(original); loosened.thresholds = { ...loosened.thresholds, tilePsnr: 100, lumaJump: 256 };
  writeFileSync(fi, JSON.stringify(loosened));
  const r = run(releaseValidator, [root, candidate]);
  assert.notEqual(r.code, 0);
  assert.match(r.output, /frame-integrity.json was not run at the canonical thresholds: tilePsnr 100 \(at most 32\), lumaJump 256 \(at most 40\)/);
  const stricter = JSON.parse(original); stricter.thresholds = { ...stricter.thresholds, tilePsnr: 28, sampleFps: 4 };
  writeFileSync(fi, JSON.stringify(stricter));
  assert.equal(run(releaseValidator, [root, candidate]).code, 0, 'a stricter run still releases');
  const missing = JSON.parse(original); delete missing.thresholds;
  writeFileSync(fi, JSON.stringify(missing));
  assert.match(run(releaseValidator, [root, candidate]).output, /frame-integrity.json was not run at the canonical thresholds: tilePsnr missing/);
  writeFileSync(fi, original);
});
