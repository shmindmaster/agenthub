// Stage 4: assets. Sound effects and one music bed (ElevenLabs, governed ledger), abstract b-roll stills (OpenAI
// gpt-image) and, where the API exposes it, ElevenLabs video for abstract non-claim b-roll. Every generated asset is
// tagged AI-generated in assets/manifest.json with its prompt, provider, hash and cost.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { estimateCutSeconds, normalizeCuts } from '../lint.mjs';
import { estimateImageUsd, estimateMusicCredits, estimateSfxCredits } from '../prices.mjs';
import { fileSha, hashOf, readJson, writeJson } from '../util.mjs';

export const sfxKey = (prompt, durationSeconds) => hashOf({ kind: 'sfx', prompt, durationSeconds });
export const musicKey = (prompt, lengthMs, model) => hashOf({ kind: 'music', prompt, lengthMs, model });

export function collectSfx(spec) {
  const map = new Map();
  for (const cut of normalizeCuts(spec)) for (const b of cut.beats) for (const s of b.sfx || []) {
    const durationSeconds = s.durationSeconds || 1;
    const key = sfxKey(s.prompt, durationSeconds);
    if (!map.has(key)) map.set(key, { key, prompt: s.prompt, durationSeconds, beats: [] });
    map.get(key).beats.push(`${cut.id}/${b.id}`);
  }
  return [...map.values()];
}

function cutDuration(ctx, cut) {
  const p = join(ctx.jobDir, 'timing', cut.id, 'timeline.json');
  return existsSync(p) ? readJson(p).durationSeconds : estimateCutSeconds(cut);
}

export async function assetsStage(ctx) {
  const cuts = normalizeCuts(ctx.spec);
  const eleven = ctx.providers.elevenlabs || (await import('../providers/elevenlabs.mjs'));
  const sfx = collectSfx(ctx.spec);
  const musicOn = ctx.spec.music?.provider === 'elevenlabs';
  const longest = Math.max(...cuts.map((c) => cutDuration(ctx, c)));
  const lengthMs = Math.max(3000, Math.ceil(longest + 2) * 1000);
  const model = ctx.spec.music?.model || 'music_v2_5';
  const brolls = cuts.flatMap((cut) => cut.beats.filter((b) => b.broll).map((b) => ({ cut, beat: b })));
  const k = stageKey('assets', { sfx: sfx.map((s) => s.key), music: musicOn ? musicKey(ctx.spec.music.prompt, lengthMs, model) : null, broll: brolls.map(({ beat }) => [beat.id, beat.broll]) });
  const cached = checkStage(ctx.jobDir, 'assets', 'all', k);
  if (cached.hit && !ctx.flags.force) { ctx.log('assets: cached'); return cached.manifest; }
  const items = [];
  const skipped = [];
  const cli = ctx.providers.elevenCli || (sfx.length || musicOn ? eleven.resolveCli(ctx.brand) : null);

  for (const s of sfx) {
    const rel = join('assets', 'sfx', `${s.key.slice(0, 16)}.mp3`);
    const out = join(ctx.jobDir, rel);
    const credits = estimateSfxCredits(s.durationSeconds);
    if (ctx.flags.dryRun) { items.push({ kind: 'sfx', key: s.key, planned: credits }); continue; }
    mkdirSync(join(ctx.jobDir, 'assets', 'sfx'), { recursive: true });
    let receipt = null;
    if (!existsSync(out)) {
      ctx.ledger.check('elevenlabs', credits, `sfx "${s.prompt.slice(0, 30)}"`);
      ctx.log(`assets: sfx "${s.prompt}" (${s.durationSeconds}s)`);
      const res = await eleven.soundEffect(cli, { prompt: s.prompt, output: out, durationSeconds: s.durationSeconds, maxCredits: credits, workspace: ctx.workspaceId, revision: 'mvg-sfx-v1', promptInfluence: 0.5, run: ctx.providers.runCli });
      receipt = res.receipt;
      ctx.ledger.charge({ stage: 'assets', provider: 'elevenlabs', service: 'sfx', units: receipt.actual_credits ?? credits, estimated: receipt.actual_credits == null, cached: !!receipt.reused, ref: s.key.slice(0, 12) });
    } else ctx.ledger.charge({ stage: 'assets', provider: 'elevenlabs', service: 'sfx', units: 0, cached: true, ref: s.key.slice(0, 12) });
    items.push({ kind: 'sfx', key: s.key, path: rel.replace(/\\/g, '/'), sha256: fileSha(out), provider: 'elevenlabs', model: 'eleven_text_to_sound_v2', prompt: s.prompt, durationSeconds: s.durationSeconds, aiGenerated: true, usedBy: s.beats, receipt });
  }

  if (musicOn) {
    const key = musicKey(ctx.spec.music.prompt, lengthMs, model);
    const rel = join('assets', 'music', `${key.slice(0, 16)}.mp3`);
    const out = join(ctx.jobDir, rel);
    const credits = estimateMusicCredits(lengthMs);
    if (ctx.flags.dryRun) items.push({ kind: 'music', key, planned: credits });
    else {
      mkdirSync(join(ctx.jobDir, 'assets', 'music'), { recursive: true });
      let receipt = null;
      if (!existsSync(out)) {
        ctx.ledger.check('elevenlabs', credits, 'music bed');
        ctx.log(`assets: music bed ${lengthMs / 1000}s (${model}), licence basis recorded`);
        const res = await eleven.music(cli, { prompt: ctx.spec.music.prompt, output: out, lengthMs, model, maxCredits: credits, workspace: ctx.workspaceId, revision: 'mvg-music-v1', run: ctx.providers.runCli });
        receipt = res.receipt;
        ctx.ledger.charge({ stage: 'assets', provider: 'elevenlabs', service: 'music', units: receipt.actual_credits ?? credits, estimated: receipt.actual_credits == null, cached: !!receipt.reused, ref: key.slice(0, 12) });
      } else ctx.ledger.charge({ stage: 'assets', provider: 'elevenlabs', service: 'music', units: 0, cached: true, ref: key.slice(0, 12) });
      items.push({ kind: 'music', key, path: rel.replace(/\\/g, '/'), sha256: fileSha(out), provider: 'elevenlabs', model, prompt: ctx.spec.music.prompt, lengthMs, instrumental: true, licenseBasis: ctx.spec.music.licenseBasis, aiGenerated: true, receipt });
    }
  }

  for (const { cut, beat } of brolls) {
    const b = beat.broll;
    const portraitOnly = cut.ratios.every((r) => r === '9x16' || r === '4x5');
    const size = portraitOnly ? '1024x1536' : '1536x1024';
    if (b.provider === 'elevenlabs-video') {
      skipped.push({ beat: `${cut.id}/${beat.id}`, provider: b.provider, reason: 'ElevenLabs image/video are not exposed by the governed REST adapter (Creative platform / full-connector only; REST endpoints unverified as of 2026-10-20). No video was generated.' });
      continue;
    }
    if (b.provider === 'stock') {
      if (!b.file) { skipped.push({ beat: `${cut.id}/${beat.id}`, provider: 'stock', reason: 'no licensed stock file supplied (broll.file)' }); continue; }
      items.push({ kind: 'broll', beat: `${cut.id}/${beat.id}`, path: b.file, provider: 'stock', aiGenerated: false });
      continue;
    }
    const model = ctx.brand.images?.model || 'gpt-image-2';
    const quality = b.quality || ctx.brand.images?.quality || 'medium';
    const key = hashOf({ kind: 'image', model, size, quality, prompt: b.prompt });
    const rel = join('assets', 'broll', `${beat.id}-${key.slice(0, 12)}.png`);
    const out = join(ctx.jobDir, rel);
    const usd = estimateImageUsd(model, quality);
    if (ctx.flags.dryRun) { items.push({ kind: 'broll', key, planned: usd }); continue; }
    mkdirSync(join(ctx.jobDir, 'assets', 'broll'), { recursive: true });
    if (!existsSync(out)) {
      ctx.ledger.check('openai', usd, 'gpt-image');
      ctx.log(`assets: still for ${beat.id} (${model} ${quality} ${size})`);
      const img = await (ctx.providers.generateImage || (await import('../providers/openai.mjs')).generateImage)({ prompt: b.prompt, model, size, quality });
      writeFileSync(out, img.bytes);
      ctx.ledger.charge({ stage: 'assets', provider: 'openai', service: 'image', units: usd, ref: key.slice(0, 12) });
    } else ctx.ledger.charge({ stage: 'assets', provider: 'openai', service: 'image', units: 0, cached: true, ref: key.slice(0, 12) });
    items.push({ kind: 'broll', key, beat: `${cut.id}/${beat.id}`, path: rel.replace(/\\/g, '/'), sha256: fileSha(out), provider: 'openai', model, size, quality, prompt: b.prompt, aiGenerated: true });
  }

  if (ctx.flags.dryRun) { recordStage(ctx, 'assets', 'dry-run', { planned: items }); return { dryRun: true, items, skipped }; }
  const manifestPath = join(ctx.jobDir, 'assets', 'manifest.json');
  writeJson(manifestPath, { items, skipped, note: 'Every generated asset is AI-generated and asserts nothing; real product UI carries every claim.' });
  const manifest = writeStage(ctx.jobDir, 'assets', 'all', k, { items, skipped, outputs: [relative(ctx.jobDir, manifestPath), ...items.filter((i) => i.path && i.provider !== 'stock').map((i) => i.path)] });
  recordStage(ctx, 'assets', 'done', { items: items.length, skipped: skipped.length });
  return manifest;
}
