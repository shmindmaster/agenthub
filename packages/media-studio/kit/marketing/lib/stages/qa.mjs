// Stage 7: qa, per ratio, on the exact encoded file. Gates: band-bound picture, captions, loudness, sync and Local-AI
// listen (local, --local-gates), OpenAI vision QA, the story score (reviewer file), and validate-viewer-release.
// Anything that did not run on this exact candidate is `pending`, never a pass, and deliver refuses to ship it.
import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { MODULE_ROOT, recordStage } from '../context.mjs';
import { DEFAULT_REQUIRED, assembleEvidence, buildGateWorkspace, captionsCheck, readReviews, releasable } from '../gates.mjs';
import { measureLoudness, gateScript, runSyncGates } from '../local-gates.mjs';
import { loudnessTarget, run } from '../mix.mjs';
import { runPictureGate } from '../picture-gate.mjs';
import { normalizeCuts } from '../lint.mjs';
import { fileSha, readJson, writeJson } from '../util.mjs';
import { resolveClip } from './capture.mjs';
import { runVisionQa } from '../../vision-qa.mjs';

const pending = (detail) => ({ status: 'pending', detail });

export async function qaStage(ctx) {
  const required = ctx.spec.qa?.required || DEFAULT_REQUIRED;
  const out = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    const timeline = readJson(join(ctx.jobDir, 'timing', cut.id, 'timeline.json'));
    const capture = existsSync(join(ctx.jobDir, 'capture', `${cut.id}.json`)) ? readJson(join(ctx.jobDir, 'capture', `${cut.id}.json`)).clips : [];
    for (const ratio of cut.ratios) {
      const cdir = join(ctx.jobDir, 'compose', ratio);
      const qdir = join(ctx.jobDir, 'qa', ratio);
      const ws = join(qdir, 'ws');
      mkdirSync(qdir, { recursive: true });
      const composeMap = readJson(join(cdir, 'compose-map.json'));
      const gateSegments = readJson(join(cdir, 'gate-segments.json'));
      const clips = capture.map((c) => ({ ...c, receiptEntry: resolveClip(ctx, cut.beats.find((b) => b.id === c.beatId)).entry }));
      const asr = Object.fromEntries((timeline.lines || []).filter((l) => l.asr).map((l) => [l.beatId, join(ctx.jobDir, l.asr)]));
      const target = loudnessTarget(ratio, ctx.spec, ctx.brand);
      buildGateWorkspace({ root: ws, spec: ctx.spec, cut, ratio, timeline, composeMap, clips, asr, loudnessLufs: target.lufs });
      const ad = join(cdir, 'ad.mp4');
      const gates = {};
      if (!existsSync(ad) || ctx.flags.prepareOnly) {
        for (const g of required) gates[g] = pending('no encoded candidate yet (compose renders it) or --prepare-only');
        const verdict = releasable(gates, required);
        writeJson(join(qdir, 'gates.json'), { ratio, candidate: null, gates, ...verdict });
        out[ratio] = { ...verdict, gates };
        continue;
      }
      const sha = fileSha(ad);
      const candidate = join(ws, 'output', `${ctx.spec.id}.mp4`);
      copyFileSync(ad, candidate);
      const srt = join(ws, 'output', `${ctx.spec.id}.srt`);
      copyFileSync(join(cdir, 'ad.srt'), srt);

      const pic = runPictureGate({ candidate: ad, band: gateSegments.band, segments: gateSegments.segments, durationSeconds: gateSegments.durationSeconds });
      writeJson(join(qdir, 'picture.json'), pic);
      gates.picture = pic.ok ? { status: 'pass', detail: `UI ratio ${pic.screenRatio}` } : { status: 'fail', detail: pic.errors.slice(0, 2).join(' | ') };

      const cap = captionsCheck(readFileSync(srt, 'utf8'));
      gates.captions = cap.ok ? { status: 'pass', detail: `${cap.cues} cues` } : { status: 'fail', detail: cap.errors.slice(0, 2).join(' | ') };

      const loudPath = join(ws, 'qa', `loudness-${ctx.spec.id}.json`);
      const loud = await measureLoudness(candidate, loudPath);
      gates.loudness = Math.abs(loud.integratedLufs - target.lufs) <= 1.0 && loud.truePeakDbtp <= -1.0 ? { status: 'pass', detail: `${loud.integratedLufs} LUFS / ${loud.truePeakDbtp} dBTP (target ${target.lufs})` } : { status: 'fail', detail: `${loud.integratedLufs} LUFS / ${loud.truePeakDbtp} dBTP vs target ${target.lufs}` };

      if (ctx.flags.localGates) {
        const local = await runSyncGates({ ws, candidate, moduleRoot: MODULE_ROOT, composeMapRel: `output/${ctx.spec.id}-compose-map.json`, sourceRevision: ctx.spec.id });
        gates.sync = local.sync;
        gates.listen = local.listen;
      } else { gates.sync = pending('needs local ASR (GPU); run with --local-gates'); gates.listen = pending('needs the Local-AI listen gate (GPU); run with --local-gates'); }

      if (ctx.flags.noVision) gates.vision = pending('skipped by --no-vision');
      else {
        try {
          // Frames are sampled away from caption transitions, and a reviewer's arbitration (never written by mvg) is honoured only
          // when it names this exact candidate hash.
          const arbPath = join(qdir, 'vision-arbitration.json');
          const v = await runVisionQa({ candidate: ad, spec: ctx.spec, brand: ctx.brand, ratio, ledger: ctx.ledger, vision: ctx.providers.vision, frames: ctx.providers.frames, framesDir: join(qdir, 'vision-frames'), duration: gateSegments.durationSeconds, cues: readJson(join(ctx.jobDir, 'timing', cut.id, 'captions.json')).chunks, arbitration: existsSync(arbPath) ? readJson(arbPath) : null });
          writeJson(join(qdir, 'vision.json'), v);
          const arb = v.arbitration?.honoured ? { reviewer: v.arbitration.reviewer, applied: v.arbitration.applied, ignored: v.arbitration.ignored } : v.arbitration?.file ? { reviewer: null, applied: [], ignored: v.arbitration.ignored } : null;
          gates.vision = v.ok ? { status: 'pass', detail: `${v.sampled.length} frames, ${v.findings.length} findings${v.arbitration?.applied?.length ? `, ${v.arbitration.applied.length} arbitrated false-positive by ${v.arbitration.reviewer}` : ' (none blocking)'}`, ...(arb ? { arbitration: arb } : {}) } : { status: 'fail', detail: v.reasons.slice(0, 2).join(' | '), ...(arb ? { arbitration: arb } : {}) };
        } catch (e) { gates.vision = { status: 'fail', detail: e.message }; }
      }

      const reviews = readReviews(join(qdir, 'reviews.json'), sha);
      const storyMin = ctx.spec.qa?.storyMin ?? 85;
      const sr = reviews.storyReview;
      gates.story = sr && sr.reviewer && Number(sr.score) >= storyMin && sr.cta ? { status: 'pass', detail: `score ${sr.score} by ${sr.reviewer}` } : pending(`media-story-experience-reviewer score >= ${storyMin} on this candidate (qa/${ratio}/reviews.json storyReview)`);

      const evidenceReady = ['encodedVisualReview', 'titleReview', 'actionResultReview', 'storyReview', 'pronunciation'].every((k) => reviews[k]?.status === 'PASS');
      if (!evidenceReady) gates.viewerRelease = pending('reviews.json needs PASS entries (encodedVisualReview, titleReview, actionResultReview, storyReview, pronunciation) for this candidate');
      else {
        const evidence = assembleEvidence({ root: ws, candidate, candidateSha: sha, srtPath: srt, loudnessReportPath: loudPath, loudness: loud, reviews, scriptPath: join(ws, 'story', 'locked-script.txt') });
        writeJson(join(ws, 'qa', 'viewer-release-evidence.json'), evidence);
        for (const name of ['encoded-picture.json']) if (!existsSync(join(ws, 'qa', name))) copyFileSync(join(qdir, 'picture.json'), join(ws, 'qa', name));
        const vr = await run(process.execPath, [gateScript('validate-viewer-release.mjs', MODULE_ROOT), ws, candidate], {});
        let parsed = null;
        try { parsed = JSON.parse(vr.stdout); } catch { parsed = null; }
        gates.viewerRelease = vr.code === 0 && parsed?.ok ? { status: 'pass', detail: 'validate-viewer-release ok' } : { status: 'fail', detail: (parsed?.errors || [vr.stderr]).slice(0, 3).join(' | ') };
      }
      const verdict = releasable(gates, required);
      writeJson(join(qdir, 'gates.json'), { ratio, candidate: { path: ad, sha256: sha }, required, gates, ...verdict });
      out[ratio] = { ...verdict, gates, candidateSha256: sha };
    }
  }
  const allOk = Object.values(out).every((r) => r.ok);
  recordStage(ctx, 'qa', allOk ? 'pass' : 'pending-or-fail', { ratios: Object.fromEntries(Object.entries(out).map(([k, v]) => [k, { ok: v.ok, failing: v.failing }])) });
  return out;
}
