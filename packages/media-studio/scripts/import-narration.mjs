#!/usr/bin/env node
// Turn narration already made by a governed script into the manifest the mvg `import` voice provider reads
// (media-studio/narration-import/1). Pure and offline: it reads files, recomputes hashes, copies audio next to the
// manifest and writes the manifest. It never calls a provider and refuses on any hash or text mismatch.
//
//   node import-narration.mjs --spec <spec.json> --source assemblyai --from <narration-manifest.json | its folder> --out <manifest.json> [--entity E] [--region us|eu]
//   node import-narration.mjs --spec <spec.json> --source deepgram   --from <folder of deepgram_cli receipts>      --out <manifest.json> --entity E
//
// assemblyai: the narration-manifest.json written by narration-preflight.mjs executeAssembly. Each batch must be exactly one
//   narrated beat (every turn made with keepSeparate); turn N is the Nth narrated beat of the spec, in cut and beat order.
//   The batch request hash is recomputed from the beat text, so a changed or misordered line is refused.
// deepgram: a folder holding the --receipt JSON of each deepgram_cli.py run next to its --output audio (same file name, the
//   extension .wav, .mp3 or .m4a). A beat is matched by the SHA-256 of its exact narration text, the receipt's text_sha256.
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const SCHEMA = 'media-studio/narration-import/1';
const ENTITIES = ['abacare', 'mahumtech', 'personal'];
const AUDIO_EXT = ['.wav', '.mp3', '.m4a'];
const HOSTS = { us: 'https://tts.us.assemblyai.com', eu: 'https://tts.eu.assemblyai.com' };
const sha = (data) => createHash('sha256').update(data).digest('hex');
const readJson = (path) => JSON.parse(readFileSync(path, 'utf8').replace(/^﻿/, ''));

function narratedBeats(spec) {
  const cuts = Array.isArray(spec.cuts) && spec.cuts.length ? spec.cuts : [{ id: 'main', beats: spec.beats || [] }];
  return cuts.flatMap((cut) => cut.beats.filter((b) => b.narration).map((b) => ({ cut: Array.isArray(spec.cuts) && spec.cuts.length ? cut.id : undefined, cutId: cut.id, beatId: b.id, text: b.narration })));
}
const label = (b) => `${b.cutId}/${b.beatId}`;

/** First existing path among the candidates, or null. */
const firstFile = (candidates) => candidates.find((p) => existsSync(p) && statSync(p).isFile()) || null;

function entityFor(entity, folder) {
  let value = entity;
  const jobFile = join(folder, 'assemblyai-job.json');
  const recorded = existsSync(jobFile) ? readJson(jobFile).entity : undefined;
  if (entity && recorded && entity !== recorded) throw new Error(`--entity "${entity}" contradicts assemblyai-job.json entity "${recorded}"; the job was authorized for "${recorded}"`);
  if (!value) value = recorded;
  if (!ENTITIES.includes(value)) throw new Error(`name the entity with --entity (${ENTITIES.join(', ')}); none was given or found in assemblyai-job.json`);
  return value;
}

function assemblyLines(spec, from, { entity, region = 'us' }) {
  const file = existsSync(from) && statSync(from).isDirectory() ? join(from, 'narration-manifest.json') : from;
  if (!existsSync(file)) throw new Error(`AssemblyAI narration manifest not found: ${file}`);
  const folder = dirname(resolve(file));
  const host = HOSTS[region];
  if (!host) throw new Error('--region must be us or eu');
  const { results } = readJson(file);
  if (!Array.isArray(results) || !results.length) throw new Error(`${file} has no results`);
  const beats = narratedBeats(spec);
  const byTurn = new Map();
  results.forEach((r, i) => {
    if (!Array.isArray(r.turns) || r.turns.length !== 1) throw new Error(`batch ${i + 1} covers turns [${(r.turns || []).join(', ')}]: each batch must be exactly one beat. Make the narration again with keepSeparate on every turn.`);
    const turn = r.turns[0];
    if (byTurn.has(turn)) throw new Error(`turn ${turn} was split across more than one batch; one beat needs one batch, so shorten that line or split it into two beats`);
    byTurn.set(turn, r);
  });
  if (byTurn.size !== beats.length) throw new Error(`the manifest covers ${byTurn.size} turns but the spec has ${beats.length} narrated beats`);
  const lines = beats.map((beat, i) => {
    const r = byTurn.get(i + 1);
    if (!r) throw new Error(`${label(beat)}: no batch for turn ${i + 1}`);
    const input = { model_id: r.model, voice_id: r.voice, text: beat.text.trim(), sample_rate: 24000, language: 'english', encoding: 'pcm_s16le', container: 'wav', stream: false };
    if (sha(JSON.stringify({ host, input })) !== r.requestSha256) throw new Error(`${label(beat)}: the text does not match the audio request (requestSha256 differs); the line was changed or turn ${i + 1} is not this beat`);
    const wav = firstFile([r.wav, join(folder, basename(String(r.wav || '')))]);
    if (!wav) throw new Error(`${label(beat)}: audio file not found (${r.wav})`);
    const bytes = readFileSync(wav);
    if (sha(bytes) !== r.outputSha256) throw new Error(`${label(beat)}: the audio changed since the provider returned it (outputSha256 differs)`);
    if (!String(r.providerRequestId || '').trim()) throw new Error(`${label(beat)}: the manifest records no provider request id, so the line cannot be traced to a paid request`);
    const actual = r.actualUsd ?? null;
    const usd = actual ?? r.estimatedUsd;
    return { beat, wav, bytes, receipt: { provider: 'assemblyai', requestId: r.providerRequestId, outputSha256: r.outputSha256, usdMicros: Number.isFinite(usd) ? Math.round(usd * 1e6) : null, estimated: actual === null, model: r.model, voice: r.voice, requestSha256: r.requestSha256, ...(r.clone === true ? { clone: true } : {}), ...(r.visibility ? { visibility: r.visibility } : {}) } };
  });
  return { entity: entityFor(entity, folder), lines };
}

function deepgramLines(spec, from, { entity }) {
  if (!existsSync(from) || !statSync(from).isDirectory()) throw new Error(`Deepgram receipts folder not found: ${from}`);
  const receipts = [];
  for (const name of readdirSync(from).filter((n) => n.endsWith('.json')).sort()) {
    let receipt;
    try { receipt = readJson(join(from, name)); } catch { continue; }
    if (receipt?.provider !== 'deepgram' || !receipt.text_sha256) continue;
    const stem = name.replace(/\.receipt\.json$|\.json$/, '');
    receipts.push({ name, receipt, audio: firstFile(AUDIO_EXT.map((e) => join(from, stem + e))) });
  }
  if (!receipts.length) throw new Error(`no Deepgram receipts (provider "deepgram" with text_sha256) in ${from}`);
  if (!ENTITIES.includes(entity)) throw new Error(`name the entity with --entity (${ENTITIES.join(', ')})`);
  const lines = narratedBeats(spec).map((beat) => {
    const hits = receipts.filter((r) => r.receipt.text_sha256 === sha(Buffer.from(beat.text, 'utf8')));
    if (!hits.length) throw new Error(`${label(beat)}: no receipt matches this narration text (text_sha256); the line was changed or never made`);
    if (new Set(hits.map((h) => h.receipt.output_sha256)).size > 1) throw new Error(`${label(beat)}: ${hits.length} receipts match this text with different audio; keep one`);
    const { name, receipt, audio } = hits[0];
    if (!audio) throw new Error(`${label(beat)}: the audio for ${name} is missing (expected the same name with .wav, .mp3 or .m4a)`);
    const bytes = readFileSync(audio);
    if (sha(bytes) !== receipt.output_sha256) throw new Error(`${label(beat)}: the audio changed since the provider returned it (output_sha256 differs from ${name})`);
    if (!String(receipt.request_id || '').trim()) throw new Error(`${label(beat)}: ${name} records no provider request id`);
    const actual = receipt.actual_usd_micros ?? null;
    const usd = actual ?? receipt.maximum_reserved_usd_micros ?? null;
    return { beat, wav: audio, bytes, receipt: { provider: 'deepgram', requestId: receipt.request_id, outputSha256: receipt.output_sha256, usdMicros: Number.isInteger(usd) ? usd : null, estimated: actual === null, model: receipt.model, voice: receipt.model, reused: Boolean(receipt.reused), cacheKey: receipt.cache_key, ...(receipt.clone === true ? { clone: true } : {}), ...(receipt.visibility ? { visibility: receipt.visibility } : {}) } };
  });
  return { entity, lines };
}

/** Build the manifest and copy the audio beside it. Throws on any mismatch before anything is written. */
export function importNarration({ spec, source, from, out, entity, region }) {
  const build = { assemblyai: assemblyLines, deepgram: deepgramLines }[source];
  if (!build) throw new Error('--source must be assemblyai or deepgram');
  const built = build(spec, resolve(from), { entity, region });
  const outPath = resolve(out);
  const dir = join(dirname(outPath), 'audio');
  const lines = built.lines.map(({ beat, wav, bytes, receipt }) => {
    const ext = extname(wav).toLowerCase();
    if (!AUDIO_EXT.includes(ext)) throw new Error(`${label(beat)}: ${basename(wav)} must be wav, mp3 or m4a`);
    const file = `audio/${beat.cutId}-${beat.beatId}-${sha(bytes).slice(0, 12)}${ext}`;
    const target = join(dirname(outPath), file);
    if (existsSync(target) && sha(readFileSync(target)) !== sha(bytes)) throw new Error(`${label(beat)}: ${file} already exists with different audio`);
    return { beat, wav, target, line: { beatId: beat.beatId, ...(beat.cut ? { cut: beat.cut } : {}), textSha256: sha(Buffer.from(beat.text, 'utf8')), file, sha256: sha(bytes), receipt } };
  });
  mkdirSync(dir, { recursive: true });
  for (const { wav, target } of lines) if (!existsSync(target)) copyFileSync(wav, target);
  const manifest = { schema: SCHEMA, source, entity: built.entity, lines: lines.map((l) => l.line) };
  writeFileSync(outPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  return manifest;
}

function parseArgs(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--') || argv[i + 1] === undefined || argv[i + 1].startsWith('--')) throw new Error(`${a} needs a value`);
    flags[a.slice(2)] = argv[++i];
  }
  for (const k of ['spec', 'source', 'from', 'out']) if (!flags[k]) throw new Error(`--${k} is required`);
  return flags;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const f = parseArgs(process.argv.slice(2));
    const manifest = importNarration({ spec: readJson(f.spec), source: f.source, from: f.from, out: f.out, entity: f.entity, region: f.region });
    console.log(JSON.stringify({ ok: true, out: resolve(f.out), lines: manifest.lines.length, source: manifest.source }));
  } catch (e) {
    console.error(`import-narration: ${e.message}`);
    process.exit(1);
  }
}
