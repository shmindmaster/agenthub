// Stage 8: deliver. Fail closed: only ratios whose every required gate passed on the exact candidate ship.
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { recordStage } from '../context.mjs';
import { deleteIntermediates, deliverFiles, mmss } from '../deliver.mjs';
import { normalizeCuts } from '../lint.mjs';
import { fileSha, readJson, writeJson } from '../util.mjs';

export function readmeSection({ ctx, nn, title, delivered, gatesByRatio, date }) {
  const v = ctx.spec.voice;
  const gateLine = Object.entries(gatesByRatio).map(([ratio, g]) => `${ratio}: ${Object.entries(g.gates).map(([k, s]) => `${k} ${s.detail ? `(${s.detail})` : s.status}`).join(', ')}`).join('; ');
  const clips = [...new Set(normalizeCuts(ctx.spec).flatMap((c) => c.beats.filter((b) => b.ui).map((b) => `${b.ui.sourceJob.split(/[\\/]/).pop()}/${b.ui.clipId}`)))];
  return [
    `## ${String(nn).padStart(2, '0')} - ${title} (delivered ${date})`,
    '',
    `${ctx.spec.objective}. Cuts: ${delivered.map((d) => `${d.ratio} ${mmss(d.seconds)} (sha256 ${d.mp4Sha256.slice(0, 12)}...)`).join(', ')}. Narrator: ${v.provider} ${v.name || v.voiceId} (${v.model}), AI-generated, not an owner voice or a celebrity-style clone${v.disclosure ? `; disclosure: ${v.disclosure}` : ''}. Picture: receipt-bound Playwright + Recast captures (${clips.join(', ')}) on the bounded synthetic Demo Clinic, cropped to follow the pointer; generated assets are abstract and assert nothing. Gates on the exact files: ${gateLine}. Ledger: \`${ctx.jobDir}\`.`,
    '',
  ].join('\n');
}

export async function deliverStage(ctx) {
  const rows = [];
  const gatesByRatio = {};
  for (const cut of normalizeCuts(ctx.spec)) {
    for (const ratio of cut.ratios) {
      const gp = join(ctx.jobDir, 'qa', ratio, 'gates.json');
      const ad = join(ctx.jobDir, 'compose', ratio, 'ad.mp4');
      if (!existsSync(gp) || !existsSync(ad)) throw new Error(`deliver: ${ratio} has no gated candidate; run compose and qa first`);
      const g = readJson(gp);
      if (!g.ok) throw new Error(`deliver refused for ${ratio}: ${g.failing.join('; ')}`);
      if (!g.candidate || g.candidate.sha256 !== fileSha(ad)) throw new Error(`deliver refused for ${ratio}: the gates were run on a different file than the current candidate`);
      gatesByRatio[ratio] = g;
      rows.push({ ratio, mp4: ad, srt: join(ctx.jobDir, 'compose', ratio, 'ad.srt'), seconds: readJson(join(ctx.jobDir, 'timing', cut.id, 'timeline.json')).durationSeconds });
    }
  }
  const dir = ctx.brand.deliver.dir;
  const readmePath = join(dir, ctx.brand.deliver.readme || 'README.md');
  if (ctx.flags.dryRun) { ctx.log(`deliver: would ship ${rows.map((r) => r.ratio).join(', ')} to ${dir}`); return { dryRun: true, rows }; }
  const date = new Date().toISOString().slice(0, 10);
  const result = deliverFiles({
    dir, readmePath, reserved: ctx.brand.deliver.reservedNumbers || [], title: ctx.spec.title, files: rows,
    readmeEntry: ({ nn, delivered }) => ({ audience: ctx.spec.audience, pitch: ctx.spec.objective, section: readmeSection({ ctx, nn, title: ctx.spec.title, delivered, gatesByRatio, date }) }),
  });
  const removed = deleteIntermediates(rows.flatMap((r) => [join(ctx.jobDir, 'compose', r.ratio, 'silent.mp4'), join(ctx.jobDir, 'compose', r.ratio, 'mix.wav'), join(ctx.jobDir, 'compose', r.ratio, 'public'), join(ctx.jobDir, 'qa', r.ratio, 'vision-frames')]));
  writeJson(join(ctx.jobDir, 'deliver', 'manifest.json'), { nn: result.nn, deliveredAt: new Date().toISOString(), files: result.delivered, readme: result.readme, intermediatesDeleted: removed, cost: ctx.ledger.summary(), specSha256: ctx.specSha, brandSha256: ctx.brandSha });
  recordStage(ctx, 'deliver', 'done', { nn: result.nn, files: result.delivered.length });
  return result;
}
