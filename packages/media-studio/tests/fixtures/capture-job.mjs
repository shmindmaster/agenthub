// A minimal viewer-facing product-screencast job for the capture gates: real encoded clips, a sealed receipt and a passing
// scenario proof. Used by capture-receipt.test.mjs and screencast-gates.test.mjs.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { sealReceipt } from '../../kit/screencast/receipt-lib.mjs';

export const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
export const write = (p, data) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2)); };
export const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));
export const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { windowsHide: true, timeout: 120000, stdio: ['ignore', 'ignore', 'inherit'] });
export const hasFfmpeg = () => { try { for (const t of ['ffmpeg', 'ffprobe']) execFileSync(t, ['-version'], { windowsHide: true, timeout: 10000, stdio: 'ignore' }); return true; } catch { return false; } };

export const IDENTITY = { persona: 'parent', scenarioId: 'weeknight', sourceRevision: 'f1c30ee967', servedRevision: 'f1c30ee967', baseUrl: 'http://127.0.0.1:8080', kitVersion: '9.9.0' };

/** evidence/demo-scenario-proof.json with its handoff and runtime outcome, as write-scenario-proof.mjs leaves them. */
export function writeProof(root, { heroSegment = 'S02', identity = IDENTITY, entities = [{ type: 'clinic', id: 'demo-clinic' }] } = {}) {
  const outcome = join(root, 'evidence', 'runtime-outcome.json');
  write(outcome, { status: 'PASS' });
  const handoff = join(root, 'evidence', 'readiness-handoff.json');
  write(handoff, { status: 'DEMO-READY', workflow: { authenticated: true, actionResultObserved: true }, runtimeOutcome: { path: 'evidence/runtime-outcome.json', sha256: sha(outcome), status: 'PASS' } });
  write(join(root, 'evidence', 'demo-scenario-proof.json'), {
    scenarioId: identity.scenarioId, synthetic: true, persona: 'Parent, synthetic Demo Clinic', personaId: identity.persona, problem: 'p',
    sourceRevision: identity.sourceRevision, servedRevision: identity.servedRevision, baseUrl: identity.baseUrl,
    hero: { segmentId: heroSegment, beforeState: 'a', action: 'b', visibleResult: 'c' }, outcome: { statement: 's', evidence: 'e' }, continuity: { entities },
    source: { kind: 'product-readiness-handoff', status: 'DEMO-READY', path: 'evidence/readiness-handoff.json', sha256: sha(handoff), verifiedAt: '2026-11-24T00:00:00Z' },
  });
}

/** Write capture/receipt.json the way record-job.mjs does: provenance on every clip, then the seal. */
export function putReceipt(root, receipt, identity = IDENTITY) {
  const clips = Object.fromEntries(Object.entries(receipt.clips).map(([id, c]) => [id, { provenance: { ...identity }, ...c }]));
  write(join(root, 'capture', 'receipt.json'), sealReceipt({ ...receipt, clips }));
}

export function writeCaptureJob(root, { seconds = 16, clip = null, job = {} } = {}) {
  const file = join(root, 'capture', 'clips', 'S02.webm');
  mkdirSync(dirname(file), { recursive: true });
  if (clip) writeFileSync(file, readFileSync(clip));
  else ff(['-f', 'lavfi', '-i', `testsrc2=size=640x360:rate=30:duration=${seconds}`, '-c:v', 'libvpx', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '600k', '-pix_fmt', 'yuv420p', file]);
  write(join(root, 'job.json'), { kind: 'product-screencast', title: 't', repositoryWritePolicy: 'read-only', programForm: 'role-demo', intent: 'viewer-facing', ...job });
  write(join(root, 'story', 'storyboard.json'), { title: 't', scenarioId: IDENTITY.scenarioId, cta: 'Open the portal', beats: [{ id: 'S02', visualMode: 'screen', durationSeconds: seconds }] });
  write(join(root, 'story', 'narration-timeline.json'), { durationSeconds: seconds, segments: [{ id: 'S02', scene: 'S02', text: 'Save it.', startSeconds: 0, durationSeconds: seconds }] });
  write(join(root, 'story', 'capture-plan.json'), { scenes: [{ sceneId: 'S02', kind: 'interaction', action: 'click Save', expectedResult: 'thanks', startState: 'form', resultState: 'thanks', provesClaim: 'it saves', clip: 'clips/S02.webm' }] });
  write(join(root, 'capture', 'manifest.json'), { clips: [{ id: 'S02', file: 'clips/S02.webm', segments: ['S02'] }] });
  writeProof(root);
  putReceipt(root, { generator: 'media-studio/record-job', baseUrl: IDENTITY.baseUrl, clips: { S02: { file: 'clips/S02.webm', sha256: sha(file), recast: 'noZoom', valid: true, actionClock: 'clip', clipSeconds: seconds,
    actions: [{ type: 'move', t: 0.5, x: 10, y: 10 }, { type: 'click', t: 1, tStart: 1, x: 20, y: 20, label: 'Save' }],
    events: { pointerMoves: 24, clicks: 1, keystrokes: 0, scrolls: 0, expectations: 1, expectationsObserved: 1, expectationsFailed: [] } } } });
  return file;
}
