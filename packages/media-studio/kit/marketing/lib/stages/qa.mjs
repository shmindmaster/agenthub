// Stage 7: qa, per ratio, on the exact encoded file. Gates: band-bound picture, captions, loudness, sync / word-sync /
// transcript (only with an injected aligner: Local AI is off), listen (no runner: pending), the film-chain gates (picture
// integrity, pointer path, frame integrity, marketing readiness), vision QA, the story score (reviewer file), and
// validate-viewer-release.
// Anything that did not run on this exact candidate is `pending`, never a pass, and deliver refuses to ship it.
import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { MODULE_ROOT, recordStage } from '../context.mjs';
import { runFrameIntegrityGate, runIntegrityGate, runMarketingGate, runPointerGate } from '../chain-gates.mjs';
import { assembleEvidence, buildGateWorkspace, captionsCheck, readReviews, releasable, requiredGates } from '../gates.mjs';
import { measureLoudness, gateScript, runSyncGates } from '../gate-runners.mjs';
import { loudnessTarget, run } from '../mix.mjs';
import { runPictureGate } from '../picture-gate.mjs';
import { normalizeCuts } from '../lint.mjs';
import { LOCAL_AI_OFF, fileSha, readJson, writeJson } from '../util.mjs';
import { resolveClip } from './capture.mjs';
import { runVisionQa } from '../../vision-qa.mjs';
import { candidatePaths, selectedCuts, verifiedCandidate } from '../candidate.mjs';

const pending = (detail) => ({ status: 'pending', detail });

function pendingGates(required, detail) {
  const gates = {};
  for (const g of required) gates[g] = pending(detail);
  return gates;
}

function gateInputs(ctx, cut, ratio, named, timeline, capture) {
  const cdir = named.dir;
  const ws = join(named.qa, 'ws');
  const composeMap = readJson(join(cdir, 'compose-map.json'));
  const gateSegments = readJson(join(cdir, 'gate-segments.json'));
  const clips = capture.map((c) => ({ ...c, receiptEntry: resolveClip(ctx, cut.beats.find((b) => b.id === c.beatId)).entry }));
  const asr = Object.fromEntries((timeline.lines || []).filter((l) => l.asr).map((l) => [l.beatId, join(ctx.jobDir, l.asr)]));
  const target = loudnessTarget(ratio, ctx.spec, ctx.brand);
  buildGateWorkspace({ root: ws, spec: ctx.spec, cut, ratio, timeline, composeMap, clips, asr, loudnessLufs: target.lufs });
  return { ws, cdir, gateSegments, target };
}

function bindCandidate(ctx, named, ws) {
  const ad = named.ad;
  const sha = named.sha256;
  if (fileSha(ad) !== sha) throw new Error('candidate changed before QA');
  const candidate = join(ws, 'output', `${ctx.spec.id}.mp4`);
  copyFileSync(ad, candidate);
  const srt = join(ws, 'output', `${ctx.spec.id}.srt`);
  copyFileSync(join(named.dir, 'ad.srt'), srt);
  return { ad, sha, candidate, srt, srtSha: fileSha(srt) };
}

async function avGates(ctx, { ad, srt, ws, qdir, gateSegments, target, gates }) {
  const pic = runPictureGate({ candidate: ad, band: gateSegments.band, segments: gateSegments.segments, durationSeconds: gateSegments.durationSeconds });
  writeJson(join(qdir, 'picture.json'), pic);
  gates.picture = pic.ok ? { status: 'pass', detail: `UI ratio ${pic.screenRatio}` } : { status: 'fail', detail: pic.errors.slice(0, 2).join(' | ') };

  const cap = captionsCheck(readFileSync(srt, 'utf8'));
  gates.captions = cap.ok ? { status: 'pass', detail: `${cap.cues} cues` } : { status: 'fail', detail: cap.errors.slice(0, 2).join(' | ') };

  const loudPath = join(ws, 'qa', `loudness-${ctx.spec.id}.json`);
  const loud = await measureLoudness(join(ws, 'output', `${ctx.spec.id}.mp4`), loudPath);
  gates.loudness = Math.abs(loud.integratedLufs - target.lufs) <= 1.0 && loud.truePeakDbtp <= -1.0 ? { status: 'pass', detail: `${loud.integratedLufs} LUFS / ${loud.truePeakDbtp} dBTP (target ${target.lufs})` } : { status: 'fail', detail: `${loud.integratedLufs} LUFS / ${loud.truePeakDbtp} dBTP vs target ${target.lufs}` };
  return { loudPath, loud };
}

async function syncGates(ctx, { ws, candidate, cdir, gates }) {
  // A cue sheet in the workspace must belong to this candidate: the sync gate below rebuilds it, nothing else may leave one behind.
  rmSync(join(ws, 'plan', 'cue-sheet.json'), { force: true });
  // mvg has no listen runner: the Local-AI listen gate is retired and nothing hosted replaces it here.
  gates.listen = pending(`needs a listen review of this candidate; ${LOCAL_AI_OFF}`);
  const P = ctx.providers || {};
  if (P.alignWords) {
    // Injected aligner (a hosted route or a test fake). The encoded transcript is injected the same way; absent, it is pending.
    const hosted = await runSyncGates({ ws, candidate, moduleRoot: MODULE_ROOT, composeMapRel: `output/${ctx.spec.id}-compose-map.json`, voiceLines: readJson(join(cdir, 'mix-plan.json')).lines, align: P.alignWords, transcribe: P.encodedTranscript || null });
    gates.sync = hosted.sync;
    gates.wordSync = hosted.wordSync || pending('word-sync did not run');
    gates.transcript = hosted.transcript || pending(`needs an independent transcript of this candidate; ${LOCAL_AI_OFF}`);
  } else {
    gates.sync = pending(`needs forced alignment of this candidate; ${LOCAL_AI_OFF}`);
    gates.wordSync = pending(`needs a forced-alignment word clock; ${LOCAL_AI_OFF}`);
    gates.transcript = pending(`needs an independent transcript of this candidate; ${LOCAL_AI_OFF}`);
  }
}

// Film-chain gates on the exact encoded candidate (media-studio 2.0.0). They read the ws copies of the compose map and
// receipt; the marketing floor counts only a reviewer's qa/<ratio>/marketing-readiness.json that names this candidate.
async function chainGates(ctx, { ws, qdir, ratio, candidate, sha, gates }) {
  const composeMapRel = `output/${ctx.spec.id}-compose-map.json`;
  gates.integrity = await runIntegrityGate({ ws, candidate, composeMapRel, moduleRoot: MODULE_ROOT });
  gates.pointer = await runPointerGate({ ws, moduleRoot: MODULE_ROOT });
  gates.frameIntegrity = await runFrameIntegrityGate({ ws, candidate, composeMapRel, moduleRoot: MODULE_ROOT });
  gates.marketing = await runMarketingGate({ ws, qdir, ratio, candidate, sha, composeMapRel, moduleRoot: MODULE_ROOT });
}

function visionVerdict(v) {
  const arb = v.arbitration?.honoured ? { reviewer: v.arbitration.reviewer, applied: v.arbitration.applied, ignored: v.arbitration.ignored } : v.arbitration?.file ? { reviewer: null, applied: [], ignored: v.arbitration.ignored } : null;
  return v.ok ? { status: 'pass', detail: `${v.sampled.length} frames, ${v.findings.length} findings${v.arbitration?.applied?.length ? `, ${v.arbitration.applied.length} arbitrated false-positive by ${v.arbitration.reviewer}` : ' (none blocking)'}`, ...(arb ? { arbitration: arb } : {}) } : { status: 'fail', detail: v.reasons.slice(0, 2).join(' | '), ...(arb ? { arbitration: arb } : {}) };
}

async function visionGate(ctx, { ad, qdir, ratio, cut, gateSegments, gates }) {
  if (ctx.flags.noVision) {
    gates.vision = pending('skipped by --no-vision');
    return;
  }
  // The local reviewer is injected only: with Local AI off nothing reviewed the frames, so the gate is pending, not failed.
  if ((ctx.flags.visionProvider || ctx.brand?.vision?.provider || 'local') === 'local' && !ctx.providers?.localVision) {
    gates.vision = pending(`local vision: ${LOCAL_AI_OFF}; or --vision-provider openai (paid, ledger-governed)`);
    return;
  }
  try {
    // Frames are sampled away from caption transitions, and a reviewer's arbitration (never written by mvg) is honoured only
    // when it names this exact candidate hash.
    const arbPath = join(qdir, 'vision-arbitration.json');
    const v = await runVisionQa({ candidate: ad, spec: ctx.spec, brand: ctx.brand, ratio, provider: ctx.flags.visionProvider, ledger: ctx.ledger, vision: ctx.providers.vision, localVision: ctx.providers.localVision, frames: ctx.providers.frames, framesDir: join(qdir, 'vision-frames'), duration: gateSegments.durationSeconds, cues: readJson(join(ctx.jobDir, 'timing', cut.id, 'captions.json')).chunks, arbitration: existsSync(arbPath) ? readJson(arbPath) : null });
    writeJson(join(qdir, 'vision.json'), v);
    gates.vision = visionVerdict(v);
  } catch (e) { gates.vision = { status: 'fail', detail: e.message }; }
}

function storyGate(ctx, ratio, reviews) {
  const storyMin = ctx.spec.qa?.storyMin ?? 85;
  const sr = reviews.storyReview;
  return sr && sr.reviewer && Number(sr.score) >= storyMin && sr.cta ? { status: 'pass', detail: `score ${sr.score} by ${sr.reviewer}` } : pending(`media-studio-qa story-experience review score >= ${storyMin} on this candidate (qa/${ratio}/reviews.json storyReview)`);
}

async function viewerReleaseGate(ctx, { ws, qdir, candidate, sha, srt, loudPath, loud, reviews }) {
  const evidenceReady = ['encodedVisualReview', 'titleReview', 'actionResultReview', 'storyReview', 'pronunciation'].every((k) => reviews[k]?.status === 'PASS');
  if (!evidenceReady) return pending('reviews.json needs PASS entries (encodedVisualReview, titleReview, actionResultReview, storyReview, pronunciation) for this candidate');
  const evidence = assembleEvidence({ root: ws, candidate, candidateSha: sha, srtPath: srt, loudnessReportPath: loudPath, loudness: loud, reviews, scriptPath: join(ws, 'story', 'locked-script.txt') });
  writeJson(join(ws, 'qa', 'viewer-release-evidence.json'), evidence);
  // Always the current candidate's report: a copy left from an earlier render is bound to another SHA-256.
  copyFileSync(join(qdir, 'picture.json'), join(ws, 'qa', 'encoded-picture.json'));
  const vr = await run(process.execPath, [gateScript('validate-viewer-release.mjs', MODULE_ROOT), ws, candidate], {});
  let parsed = null;
  try { parsed = JSON.parse(vr.stdout); } catch { parsed = null; }
  return vr.code === 0 && parsed?.ok ? { status: 'pass', detail: 'validate-viewer-release ok' } : { status: 'fail', detail: (parsed?.errors || [vr.stderr]).slice(0, 3).join(' | ') };
}

async function qaCandidate(ctx, { cut, ratio, timeline, capture, required }) {
  const paths = candidatePaths(ctx, ratio);
  const named = existsSync(paths.ad) ? verifiedCandidate(ctx, ratio) : paths;
  const qdir = named.qa;
  mkdirSync(qdir, { recursive: true });
  if (!existsSync(named.ad) || ctx.flags.prepareOnly) {
    const gates = pendingGates(required, 'no encoded candidate yet (compose renders it) or --prepare-only');
    const verdict = releasable(gates, required);
    writeJson(join(qdir, 'gates.json'), { ratio, candidate: null, gates, ...verdict });
    return { ...verdict, gates };
  }

  const { ws, cdir, gateSegments, target } = gateInputs(ctx, cut, ratio, named, timeline, capture);
  const { ad, sha, candidate, srt, srtSha } = bindCandidate(ctx, named, ws);
  const gates = {};
  const { loudPath, loud } = await avGates(ctx, { ad, srt, ws, qdir, gateSegments, target, gates });
  await syncGates(ctx, { ws, candidate, cdir, gates });
  await chainGates(ctx, { ws, qdir, ratio, candidate, sha, gates });
  await visionGate(ctx, { ad, qdir, ratio, cut, gateSegments, gates });

  const reviews = readReviews(join(qdir, 'reviews.json'), sha);
  gates.story = storyGate(ctx, ratio, reviews);
  gates.viewerRelease = await viewerReleaseGate(ctx, { ws, qdir, candidate, sha, srt, loudPath, loud, reviews });

  const verdict = releasable(gates, required);
  if (fileSha(ad) !== sha || fileSha(candidate) !== sha) throw new Error('candidate changed during QA; no gate verdict published');
  if (fileSha(srt) !== srtSha || fileSha(join(cdir, 'ad.srt')) !== srtSha) throw new Error('subtitles changed during QA; no gate verdict published');
  for (const g of Object.values(gates)) g.candidateSha256 = sha;
  writeJson(join(qdir, 'gates.json'), { ratio, candidate: { id: named.id, path: ad, sha256: sha, bytes: named.bytes }, subtitles: { sha256: srtSha }, specSha256: ctx.specSha, brandSha256: ctx.brandSha, required, gates, ...verdict });
  return { ...verdict, gates, candidateSha256: sha };
}

export async function qaStage(ctx) {
  const required = requiredGates(ctx.spec);
  const out = {};
  for (const cut of selectedCuts(ctx, normalizeCuts(ctx.spec))) {
    const timeline = readJson(join(ctx.jobDir, 'timing', cut.id, 'timeline.json'));
    const capture = existsSync(join(ctx.jobDir, 'capture', `${cut.id}.json`)) ? readJson(join(ctx.jobDir, 'capture', `${cut.id}.json`)).clips : [];
    for (const ratio of cut.ratios) {
      out[ratio] = await qaCandidate(ctx, { cut, ratio, timeline, capture, required });
    }
  }
  const allOk = Object.values(out).every((r) => r.ok);
  if (!ctx.flags.qaDir) recordStage(ctx, 'qa', allOk ? 'pass' : 'pending-or-fail', { ratios: Object.fromEntries(Object.entries(out).map(([k, v]) => [k, { ok: v.ok, failing: v.failing }])) });
  return out;
}
