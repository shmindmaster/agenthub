// Stage 5: capture. Real product UI only: reuse an existing receipt-bound clip (hash-checked against its capture
// receipt) or, with ui.record and --allow-capture, record it through record-job.mjs. Product repositories stay
// read-only; the film workspace that owns the receipt is also only read.
import { existsSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import { MODULE_ROOT, recordStage } from '../context.mjs';
import { normalizeCuts } from '../lint.mjs';
import { run } from '../mix.mjs';
import { fileSha, readJson, writeJson } from '../util.mjs';

export function resolveClip(ctx, beat) {
  const source = isAbsolute(beat.ui.sourceJob) ? beat.ui.sourceJob : resolve(ctx.specDir, beat.ui.sourceJob);
  const receiptPath = join(source, 'capture', 'receipt.json');
  if (!existsSync(receiptPath)) throw new Error(`${beat.id}: capture receipt not found: ${receiptPath}`);
  const receipt = readJson(receiptPath);
  const entry = receipt.clips?.[beat.ui.clipId];
  if (!entry) throw new Error(`${beat.id}: clip ${beat.ui.clipId} is not in ${receiptPath}`);
  return { source, receipt, entry, file: join(source, 'capture', entry.file) };
}

export async function captureStage(ctx) {
  const out = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    const clips = [];
    for (const beat of cut.beats.filter((b) => b.kind === 'ui')) {
      let r = resolveClip(ctx, beat);
      if (beat.ui.record) {
        if (!ctx.flags.allowCapture) throw new Error(`${beat.id}: ui.record requires --allow-capture (recording starts a browser against the local product build)`);
        const tool = ctx.providers.recordJobPath || join(MODULE_ROOT, '..', 'screencast', 'record-job.mjs');
        ctx.log(`capture/${beat.id}: recording ${beat.ui.clipId} in ${r.source}`);
        const res = await (ctx.providers.run || run)(process.execPath, [tool, r.source, beat.ui.clipId], { timeoutMs: 600000 });
        if (res.code !== 0) throw new Error(`${beat.id}: record-job failed: ${(res.stderr || res.stdout).trim().split('\n').pop()}`);
        r = resolveClip(ctx, beat);
      }
      if (!existsSync(r.file)) throw new Error(`${beat.id}: clip file missing ${r.file}`);
      if (r.entry.valid === false || (r.entry.events?.expectationsFailed || []).length) throw new Error(`${beat.id}: clip ${beat.ui.clipId} is not a valid capture (receipt)`);
      const sha = fileSha(r.file);
      if (sha !== r.entry.sha256) throw new Error(`${beat.id}: clip ${beat.ui.clipId} changed since its capture receipt (sha mismatch); re-record or re-run the receipt backfill`);
      clips.push({
        beatId: beat.id, clipId: beat.ui.clipId, sourceJob: r.source, file: r.file, sha256: sha, clipSeconds: r.entry.clipSeconds, viewport: r.entry.viewport,
        recast: r.entry.recast, headTrimSeconds: r.entry.recastHeadTrimSeconds ?? 0, recordedAt: r.entry.recordedAt, clicks: r.entry.events?.clicks ?? 0,
        actionCount: (r.entry.actions || []).length, freshness: beat.ui.freshness || 'current', freshnessNote: beat.ui.freshnessNote || null,
      });
    }
    out[cut.id] = clips;
    writeJson(join(ctx.jobDir, 'capture', `${cut.id}.json`), { cut: cut.id, clips });
  }
  const stale = Object.values(out).flat().filter((c) => c.freshness !== 'current');
  recordStage(ctx, 'capture', 'done', { clips: Object.values(out).flat().length, recaptureRecommended: stale.map((c) => `${c.beatId}:${c.clipId}`) });
  return out;
}
