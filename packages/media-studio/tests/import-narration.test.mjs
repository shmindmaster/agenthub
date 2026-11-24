// scripts/import-narration.mjs: AssemblyAI narration manifests and Deepgram receipts become import manifests.
// Synthetic fixtures; nothing is called.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { importNarration } from '../scripts/import-narration.mjs';
import { CostLedger } from '../kit/marketing/lib/ledger.mjs';
import { voiceStage } from '../kit/marketing/lib/stages/voice.mjs';

const root = mkdtempSync(join(tmpdir(), 'mvg-impnar-'));
test.after(() => rmSync(root, { recursive: true, force: true }));
const sha = (d) => createHash('sha256').update(d).digest('hex');
const TEXTS = ['First line of narration.', 'Second line of narration.'];
const spec = { id: 'imp-narr', beats: TEXTS.map((narration, i) => ({ id: `B${i + 1}`, kind: 'card', narration })) };
const HOST = 'https://tts.us.assemblyai.com';
let n = 0;
const dir = () => { const d = join(root, `c${++n}`); mkdirSync(d, { recursive: true }); return d; };

function assembly({ turns = [[1], [2]], texts = TEXTS, keepWav = true, mutate = (r) => r } = {}) {
  const d = dir();
  const results = turns.map((t, i) => {
    const bytes = Buffer.from(`wav-${n}-${i}`);
    const wav = join(d, `000${i + 1}.wav`);
    writeFileSync(wav, bytes);
    const input = { model_id: 'assemblyai-tts-1', voice_id: 'aai-fixture', text: texts[i].trim(), sample_rate: 24000, language: 'english', encoding: 'pcm_s16le', container: 'wav', stream: false };
    return mutate({ provider: 'assemblyai', model: 'assemblyai-tts-1', voice: 'aai-fixture', speaker: 'narrator', turns: t, requestSha256: sha(JSON.stringify({ host: HOST, input })), outputSha256: sha(bytes), characters: 10, estimatedUsd: 0.0012, actualUsd: null, providerRequestId: `req-${i}`, wav: keepWav ? wav : join('/gone', `000${i + 1}.wav`) }, i);
  });
  writeFileSync(join(d, 'narration-manifest.json'), JSON.stringify({ quoteSha256: 'q', results }));
  writeFileSync(join(d, 'assemblyai-job.json'), JSON.stringify({ entity: 'personal', scriptSha256: 'x', credentialSha256: 'y' }));
  return d;
}
const run = (from, extra = {}) => { const out = join(dir(), 'manifest.json'); return { out, manifest: importNarration({ spec, source: 'assemblyai', from, out, ...extra }) }; };

test('an AssemblyAI manifest becomes an import manifest the voice stage accepts, with receipts and copied audio', async () => {
  const from = assembly();
  const { out, manifest } = run(from);
  assert.equal(manifest.schema, 'media-studio/narration-import/1');
  assert.equal(manifest.source, 'assemblyai');
  assert.equal(manifest.entity, 'personal', 'entity read from assemblyai-job.json');
  assert.equal(manifest.lines.length, 2);
  const [a] = manifest.lines;
  assert.equal(a.textSha256, sha(TEXTS[0]));
  assert.equal(a.receipt.requestId, 'req-0');
  assert.equal(a.receipt.usdMicros, 1200);
  assert.equal(a.receipt.estimated, true);
  assert.equal(a.receipt.outputSha256, a.sha256);
  assert.ok(existsSync(join(out, '..', a.file)));
  const jobDir = join(root, 'job');
  const ctx = { spec: { ...spec, voice: { provider: 'import', voiceId: 'aai-fixture', model: 'assemblyai-tts-1', source: 'assemblyai', manifest: 'manifest.json' } }, specDir: join(out, '..'), jobDir, brand: { entity: 'personal' }, flags: { quiet: true }, providers: {}, log: () => {}, workspaceId: 'w', ledger: new CostLedger({ jobDir, runId: 'r', perRun: {}, cumulative: {} }) };
  const done = await voiceStage(ctx);
  assert.equal(done.main.lines.length, 2);
});

test('the AssemblyAI importer refuses merged batches, split turns, changed text, changed audio, missing ids and no entity', () => {
  assert.throws(() => run(assembly({ turns: [[1, 2]], texts: TEXTS })), /each batch must be exactly one beat.*keepSeparate/);
  assert.throws(() => run(assembly({ turns: [[1], [1]] })), /split across more than one batch/);
  assert.throws(() => run(assembly({ texts: [TEXTS[0], 'Changed second line.'] })), /B2: the text does not match/);
  assert.throws(() => run(assembly({ turns: [[2], [1]] })), /main\/B1: the text does not match/);
  const bad = assembly();
  writeFileSync(join(bad, '0001.wav'), 'tampered');
  assert.throws(() => run(bad), /main\/B1: the audio changed/);
  assert.throws(() => run(assembly({ mutate: (r) => ({ ...r, providerRequestId: null }) })), /no provider request id/);
  const noEntity = assembly();
  rmSync(join(noEntity, 'assemblyai-job.json'));
  assert.throws(() => run(noEntity), /name the entity/);
  assert.equal(run(noEntity, { entity: 'mahumtech' }).manifest.entity, 'mahumtech');
  assert.throws(() => run(assembly(), { region: 'eu' }), /text does not match/, 'the data zone is part of the request hash');
  const moved = assembly({ keepWav: false });
  assert.equal(run(moved).manifest.lines.length, 2, 'a moved wav is found beside the manifest');
});

function deepgram({ texts = TEXTS, drop } = {}) {
  const d = dir();
  texts.forEach((text, i) => {
    if (i === drop) return;
    const bytes = Buffer.from(`dg-${n}-${i}`);
    writeFileSync(join(d, `line${i}.wav`), bytes);
    writeFileSync(join(d, `line${i}.receipt.json`), JSON.stringify({ provider: 'deepgram', model: 'flux-fixture-en', request_id: `dg-req-${i}`, reused: false, output_sha256: sha(bytes), text_sha256: sha(Buffer.from(text)), maximum_reserved_usd_micros: 900, actual_usd_micros: null, cache_key: 'k' }));
  });
  writeFileSync(join(d, 'unrelated.json'), '{"hello":1}');
  return d;
}
const runDg = (from, extra = { entity: 'personal' }) => { const out = join(dir(), 'm.json'); return importNarration({ spec, source: 'deepgram', from, out, ...extra }); };

test('Deepgram receipts are matched to beats by text hash and refused on any mismatch', () => {
  const m = runDg(deepgram());
  assert.equal(m.source, 'deepgram');
  assert.deepEqual(m.lines.map((l) => l.beatId), ['B1', 'B2']);
  assert.equal(m.lines[0].receipt.requestId, 'dg-req-0');
  assert.equal(m.lines[0].receipt.usdMicros, 900);
  assert.equal(m.lines[0].receipt.estimated, true);
  assert.throws(() => runDg(deepgram({ drop: 1 })), /main\/B2: no receipt matches/);
  assert.throws(() => runDg(deepgram({ texts: [TEXTS[0], 'Different words.'] })), /main\/B2: no receipt matches/);
  const tampered = deepgram();
  writeFileSync(join(tampered, 'line0.wav'), 'tampered');
  assert.throws(() => runDg(tampered), /main\/B1: the audio changed/);
  const noAudio = deepgram();
  rmSync(join(noAudio, 'line1.wav'));
  assert.throws(() => runDg(noAudio), /main\/B2: the audio for line1.receipt.json is missing/);
  assert.throws(() => runDg(deepgram(), {}), /name the entity/);
  assert.throws(() => runDg(dir()), /no Deepgram receipts/);
});

test('the command line writes the manifest, and refuses with exit 1 and a message', () => {
  const from = assembly();
  const specPath = join(dir(), 'spec.json');
  writeFileSync(specPath, JSON.stringify(spec));
  const script = fileURLToPath(new URL('../scripts/import-narration.mjs', import.meta.url));
  const out = join(dir(), 'm.json');
  const ok = spawnSync(process.execPath, [script, '--spec', specPath, '--source', 'assemblyai', '--from', from, '--out', out], { encoding: 'utf8' });
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(JSON.parse(readFileSync(out, 'utf8')).lines.length, 2);
  const bad = spawnSync(process.execPath, [script, '--spec', specPath, '--source', 'assemblyai', '--from', assembly({ turns: [[1, 2]] }), '--out', join(dir(), 'x.json')], { encoding: 'utf8' });
  assert.equal(bad.status, 1);
  assert.match(bad.stderr, /exactly one beat/);
});

test('the importer refuses an --entity that contradicts the job, and writes voice and model into receipts', () => {
  const from = assembly();
  assert.throws(() => run(from, { entity: 'abacare' }), /contradicts.*personal/);
  const { manifest } = run(from, { entity: 'personal' });
  assert.equal(manifest.lines[0].receipt.voice, 'aai-fixture');
  assert.equal(manifest.lines[0].receipt.model, 'assemblyai-tts-1');
  const dg = runDg(deepgram());
  assert.equal(dg.lines[0].receipt.voice, 'flux-fixture-en');
  assert.equal(dg.lines[0].receipt.model, 'flux-fixture-en');
});
