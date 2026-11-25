// Imported narration and stills, provider-labelled accounting and the early b-roll gates of the mvg driver.
// Synthetic fixtures only: no network, no provider is ever called.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lintSpec, OWNER_CLONE_VOICES } from '../kit/marketing/lib/lint.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { CostLedger } from '../kit/marketing/lib/ledger.mjs';
import { lineKey, voiceStage } from '../kit/marketing/lib/stages/voice.mjs';
import { assetsStage } from '../kit/marketing/lib/stages/assets.mjs';
import { readmeSection } from '../kit/marketing/lib/stages/deliver.mjs';
import { readJson } from '../kit/marketing/lib/util.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const mod = join(here, '..', 'kit', 'marketing');
const adSchema = readJson(join(mod, 'ad.schema.json'));
const brandSchema = readJson(join(mod, 'brand.schema.json'));
const root = mkdtempSync(join(tmpdir(), 'mvg-import-'));
test.after(() => rmSync(root, { recursive: true, force: true }));

const sha = (data) => createHash('sha256').update(data).digest('hex');
const TEXTS = { B1: 'A first line of narration.', B2: 'A second line of narration.' };
const brand = { id: 'fixture', entity: 'personal', product: 'Fixture', colors: { primary: '#112233', foreground: '#000000', background: '#ffffff', accent: '#445566' }, fonts: { display: 'A', body: 'B' }, safeZones: {}, forbiddenNames: [], budgets: { elevenlabsCredits: 100, openaiUsd: 1 }, deliver: { dir: join(root, 'deliver') }, loudness: { social: -14, web: -16 } };
const png = (n = 0) => Buffer.concat([Buffer.from([0x89]), Buffer.from('PNG\r\n\x1a\n'), Buffer.alloc(16, n)]);

let counter = 0;
/** A fresh spec folder holding an import manifest (and its audio) for B1 and B2. */
function fixture({ source = 'assemblyai', mutate = (m) => m, voice = {}, ext = 'wav' } = {}) {
  const dir = join(root, `case-${++counter}`);
  mkdirSync(join(dir, 'narration'), { recursive: true });
  const lines = Object.entries(TEXTS).map(([beatId, text], i) => {
    const bytes = Buffer.from(`audio-${counter}-${beatId}`);
    const file = `${beatId}.${ext}`;
    writeFileSync(join(dir, 'narration', file), bytes);
    return { beatId, textSha256: sha(text), file, sha256: sha(bytes),
      receipt: source === 'recording' ? undefined : { provider: source, requestId: `req-${i}`, outputSha256: sha(bytes), usdMicros: 1234, estimated: false, voice: 'fixture-voice', model: 'fixture-model' } };
  });
  const manifest = mutate({ schema: 'media-studio/narration-import/1', source, entity: 'personal', lines });
  writeFileSync(join(dir, 'narration', 'manifest.json'), JSON.stringify(manifest));
  const spec = {
    id: 'import-fixture', title: 'Import fixture', product: 'Fixture', audience: 'Testers', objective: 'Exercise imports', labels: '', claims: [],
    cta: { text: 'See more', url: 'https://example.com/more' }, ratios: ['16x9'], targetSeconds: 8,
    voice: { provider: 'import', voiceId: 'fixture-voice', model: 'fixture-model', source, manifest: 'narration/manifest.json', ...(source === 'recording' ? {} : { disclosure: 'AI-generated narration.' }), ...voice },
    beats: Object.entries(TEXTS).map(([id, narration]) => ({ id, kind: 'card', narration })),
  };
  return { dir, spec, manifestPath: join(dir, 'narration', 'manifest.json') };
}

function ctxFor({ dir, spec }, caps = {}, extra = {}) {
  const jobDir = join(dir, 'jobs', spec.id);
  mkdirSync(jobDir, { recursive: true });
  const trap = new Proxy({}, { get(_t, name) { throw new Error(`a provider was touched: ${String(name)}`); } });
  return { spec, brand, specDir: dir, workspace: dir, jobDir, ledger: new CostLedger({ jobDir, runId: 'r', perRun: caps, cumulative: {} }), flags: { quiet: true }, providers: trap, log: () => {}, workspaceId: 'mvg:test', ...extra };
}
const lint = (spec, dir, options = {}) => lintSpec(spec, brand, { adSchema, brandSchema, specDir: dir, ...options });
const codes = (r) => r.errors.map((e) => e.code);

test('voice import copies verified audio, calls no provider and records a zero-cost cached row labelled with the true source', async () => {
  for (const [source, ext] of [['assemblyai', 'wav'], ['deepgram', 'mp3'], ['azure', 'm4a']]) {
    const f = fixture({ source, ext });
    const ctx = ctxFor(f);
    const out = await voiceStage(ctx);
    const lines = out.main.lines;
    assert.equal(lines.length, 2);
    for (const l of lines) {
      assert.ok(l.file.endsWith(`.${ext}`), 'right extension');
      assert.equal(sha(readFileSync(join(ctx.jobDir, l.file))), l.sha256);
      assert.equal(l.receipt.provider, source);
      assert.equal(l.receipt.imported, true);
      assert.equal(l.receipt.paidElsewhere, true);
    }
    const rows = ctx.ledger.entries.filter((e) => e.stage === 'voice');
    assert.equal(rows.length, 2);
    assert.ok(rows.every((e) => e.provider === source && e.cached === true && e.units === 0), 'cached zero-cost row under the real source');
    const lm = readJson(join(ctx.jobDir, 'voice', 'main.lines.json'));
    assert.equal(lm.voice.aiGenerated, true);
    assert.equal(lm.voice.source, source);
    for (const p of ['elevenlabs', 'openai', 'recording']) assert.equal(ctx.ledger.runTotal(p), 0);
  }
});

test('voice import of a recording is not AI-generated and needs no request id', async () => {
  const f = fixture({ source: 'recording', mutate: (m) => ({ ...m, recordedBy: 'Fixture Narrator' }) });
  const ctx = ctxFor(f);
  const out = await voiceStage(ctx);
  assert.equal(out.main.lines.length, 2);
  assert.equal(readJson(join(ctx.jobDir, 'voice', 'main.lines.json')).voice.aiGenerated, false);
  assert.ok(ctx.ledger.entries.filter((e) => e.stage === 'voice').every((e) => e.provider === 'recording'));
  assert.equal(codes(lint(f.spec, f.dir)).includes('disclosure'), false, 'a recording needs no AI disclosure');
});

test('voice import fails with one message naming the beat for a missing line, changed text, changed audio or a bad receipt', async () => {
  const cases = [
    ['missing line', { mutate: (m) => ({ ...m, lines: m.lines.filter((l) => l.beatId !== 'B2') }) }, /main\/B2: the manifest has no line/],
    ['changed text', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B1' ? { ...l, textSha256: sha('old text') } : l)) }) }, /main\/B1: the narration text changed/],
    ['changed audio', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B2' ? { ...l, sha256: sha('other'), receipt: { ...l.receipt, outputSha256: sha('other') } } : l)) }) }, /main\/B2: the audio changed/],
    ['receipt hash differs', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B1' ? { ...l, receipt: { ...l.receipt, outputSha256: sha('x') } } : l)) }) }, /main\/B1: receipt outputSha256/],
    ['no request id', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B1' ? { ...l, receipt: { ...l.receipt, requestId: '' } } : l)) }) }, /main\/B1: receipt has no provider request id/],
    ['receipt from another provider', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => ({ ...l, receipt: { ...l.receipt, provider: 'deepgram' } })) }) }, /receipt provider "deepgram"/],
    ['path escape', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B1' ? { ...l, file: '../outside.wav' } : l)) }) }, /main\/B1: (audio file missing|audio file .* outside)/],
    ['absolute path', { mutate: (m) => ({ ...m, lines: m.lines.map((l) => (l.beatId === 'B1' ? { ...l, file: join(root, 'abs.wav') } : l)) }) }, /main\/B1: the line file must be a relative path/],
    ['wrong source', { mutate: (m) => ({ ...m, source: 'deepgram' }) }, /manifest source "deepgram"/],
  ];
  for (const [name, opts, pattern] of cases) {
    const f = fixture(opts);
    writeFileSync(join(f.dir, 'outside.wav'), 'x');
    await assert.rejects(voiceStage(ctxFor(f)), pattern, name);
  }
  const unknownExt = fixture({ ext: 'ogg' });
  await assert.rejects(voiceStage(ctxFor(unknownExt)), /must be wav, mp3 or m4a/);
});

test('swapped audio gets a new line key, so old timing is never reused', async () => {
  const a = fixture();
  const b = fixture();
  const ka = lineKey(a.spec, TEXTS.B1, undefined, TEXTS.B2, 0, sha('one'));
  assert.notEqual(ka, lineKey(a.spec, TEXTS.B1, undefined, TEXTS.B2, 0, sha('two')), 'audio sha256 is part of the line key');
  const ctxA = ctxFor(a);
  const first = await voiceStage(ctxA);
  const second = await voiceStage(ctxA);
  assert.equal(second.main.key, first.main.key, 'an unchanged import is a stage cache hit');
  // swap the audio under the same manifest text and hashes of the other fixture
  assert.notEqual(first.main.lines[0].key, (await voiceStage(ctxFor(b))).main.lines[0].key);
});

test('lint: imported narration needs source, manifest, a matching manifest and, for AI sources, a disclosure', () => {
  const f = fixture();
  assert.deepEqual(codes(lint(f.spec, f.dir)).filter((c) => /voice-import|disclosure|owner-voice/.test(c)), []);
  const noDisclosure = structuredClone(f.spec); delete noDisclosure.voice.disclosure;
  assert.ok(codes(lint(noDisclosure, f.dir)).includes('disclosure'));
  const noManifest = structuredClone(f.spec); delete noManifest.voice.manifest;
  assert.ok(codes(lint(noManifest, f.dir)).includes('voice-import'));
  const noSource = structuredClone(f.spec); delete noSource.voice.source;
  assert.ok(codes(lint(noSource, f.dir)).includes('voice-import'));
  const missing = structuredClone(f.spec); missing.voice.manifest = 'narration/none.json';
  assert.match(lint(missing, f.dir).errors.find((e) => e.code === 'voice-import').message, /not found/);
  const changed = structuredClone(f.spec); changed.beats[0].narration = 'Different words now.';
  assert.match(lint(changed, f.dir).errors.find((e) => e.code === 'voice-import').message, /main\/B1 changed since its audio/);
  const lie = structuredClone(f.spec); lie.voice.aiGenerated = false;
  assert.ok(codes(lint(lie, f.dir)).includes('voice-import'), 'synthetic narration cannot claim to be human');
  const rec = fixture({ source: 'recording' });
  const recLie = structuredClone(rec.spec); recLie.voice.aiGenerated = true;
  assert.ok(codes(lint(recLie, rec.dir)).includes('voice-import'));
  const wrongSource = structuredClone(f.spec); wrongSource.voice.source = 'deepgram';
  assert.match(lint(wrongSource, f.dir).errors.find((e) => e.code === 'voice-import').message, /does not match voice.source/);
});

test('lint: an imported AssemblyAI owner clone needs unexpired consent and a disclosure; the ElevenLabs rule is unchanged', () => {
  const consent = (validUntil) => ({ subject: 'Fixture Clone', approvedBy: 'Fixture Owner', approvedAt: '2026-11-01', validUntil });
  const owner = { ownerVoice: true, name: 'Fixture Clone' };
  const none = fixture({ voice: owner });
  assert.match(lint(none.spec, none.dir).errors.find((e) => e.code === 'owner-voice').message, /needs valid consent/);
  const expired = fixture({ voice: owner, mutate: (m) => ({ ...m, consent: consent('2026-11-10') }) });
  assert.match(lint(expired.spec, expired.dir, { now: Date.parse('2026-11-24') }).errors.find((e) => e.code === 'owner-voice').message, /expired/);
  const good = fixture({ voice: owner, mutate: (m) => ({ ...m, consent: consent('2026-12-15') }) });
  assert.equal(codes(lint(good.spec, good.dir, { now: Date.parse('2026-11-24') })).includes('owner-voice'), false);
  const noDisclosure = structuredClone(good.spec); delete noDisclosure.voice.disclosure;
  assert.ok(codes(lint(noDisclosure, good.dir, { now: Date.parse('2026-11-24') })).includes('disclosure'));
  const lineConsent = fixture({ voice: owner, mutate: (m) => ({ ...m, lines: m.lines.map((l) => ({ ...l, receipt: { ...l.receipt, consent: consent('2026-12-15') } })) }) });
  assert.equal(codes(lint(lineConsent.spec, lineConsent.dir, { now: Date.parse('2026-11-24') })).includes('owner-voice'), false, 'consent may sit on every line receipt');
  const partial = fixture({ voice: owner, mutate: (m) => ({ ...m, lines: m.lines.map((l, i) => ({ ...l, receipt: { ...l.receipt, consent: consent(i ? '2026-11-10' : '2026-12-15') } })) }) });
  assert.ok(codes(lint(partial.spec, partial.dir, { now: Date.parse('2026-11-24') })).includes('owner-voice'), 'one expired line spoils the clone');
  const other = fixture({ source: 'deepgram', voice: owner, mutate: (m) => ({ ...m, consent: consent('2026-12-15') }) });
  assert.ok(codes(lint(other.spec, other.dir)).includes('owner-voice'), 'only an AssemblyAI import may be an owner clone');
  const eleven = fixture({ source: 'elevenlabs', voice: owner });
  assert.ok(codes(lint(eleven.spec, eleven.dir)).includes('owner-voice'), 'an ElevenLabs import is not authorised by the import route');
  const direct = structuredClone(good.spec);
  direct.voice = { provider: 'elevenlabs', voiceId: 'clone', model: 'eleven_v4', ownerVoice: true, settings: { apply_text_normalization: 'on' }, disclosure: 'AI' };
  assert.ok(codes(lint(direct, good.dir)).includes('owner-voice'), 'the direct ElevenLabs owner rule still needs its manifest');
});

test('lint and assets: a b-roll still can be imported by hash; a video, a changed file or a missing producer fails early', async () => {
  const f = fixture();
  const still = png(1);
  writeFileSync(join(f.dir, 'still.png'), still);
  writeFileSync(join(f.dir, 'clip.mp4'), Buffer.from('not a still'));
  writeFileSync(join(f.dir, 'fake.png'), Buffer.from('this is text'));
  const withBroll = (broll) => { const s = structuredClone(f.spec); s.beats.push({ id: 'B3', kind: 'broll', broll: JSON.parse(JSON.stringify(broll)) }); return s; };
  const good = { provider: 'import', file: 'still.png', sha256: sha(still), source: 'runware', model: 'fixture-image', aiGenerated: true, prompt: 'an abstract field of soft light', receipt: { provider: 'runware', requestId: 'r-1', outputSha256: sha(still), usdMicros: 5000, estimated: false, entity: 'personal' } };
  const brollCodes = (b) => lint(withBroll(b), f.dir).errors.filter((e) => /^(broll-|schema)/.test(e.code));
  assert.deepEqual(brollCodes(good), []);
  assert.match(brollCodes({ ...good, file: 'clip.mp4', sha256: sha('not a still'), receipt: undefined, source: 'licensed', aiGenerated: false })[0].message, /is a video; compose is image-only/);
  assert.match(brollCodes({ ...good, file: 'fake.png', sha256: sha('this is text'), receipt: undefined, source: 'licensed', aiGenerated: false })[0].message, /not a png, jpg or webp/);
  assert.match(brollCodes({ ...good, sha256: sha('wrong') }).map((e) => e.message).join('|'), /does not match its sha256|does not match broll.sha256/);
  assert.ok(brollCodes({ ...good, aiGenerated: false }).some((e) => e.code === 'broll-import'), 'a Runware still cannot claim to be human-made');
  assert.ok(brollCodes({ ...good, receipt: undefined }).some((e) => /need broll\.receipt/.test(e.message)));
  const { aiGenerated, ...unstated } = good;
  assert.ok(brollCodes(unstated).some((e) => /must state broll\.aiGenerated/.test(e.message)));
  assert.equal(brollCodes({ provider: 'import', file: 'still.png', sha256: sha(still), source: 'licensed', aiGenerated: false, prompt: 'a licensed photograph of a desk' }).length, 0, 'a licensed still needs no provider receipt');
  assert.ok(brollCodes({ provider: 'stock', file: 'clip.mp4', prompt: 'licensed motion background' }).some((e) => /is a video/.test(e.message)));

  const ctx = { ...ctxFor({ dir: f.dir, spec: withBroll(good) }), providers: {} };
  const done = await assetsStage(ctx);
  const item = done.items.find((i) => i.kind === 'broll');
  assert.equal(item.provider, 'import');
  assert.equal(item.aiGenerated, true);
  assert.equal(item.source, 'runware');
  assert.equal(sha(readFileSync(join(ctx.jobDir, item.path))), sha(still), 'copied into the job');
  const row = ctx.ledger.entries.find((e) => e.stage === 'assets' && e.service === 'image');
  assert.equal(row.provider, 'runware');
  assert.equal(row.cached, true);
  assert.equal(row.units, 0);
  // the file changes after lint: the stage refuses it instead of composing something else
  writeFileSync(join(f.dir, 'still.png'), png(9));
  const again = { ...ctxFor({ dir: f.dir, spec: withBroll({ ...good }) }), providers: {} };
  again.flags.force = true;
  await assert.rejects(assetsStage(again), /changed since its sha256 was recorded/);
});

test('the delivery note says what an imported narrator really is', () => {
  const note = (voice) => readmeSection({ ctx: { spec: { objective: 'Obj', voice, beats: [] }, jobDir: 'job', brand: {} }, nn: 1, title: 'T', delivered: [{ ratio: '16x9', seconds: 5, mp4Sha256: 'a'.repeat(64) }], gatesByRatio: {}, date: '2026-11-24' });
  assert.match(note({ provider: 'import', source: 'deepgram', voiceId: 'v', model: 'm', disclosure: 'AI voice' }), /deepgram v \(m\), narration made outside this run and imported by hash, AI-generated; disclosure: AI voice/);
  assert.match(note({ provider: 'import', source: 'recording', voiceId: 'v', model: 'm' }), /recorded narration v \(m\), not AI-generated/);
  assert.match(note({ provider: 'import', source: 'assemblyai', voiceId: 'v', model: 'm', ownerVoice: true, disclosure: 'AI' }), /AI clone of the owner's voice, imported under the consent/);
  assert.doesNotMatch(note({ provider: 'import', source: 'recording', voiceId: 'v', model: 'm' }), /AI-generated, not an owner voice/);
  assert.ok(existsSync(root));
});

// ---- review round: receipts bind the voice, consent is strict, entities agree, imports stay honest
import { estimateCutSeconds, normalizeCuts } from '../kit/marketing/lib/lint.mjs';
import { costErrors, planCost } from '../kit/marketing/lib/stages/lint.mjs';
import { symlinkSync } from 'node:fs';

const setLines = (fn) => (m) => ({ ...m, lines: m.lines.map(fn) });
const OWNER = { ownerVoice: true, name: 'Fixture Clone' };
const NOW = Date.parse('2026-11-24T18:00:00Z');
const consentOf = (over = {}) => ({ subject: 'Fixture Clone', approvedBy: 'Fixture Owner', approvedAt: '2026-11-01', validUntil: '2026-12-15', ...over });
const ownerCase = (consent, extra = {}) => fixture({ voice: OWNER, mutate: (m) => ({ ...m, ...(consent ? { consent } : {}), ...extra }) });
const ownerMsg = (f, now = NOW) => lint(f.spec, f.dir, { now }).errors.filter((e) => e.code === 'owner-voice').map((e) => e.message).join('|');

test('final hold is part of the planned length, per cut over per spec', () => {
  const cut = { id: 'main', beats: [{ id: 'B', kind: 'card', narration: 'One two three four five.' }] };
  const base = estimateCutSeconds(cut);
  assert.ok(Math.abs(estimateCutSeconds(cut, { finalHoldSeconds: 3 }) - base - 3) < 1e-9);
  assert.ok(Math.abs(estimateCutSeconds({ ...cut, finalHoldSeconds: 1 }, { finalHoldSeconds: 3 }) - base - 1) < 1e-9);
  assert.equal(normalizeCuts({ beats: cut.beats, ratios: ['16x9'], targetSeconds: 5, finalHoldSeconds: 2 })[0].finalHoldSeconds, 2);
});

test('an imported line must carry the voice and model the spec declares', async () => {
  await assert.rejects(voiceStage(ctxFor(fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, voice: 'other-voice' } })) }))), /main\/B1: receipt voice "other-voice"/);
  await assert.rejects(voiceStage(ctxFor(fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, model: 'other-model' } })) }))), /receipt model "other-model"/);
  await assert.rejects(voiceStage(ctxFor(fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, voice: undefined } })) }))), /receipt voice/);
});

test('consent: date-only ends that day in US Central, offsets are honoured, a bare date-time is refused', () => {
  const day = ownerCase(consentOf({ validUntil: '2026-11-24' }));
  assert.equal(ownerMsg(day, Date.parse('2026-11-25T05:30:00Z')), '', 'still the 24th in Chicago');
  assert.match(ownerMsg(day, Date.parse('2026-11-25T06:30:00Z')), /expired/, 'the 25th in Chicago');
  const offset = ownerCase(consentOf({ validUntil: '2026-11-24T12:00:00-06:00' }));
  assert.equal(ownerMsg(offset, Date.parse('2026-11-24T17:00:00Z')), '');
  assert.match(ownerMsg(offset, Date.parse('2026-11-24T19:00:00Z')), /expired/);
  assert.match(ownerMsg(ownerCase(consentOf({ validUntil: '2026-12-01T12:00:00' }))), /offset/);
});

test('consent: needs approvedAt within 60 days, the voice name as subject, and cover every narrated line', () => {
  assert.match(ownerMsg(ownerCase(consentOf({ approvedAt: undefined }))), /approvedAt/);
  assert.match(ownerMsg(ownerCase(consentOf({ approvedAt: '2026-08-01', validUntil: '2026-12-15' }))), /60 days/);
  assert.equal(ownerMsg(ownerCase(consentOf({ approvedAt: undefined, recordedAt: '2026-11-01' }))), '', 'recordedAt stands in');
  assert.match(ownerMsg(ownerCase(consentOf({ subject: 'Someone Else' }))), /subject/);
  assert.equal(ownerMsg(ownerCase(consentOf({ subject: '  Fixture Clone ' }))), '', 'trimmed');
  assert.match(ownerMsg(fixture({ voice: OWNER, mutate: setLines((l, i) => (i ? l : { ...l, receipt: { ...l.receipt, consent: consentOf() } })) })), /every narrated line/);
});

test('consent: the 60-day window compares calendar days when both dates are date-only', () => {
  const span = (approvedAt, validUntil, now = Date.parse('2026-09-26T00:00:00Z')) => ownerMsg(ownerCase(consentOf({ approvedAt, validUntil })), now);
  assert.equal(span('2026-09-25', '2026-11-24'), '', 'exactly 60 days after: accepted');
  assert.match(span('2026-09-25', '2026-11-25'), /60 days/, '61 days after: refused');
  assert.equal(span('2026-09-25', '2026-11-23'), '');
  const march = Date.parse('2026-03-02T00:00:00Z');
  assert.equal(span('2026-03-01', '2026-04-30', march), '', 'across a month end and DST change');
  assert.match(span('2026-03-01', '2026-05-01', march), /60 days/);
  // instants keep their exact comparison
  assert.equal(span('2026-09-25T00:00:00Z', '2026-11-24T00:00:00Z'), '', 'exactly 60 x 24 h');
  assert.match(span('2026-09-25T00:00:00Z', '2026-11-24T00:00:01Z'), /60 days/);
  assert.match(span('2026-09-25', '2026-11-24T23:00:00-06:00'), /60 days/, 'a date-time against a date is still compared as instants');
});

test('the voice stage enforces the same consent, so --only voice cannot skip the lint', async () => {
  const stale = ownerCase(consentOf({ validUntil: '2026-11-10' }));
  await assert.rejects(voiceStage(ctxFor(stale, {}, { now: NOW })), /import narration.*consent.*expired/);
  const good = ownerCase(consentOf());
  await voiceStage(ctxFor(good, {}, { now: NOW }));
  const claimed = fixture({ voice: OWNER, source: 'deepgram' });
  await assert.rejects(voiceStage(ctxFor(claimed, {}, { now: NOW })), /only an assemblyai import/);
});

test('a clone or private voice in a receipt requires ownerVoice', async () => {
  const clone = fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, clone: true } })) });
  assert.ok(lint(clone.spec, clone.dir).errors.some((e) => e.code === 'owner-voice' && /clone|private/.test(e.message)));
  await assert.rejects(voiceStage(ctxFor(clone)), /clone or private voice.*ownerVoice/);
  const priv = fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, visibility: 'private' } })) });
  await assert.rejects(voiceStage(ctxFor(priv)), /ownerVoice/);
});

test('a governed owner clone is known by its voice slug, which is all the AssemblyAI script records', async () => {
  for (const slug of OWNER_CLONE_VOICES) {
    const f = fixture({ voice: { voiceId: 'fixture-voice' }, mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, voice: slug } })) });
    assert.ok(codes(lint(f.spec, f.dir)).includes('owner-voice'), `${slug} in a receipt`);
    await assert.rejects(voiceStage(ctxFor(f)), /ownerVoice/);
  }
  const named = fixture({ voice: { voiceId: [...OWNER_CLONE_VOICES][0] }, mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, voice: undefined } })) });
  assert.ok(codes(lint(named.spec, named.dir)).includes('owner-voice'), 'voiceId alone');
  assert.ok(!codes(lint(fixture().spec, fixture().dir)).includes('owner-voice'), 'a stock voice is unaffected');
});

test('the clone slugs are exactly the private voices narration-preflight.mjs will generate', () => {
  const source = readFileSync(join(here, '..', 'scripts', 'narration-preflight.mjs'), 'utf8');
  const list = /approvedOwners = new Set\(\[([^\]]*)\]\)/.exec(source);
  assert.ok(list, 'approvedOwners not found in narration-preflight.mjs');
  assert.deepEqual([...list[1].matchAll(/'([^']+)'/g)].map((m) => m[1]).sort(), [...OWNER_CLONE_VOICES].sort());
});

test('entity: brand and manifest must agree unless an exception is recorded, and the ledger row names the entity', async () => {
  const entityBrand = { ...brand, entity: 'abacare' };
  const f = fixture();
  const clash = lintSpec(f.spec, entityBrand, { adSchema, brandSchema, specDir: f.dir });
  assert.ok(clash.errors.some((e) => e.code === 'entity' && /personal.*abacare/.test(e.message)), JSON.stringify(clash.errors));
  await assert.rejects(voiceStage(ctxFor(f, {}, { brand: entityBrand })), /entity.*personal.*abacare/);
  const excepted = structuredClone(f.spec);
  excepted.voice.entityException = { reason: 'Owner approved cross-entity use', approvedBy: 'Fixture Owner' };
  assert.deepEqual(lintSpec(excepted, entityBrand, { adSchema, brandSchema, specDir: f.dir }).errors.filter((e) => e.code === 'entity'), []);
  const ctx = ctxFor({ ...f, spec: excepted }, {}, { brand: entityBrand });
  await voiceStage(ctx);
  const note = ctx.ledger.entries.find((e) => e.stage === 'voice').note;
  assert.match(note, /entity personal/);
  assert.match(note, /exception.*Owner approved cross-entity use.*Fixture Owner/);
  const same = fixture();
  const sameCtx = ctxFor(same, {}, { brand: { ...brand, entity: 'personal' } });
  await voiceStage(sameCtx);
  assert.match(sameCtx.ledger.entries[0].note, /entity personal/);
});

test('entity: a missing brand entity or a missing record entity is a refusal in lint, voice and assets, unless an exception is recorded', async () => {
  const f = fixture();
  const { entity: _gone, ...noBrandEntity } = brand;
  const entityErrors = (b, spec = f.spec, dir = f.dir) => lintSpec(spec, b, { adSchema, brandSchema, specDir: dir }).errors.filter((e) => e.code === 'entity');
  assert.deepEqual(entityErrors(brand), [], 'both present and equal');
  const noBrand = entityErrors(noBrandEntity);
  assert.equal(noBrand.length, 1);
  assert.match(noBrand[0].message, /brand\.entity is missing/);
  await assert.rejects(voiceStage(ctxFor(f, {}, { brand: noBrandEntity })), /brand\.entity is missing/);
  const noRecord = fixture({ mutate: (m) => { const { entity, ...rest } = m; return rest; } });
  const missingRecord = entityErrors(brand, noRecord.spec, noRecord.dir);
  assert.equal(missingRecord.length, 1);
  assert.match(missingRecord[0].message, /manifest has no entity/);
  await assert.rejects(voiceStage(ctxFor(noRecord)), /manifest has no entity/);
  const excepted = structuredClone(f.spec);
  excepted.voice.entityException = { reason: 'Owner approved cross-entity use', approvedBy: 'Fixture Owner' };
  assert.deepEqual(entityErrors(noBrandEntity, excepted), [], 'a recorded exception covers a missing brand entity');
  await voiceStage(ctxFor({ ...f, spec: excepted }, {}, { brand: noBrandEntity }));
  const exceptedNoRecord = structuredClone(noRecord.spec);
  exceptedNoRecord.voice.entityException = excepted.voice.entityException;
  assert.deepEqual(entityErrors(brand, exceptedNoRecord, noRecord.dir), []);
  // the schema does not require brand.entity globally: a brand without it still validates, and a film with no import is not touched
  assert.deepEqual(validate(brandSchema, noBrandEntity), []);
  const eleven = { ...f.spec, voice: { provider: 'elevenlabs', voiceId: 'v', model: 'eleven_v4', settings: { apply_text_normalization: 'on' } } };
  assert.deepEqual(entityErrors(noBrandEntity, eleven), []);
});

test('entity: an imported still receipt with no entity, or a brand with none, is refused by lint and the assets stage', async () => {
  const f = fixture();
  const still = png(3);
  writeFileSync(join(f.dir, 'n.png'), still);
  const withReceipt = (receiptEntity) => {
    const s = structuredClone(f.spec);
    s.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'import', file: 'n.png', sha256: sha(still), source: 'runware', aiGenerated: true, prompt: 'an abstract field of soft light', receipt: { provider: 'runware', requestId: 'r', outputSha256: sha(still), ...(receiptEntity ? { entity: receiptEntity } : {}) } } });
    return s;
  };
  const { entity: _gone, ...noBrandEntity } = brand;
  const stillErrors = (b, s) => lintSpec(s, b, { adSchema, brandSchema, specDir: f.dir }).errors.filter((e) => e.code === 'entity' && e.where === 'main/B3');
  assert.deepEqual(stillErrors(brand, withReceipt('personal')), []);
  assert.match(stillErrors(brand, withReceipt(undefined))[0].message, /receipt has no entity/);
  assert.match(stillErrors(noBrandEntity, withReceipt('personal'))[0].message, /brand\.entity is missing/);
  await assert.rejects(assetsStage({ ...ctxFor({ dir: f.dir, spec: withReceipt(undefined) }), providers: {} }), /receipt has no entity/);
  await assert.rejects(assetsStage({ ...ctxFor({ dir: f.dir, spec: withReceipt('personal') }, {}, { brand: noBrandEntity }), providers: {} }), /brand\.entity is missing/);
  const excepted = withReceipt(undefined);
  excepted.beats[2].broll.entityException = { reason: 'Owner approved cross-entity use', approvedBy: 'Fixture Owner' };
  assert.deepEqual(stillErrors(brand, excepted), []);
});

test('b-roll receipt entity follows the same rule', () => {
  const f = fixture();
  const still = png(2);
  writeFileSync(join(f.dir, 'e.png'), still);
  const s = structuredClone(f.spec);
  s.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'import', file: 'e.png', sha256: sha(still), source: 'runware', aiGenerated: true, prompt: 'an abstract field of soft light', receipt: { provider: 'runware', requestId: 'r', outputSha256: sha(still), entity: 'mahumtech' } } });
  const entityErrors = (b) => lintSpec(s, b, { adSchema, brandSchema, specDir: f.dir }).errors.filter((e) => e.code === 'entity' && e.where === 'main/B3');
  assert.deepEqual(entityErrors({ ...brand, entity: 'mahumtech' }), []);
  assert.ok(entityErrors({ ...brand, entity: 'abacare' }).length > 0);
  s.beats[2].broll.entityException = { reason: 'Owner approved cross-entity use', approvedBy: 'Fixture Owner' };
  assert.deepEqual(entityErrors({ ...brand, entity: 'abacare' }), []);
});

test('imported rows stay zero-cost but record what was paid elsewhere', async () => {
  const f = fixture();
  const ctx = ctxFor(f);
  await voiceStage(ctx);
  const rows = ctx.ledger.entries.filter((e) => e.stage === 'voice');
  assert.deepEqual(rows[0].paidElsewhere, { usdMicros: 1234, estimated: false });
  assert.ok(rows.every((r) => r.units === 0 && r.cached));
  const s = ctx.ledger.summary();
  assert.deepEqual(s.paidElsewhere, { usdMicros: 2468, estimated: false, unknownRows: 0 });
  assert.equal(s.byProvider.assemblyai.units, 0);
  const none = fixture({ mutate: setLines((l) => ({ ...l, receipt: { ...l.receipt, usdMicros: null, estimated: true } })) });
  const c2 = ctxFor(none);
  await voiceStage(c2);
  assert.deepEqual(c2.ledger.summary().paidElsewhere, { usdMicros: 0, estimated: true, unknownRows: 2 });
});

test('an unpriced provider is a lint error except the injected local hook', () => {
  const local = planCost({ ...fixture().spec, voice: { provider: 'local', voiceId: 'v', model: 'm' } }, brand);
  assert.deepEqual(local.unknownProviders, ['local']);
  assert.deepEqual(costErrors(local), []);
  const other = { ...local, unknownProviders: ['mystery'], unknown: ['voice provider mystery has no price table'] };
  assert.equal(costErrors(other)[0].code, 'cost-unknown');
  assert.deepEqual(costErrors(planCost(fixture().spec, brand)), []);
});

test('b-roll import from a synthetic source needs a receipt that names that source and the same hash', () => {
  const f = fixture();
  const still = png(3);
  writeFileSync(join(f.dir, 'r.png'), still);
  const mk = (receipt) => { const s = structuredClone(f.spec); s.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'import', file: 'r.png', sha256: sha(still), source: 'runware', aiGenerated: true, prompt: 'an abstract field of soft light', ...(receipt ? { receipt } : {}) } }); return s; };
  const errs = (s) => lint(s, f.dir).errors.filter((e) => e.code === 'broll-import').map((e) => e.message).join('|');
  assert.equal(errs(mk({ provider: 'runware', requestId: 'r', outputSha256: sha(still) })), '');
  assert.match(errs(mk({ provider: 'azure', requestId: 'r', outputSha256: sha(still) })), /receipt\.provider/);
  assert.match(errs(mk({ provider: 'runware', requestId: 'r' })), /outputSha256/);
  assert.match(errs(mk({ provider: 'runware', outputSha256: sha(still) })), /requestId/);
});

test('the label and AI-voice disclosure need a closing card, so a cut must end on one', () => {
  const f = fixture();
  assert.equal(codes(lint(f.spec, f.dir)).includes('disclosure-card'), false);
  const bad = structuredClone(f.spec);
  bad.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'openai-image', prompt: 'an abstract field of soft light' } });
  assert.ok(codes(lint(bad, f.dir)).includes('disclosure-card'), 'voice.disclosure is set');
  const rec = fixture({ source: 'recording', mutate: (m) => ({ ...m, recordedBy: 'Fixture Narrator' }) });
  const noDisc = structuredClone(rec.spec);
  noDisc.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'openai-image', prompt: 'an abstract field of soft light' } });
  assert.equal(codes(lint(noDisc, rec.dir)).includes('disclosure-card'), false);
  assert.ok(lintSpec(noDisc, { ...brand, disclosure: { required: true } }, { adSchema, brandSchema, specDir: rec.dir }).errors.some((e) => e.code === 'disclosure-card'), 'brand.disclosure.required');
});

test('assets pre-flight reads imported stills before any paid call, and keeps them inside the spec folder or workspace', async () => {
  const f = fixture();
  const still = png(4);
  writeFileSync(join(f.dir, 'p.png'), still);
  const spec = structuredClone(f.spec);
  spec.beats[0].sfx = [{ cue: 'start', prompt: 'a soft click sound' }];
  spec.beats.push({ id: 'B3', kind: 'broll', broll: { provider: 'import', file: 'p.png', sha256: sha('different'), source: 'licensed', aiGenerated: false, prompt: 'a licensed photograph of a desk' } });
  let paid = 0;
  const ctx = { ...ctxFor({ dir: f.dir, spec }), providers: { elevenCli: {}, elevenlabs: { soundEffect: async () => { paid += 1; return { receipt: {} }; } } } };
  await assert.rejects(assetsStage(ctx), /changed since its sha256/);
  assert.equal(paid, 0);
  const outside = join(root, `outside-${counter}.png`);
  writeFileSync(outside, still);
  spec.beats[2].broll = { provider: 'import', file: `../../outside-${counter}.png`, sha256: sha(still), source: 'licensed', aiGenerated: false, prompt: 'a licensed photograph of a desk' };
  assert.ok(lint(spec, join(f.dir, 'sub')).errors.some((e) => e.code === 'broll-file' && /outside/.test(e.message)), 'lint');
  mkdirSync(join(f.dir, 'sub'), { recursive: true });
  const ctx2 = { ...ctxFor({ dir: f.dir, spec }, {}, { specDir: join(f.dir, 'sub'), workspace: join(f.dir, 'sub') }), providers: {} };
  await assert.rejects(assetsStage(ctx2), /outside/);
});

test('a manifest whose lines are not an array is a lint error; a recording needs recordedBy and no provider receipt', async () => {
  const bad = fixture({ mutate: (m) => ({ ...m, lines: 'nope' }) });
  assert.ok(lint(bad.spec, bad.dir).errors.some((e) => e.code === 'voice-import' && /lines/.test(e.message)));
  await assert.rejects(voiceStage(ctxFor(bad)), /lines/);
  const rec = fixture({ source: 'recording' });
  assert.ok(lint(rec.spec, rec.dir).errors.some((e) => /recordedBy/.test(e.message)));
  await assert.rejects(voiceStage(ctxFor(rec)), /recordedBy/);
  const ok = fixture({ source: 'recording', mutate: (m) => ({ ...m, recordedBy: 'Fixture Narrator' }) });
  assert.equal(lint(ok.spec, ok.dir).errors.some((e) => /recordedBy/.test(e.message)), false);
  await voiceStage(ctxFor(ok));
  const withProvider = fixture({ source: 'recording', mutate: (m) => ({ ...m, recordedBy: 'Fixture Narrator', lines: m.lines.map((l) => ({ ...l, receipt: { provider: 'deepgram' } })) }) });
  await assert.rejects(voiceStage(ctxFor(withProvider)), /recording.*provider/);
});

test('audio reached through a symlink out of the manifest folder is refused', async (t) => {
  const f = fixture();
  const outside = join(f.dir, 'elsewhere.wav');
  writeFileSync(outside, 'x');
  try { symlinkSync(outside, join(f.dir, 'narration', 'link.wav')); } catch { t.skip('symlinks not available here'); return; }
  const m = JSON.parse(readFileSync(f.manifestPath, 'utf8'));
  m.lines[0] = { ...m.lines[0], file: 'link.wav', sha256: sha('x'), receipt: { ...m.lines[0].receipt, outputSha256: sha('x') } };
  writeFileSync(f.manifestPath, JSON.stringify(m));
  await assert.rejects(voiceStage(ctxFor(f)), /main\/B1: audio file link.wav lies outside/);
});
