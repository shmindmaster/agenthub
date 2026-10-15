import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
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
const syncReport = (candidate, over = {}) => ({ generator: 'media-studio/validate-sync', ok: true, degraded: false, errors: [], warnings: [], candidate: { sha256: sha(candidate), bytes: statSync(candidate).size }, thresholds: { actionToleranceMs: 300, screenToleranceMs: 40, resultHoldMinSeconds: 1.5, driftMaxMs: 40, maxFreezeSeconds: 4, maxDroppedFrames: 3 }, precision: { allWordLevel: true, degradedBeats: [] }, beats: [{ beat: 'hero', status: 'pass', findings: [{ check: 'action-timing', status: 'pass' }] }], checks: { performed: ['screen-on', 'action-timing', 'result-hold', 'narration-order', 'av-sync', 'frozen-frames', 'dropped-frames'], notPerformed: [{ check: 'text-clipping', reason: 'no OCR' }] }, ...over });
const writeSyncReport = (root, candidate, over) => writeFileSync(join(root, 'qa', 'sync.json'), JSON.stringify(syncReport(candidate, over)));
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
  mkdirSync(join(root, 'capture'));
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
