// Stage 2: voice. One file per narrated beat; ElevenLabs (governed ledger, request stitching), OpenAI
// OpenAI speech (instructions) or an injected local voice (Local AI is off: the default refuses). Cached by
// (text, voice, model, settings, neighbors), so an unchanged line never costs twice. A beat's `voiceTake` (1, 2, …) asks
// for a fresh take of that one line (a new key and ledger revision) after a listen or review rejects the delivery.
import { copyFileSync, existsSync, mkdirSync, realpathSync } from 'node:fs';
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { recordStage } from '../context.mjs';
import { checkStage, stageKey, writeStage } from '../cache.mjs';
import { NARRATION_IMPORT_SCHEMA, importLineFor, importPolicyProblems, normalizeCuts } from '../lint.mjs';
import { estimateTtsCredits, realtimeUsdFromUsage } from '../prices.mjs';
import { fileSha, hashOf, localAiOff, readJson, sha256, writeJson } from '../util.mjs';

const AUDIO_EXT = new Set(['.wav', '.mp3', '.m4a']);

/** The cost-ledger provider a voice line is recorded under, or null when the voice has none (a retired local voice). */
export function ledgerProvider(v) {
  if (v.provider === 'import') return v.source;
  return v.provider === 'elevenlabs' || v.provider === 'openai' ? v.provider : null;
}

/**
 * Read and verify an import manifest against the spec narration. Nothing is called and nothing is paid. Every narrated beat
 * needs a line whose text, audio file and (for AI sources) provider receipt still agree; the first disagreement throws one
 * message that names the beat. Returns Map<'cut/beat', {entry, abs, ext, sha256}>.
 */
export function verifyNarrationImport(ctx, cuts = normalizeCuts(ctx.spec)) {
  const v = ctx.spec.voice;
  if (v.provider !== 'import') return new Map();
  if (!v.manifest || isAbsolute(v.manifest)) throw new Error('import narration: voice.manifest must be a path relative to the spec folder');
  const manifestPath = resolve(ctx.specDir, v.manifest);
  if (!existsSync(manifestPath)) throw new Error(`import narration: manifest not found: ${manifestPath}`);
  const manifest = readJson(manifestPath);
  if (manifest.schema !== NARRATION_IMPORT_SCHEMA) throw new Error(`import narration: ${manifestPath} is not a ${NARRATION_IMPORT_SCHEMA} manifest`);
  if (manifest.source !== v.source) throw new Error(`import narration: manifest source "${manifest.source}" is not the declared voice.source "${v.source}"`);
  if (!Array.isArray(manifest.lines)) throw new Error('import narration: manifest lines must be an array');
  const policy = importPolicyProblems(ctx.spec, manifest, ctx.brand, ctx.now ?? Date.now());
  if (policy.length) throw new Error(`import narration: ${policy[0].message}`);
  const root = realpathSync(dirname(manifestPath));
  const out = new Map();
  for (const cut of cuts) for (const beat of cut.beats) {
    if (!beat.narration) continue;
    const where = `${cut.id}/${beat.id}`;
    const fail = (why) => { throw new Error(`import narration ${where}: ${why}`); };
    const entry = importLineFor(manifest, cut.id, beat.id);
    if (!entry) fail(`the manifest has no line for this beat (${manifestPath})`);
    if (entry.textSha256 !== sha256(beat.narration)) fail('the narration text changed since this audio was made; make the line again');
    if (typeof entry.file !== 'string' || !entry.file || isAbsolute(entry.file)) fail('the line file must be a relative path inside the manifest folder');
    const abs = resolve(root, entry.file);
    if (!existsSync(abs)) fail(`audio file missing: ${entry.file}`);
    const real = realpathSync(abs);
    if (real !== root && !real.startsWith(root + sep)) fail(`audio file ${entry.file} lies outside the manifest folder`);
    const ext = extname(real).toLowerCase();
    if (!AUDIO_EXT.has(ext)) fail(`audio file ${entry.file} must be wav, mp3 or m4a`);
    const actual = fileSha(real);
    if (!/^[0-9a-f]{64}$/.test(entry.sha256 || '') || actual !== entry.sha256) fail('the audio changed since it was recorded in the manifest (sha256 differs)');
    if (v.source !== 'recording') {
      const r = entry.receipt;
      if (!r || typeof r !== 'object') fail('an AI-generated line needs a provider receipt');
      if (r.provider !== v.source) fail(`receipt provider "${r.provider}" is not the declared source "${v.source}"`);
      if (!String(r.requestId || '').trim()) fail('receipt has no provider request id');
      if (r.outputSha256 !== entry.sha256) fail('receipt outputSha256 differs from the audio sha256: the audio is not what the provider returned');
      if (!(r.usdMicros === null || Number.isInteger(r.usdMicros))) fail('receipt usdMicros must be an integer or null');
      if (r.voice !== v.voiceId) fail(`receipt voice "${r.voice}" is not the declared voice.voiceId "${v.voiceId}"`);
      if (r.model !== v.model) fail(`receipt model "${r.model}" is not the declared voice.model "${v.model}"`);
    }
    out.set(where, { entry, abs: real, ext: ext.slice(1), sha256: actual, manifestEntity: manifest.entity });
  }
  return out;
}

export function lineKey(spec, text, prev, next, take = 0, audioSha256 = null) {
  const v = spec.voice;
  return hashOf({
    ...(take ? { take } : {}),
    ...(v.provider === 'import' ? { source: v.source, audioSha256 } : {}),
    provider: v.provider, voiceId: v.voiceId, model: v.model, settings: v.settings || null, instructions: v.instructions || null,
    dictionaries: v.pronunciationDictionaries || null, stitching: !!v.stitching, text, prev: v.stitching ? prev || null : null, next: v.stitching ? next || null : null,
  });
}

export const lineExt = (provider) => (provider === 'local' || provider === 'openai' ? 'wav' : 'mp3');

async function renderLine(ctx, { text, prev, next, out, key, take }, openaiPlan) {
  const v = ctx.spec.voice;
  const P = ctx.providers;
  if (v.provider === 'elevenlabs') {
    const credits = estimateTtsCredits(text, v.model);
    ctx.ledger.check('elevenlabs', credits, `voice line "${text.slice(0, 40)}"`);
    const eleven = P.elevenlabs || (await import('../providers/elevenlabs.mjs'));
    const cli = P.elevenCli || eleven.resolveCli(ctx.brand);
    const res = await eleven.speech(cli, {
      text, output: out, voiceId: v.voiceId, model: v.model, settings: v.settings, maxCredits: credits,
      workspace: ctx.workspaceId, revision: take ? `mvg-voice-v1-take${take}` : 'mvg-voice-v1', previousText: v.stitching ? prev : undefined, nextText: v.stitching ? next : undefined,
      dictionaries: v.pronunciationDictionaries, run: P.runCli,
    });
    const reused = !!res.receipt?.reused;
    ctx.ledger.charge({ stage: 'voice', provider: 'elevenlabs', service: 'tts', units: res.receipt?.actual_credits ?? credits, estimated: res.receipt?.actual_credits == null, cached: reused, ref: key.slice(0, 12), note: `request ${res.receipt?.request_id || '?'}` });
    return { receipt: res.receipt };
  }
  if (v.provider === 'openai') {
    const reservation = openaiPlan?.byLine.get(key);
    if (!reservation) throw new Error('OpenAI narration inputs changed after preflight. Run voice again.');
    const usd = reservation.usdMicros / 1e6;
    ctx.ledger.check('openai', usd, 'OpenAI speech');
    const openai = P.openai || (await import('../providers/openai.mjs'));
    const payment = openaiPlan.wallet.reserve(out, key, reservation.usdMicros);
    let res;
    try {
      res = await openai.speech({ text, voice: v.voiceId, instructions: v.instructions, model: openaiPlan.model,
        credential: openaiPlan.key, maxOutputTokens: reservation.maxOutputTokens });
    } catch (error) {
      if (error.definitelyUnsubmitted === true) payment.cancelUnsubmitted();
      throw error;
    }
    // Charge what the response's usage says it cost; fall back to the estimate only when usage is missing, and say so.
    const billed = realtimeUsdFromUsage(openaiPlan.model, res.usage, openaiPlan.rate);
    payment.stageAndPublish(Math.ceil((billed ?? 0) * 1e6), res.bytes);
    ctx.ledger.charge({ stage: 'voice', provider: 'openai', service: 'speech', units: billed ?? usd, estimated: billed == null, ref: key.slice(0, 12), note: res.usage ? `usage ${JSON.stringify(res.usage.output_token_details || {})}` : 'no usage returned' });
    return { receipt: { provider: 'openai', model: openaiPlan.model, voice: v.voiceId, aiGenerated: true,
      usage: res.usage ?? null, billedUsd: billed, rateEvidence: openaiPlan.rateEvidence,
      fundingObservedAt: openaiPlan.funding.observedAt, reservedUsd: usd } };
  }
  if (v.provider === 'local') {
    const local = P.localVoice || localAiOff('local voice');
    await local({ speaker: v.voiceId, instruction: v.instructions || '', text, out });
    return { receipt: { provider: 'local', speaker: v.voiceId } };
  }
  throw new Error(`unsupported voice provider ${v.provider}`);
}

function planCut(ctx, cut, imports) {
  const narrated = cut.beats.filter(b => b.narration);
  return narrated.map((b, i) => ({
      beat: b.id, text: b.narration, prev: narrated[i - 1]?.narration, next: narrated[i + 1]?.narration, take: Number(b.voiceTake || 0),
      imported: imports.get(`${cut.id}/${b.id}`) || null,
    })).map(l => ({ ...l, key: lineKey(ctx.spec, l.text, l.prev, l.next, l.take, l.imported?.sha256 ?? null), ext: l.imported?.ext }));
}

/** Copy one verified imported line into the job. No provider is called; the ledger row is zero-cost, cached and labelled with the true source. */
function importLine(ctx, l, out) {
  const v = ctx.spec.voice;
  if (!existsSync(out) || fileSha(out) !== l.imported.sha256) copyFileSync(l.imported.abs, out);
  if (fileSha(out) !== l.imported.sha256) throw new Error(`import narration ${l.beat}: the copied audio does not match its manifest hash`);
  const r = l.imported.entry.receipt || null;
  const exception = v.entityException ? `; entity exception: ${v.entityException.reason} (approved by ${v.entityException.approvedBy})` : '';
  ctx.ledger.charge({ stage: 'voice', provider: v.source, service: 'tts', units: 0, cached: true, ref: l.key.slice(0, 12),
    ...(r ? { paidElsewhere: { usdMicros: r.usdMicros ?? null, estimated: r.estimated ?? null } } : {}),
    note: `imported narration (${v.source}); entity ${l.imported.manifestEntity || 'unstated'}; paid outside this run (settled by the governed script's own ledger)${r?.requestId ? `, request ${r.requestId}` : ''}${exception}` });
  return { provider: v.source, source: v.source, imported: true, paidElsewhere: true, requestId: r?.requestId ?? null, outputSha256: r?.outputSha256 ?? null, usdMicros: r?.usdMicros ?? null, estimated: r?.estimated ?? null, aiGenerated: v.source !== 'recording' };
}

async function planOpenAI(ctx, plans, linePath) {
  if (ctx.flags.dryRun || ctx.spec.voice.provider !== 'openai') return null;
  const pending = new Map(plans.flatMap(({ plan }) => plan).filter(l => !existsSync(linePath(l.key))).map(l => [l.key, l.text]));
  if (!pending.size) return null;
  const source = [new URL('../../../../scripts/narration-preflight.mjs', import.meta.url),
    new URL('../../../../_shared/tools/narration-preflight.mjs', import.meta.url)].find(url => existsSync(url));
  if (!source) throw new Error('Media Studio narration preflight missing. Sync the runtime kit before generating voice.');
  const { preflightMarketingOpenAI, recoverMarketingAudio } = await import(source.href);
  for (const key of pending.keys()) {
    const output = linePath(key);
    const recovered = recoverMarketingAudio(output, key, ctx.providers.narrationPreflight);
    // A take settled before an interruption still counts against the workspace budget.
    if (recovered) ctx.ledger.charge({ stage: 'voice', provider: 'openai', service: 'speech', units: recovered.billedMicros / 1e6,
      estimated: false, ref: key.slice(0, 12), note: 'recovered settled take' });
    if (recovered || existsSync(output)) pending.delete(key);
  }
  if (!pending.size) return null;
  const { narrationEntity: entity, narrationFunding } = ctx.flags;
  if (!entity || !narrationFunding) throw new Error('New OpenAI narration requires --narration-entity and --narration-funding with current dashboard evidence');
  const voice = ctx.spec.voice;
  const quote = await preflightMarketingOpenAI({ entity, model: voice.model, voice: voice.voiceId, lines: [...pending.values()],
    instructions: voice.instructions, snapshot: readJson(narrationFunding) }, { ...ctx.providers.narrationPreflight, recoverInterrupted: true });
  ctx.ledger.check('openai', quote.totalMicros / 1e6, 'planned OpenAI narration');
  return { ...quote, byLine: new Map([...pending.keys()].map((key, i) => [key, quote.reservations[i]])) };
}

export async function voiceStage(ctx) {
  const results = {};
  const cuts = normalizeCuts(ctx.spec);
  const imports = verifyNarrationImport(ctx, cuts);
  const ext = lineExt(ctx.spec.voice.provider);
  const lineFile = (key, e = ext) => join('voice', 'lines', `${key.slice(0, 16)}.${e}`);
  const plans = cuts.map(cut => ({ cut, plan: planCut(ctx, cut, imports) }));
  const openaiPlan = await planOpenAI(ctx, plans, key => join(ctx.jobDir, lineFile(key)));
  for (const { cut, plan } of plans) {
    const stageK = stageKey('voice', { lines: plan.map((l) => l.key) });
    const cached = checkStage(ctx.jobDir, 'voice', cut.id, stageK);
    if (cached.hit && !ctx.flags.force) { ctx.log(`voice/${cut.id}: cached`); results[cut.id] = cached.manifest; continue; }
    const lines = [];
    for (const l of plan) {
      const rel = lineFile(l.key, l.ext);
      const out = join(ctx.jobDir, rel);
      mkdirSync(join(ctx.jobDir, 'voice', 'lines'), { recursive: true });
      let receipt = null;
      if (l.imported) {
        if (ctx.flags.dryRun) { ctx.log(`voice/${cut.id}/${l.beat}: would import ${l.imported.entry.file}`); continue; }
        ctx.log(`voice/${cut.id}/${l.beat}: importing (${ctx.spec.voice.source})`);
        receipt = importLine(ctx, l, out);
      } else if (existsSync(out)) {
        const provider = ledgerProvider(ctx.spec.voice);
        if (provider) ctx.ledger.charge({ stage: 'voice', provider, service: 'tts', units: 0, cached: true, ref: l.key.slice(0, 12), note: 'line file already present' });
      } else if (ctx.flags.dryRun) {
        ctx.log(`voice/${cut.id}/${l.beat}: would render ${l.text.length} chars`);
        continue;
      } else {
        ctx.log(`voice/${cut.id}/${l.beat}: rendering (${ctx.spec.voice.provider})`);
        receipt = (await renderLine(ctx, { ...l, out }, openaiPlan)).receipt;
      }
      lines.push({ beatId: l.beat, text: l.text, file: rel.replace(/\\/g, '/'), key: l.key, sha256: existsSync(out) ? fileSha(out) : null, receipt });
    }
    if (ctx.flags.dryRun) { results[cut.id] = { dryRun: true, lines: plan.map((l) => ({ beatId: l.beat, key: l.key })) }; continue; }
    const manifestPath = join(ctx.jobDir, 'voice', `${cut.id}.lines.json`);
    writeJson(manifestPath, { cut: cut.id, voice: { provider: ctx.spec.voice.provider, voiceId: ctx.spec.voice.voiceId, model: ctx.spec.voice.model, name: ctx.spec.voice.name || null, aiGenerated: ctx.spec.voice.provider === 'import' ? ctx.spec.voice.source !== 'recording' : true, ...(ctx.spec.voice.provider === 'import' ? { source: ctx.spec.voice.source, manifest: ctx.spec.voice.manifest } : {}) }, lines });
    results[cut.id] = writeStage(ctx.jobDir, 'voice', cut.id, stageK, { lines, outputs: [relative(ctx.jobDir, manifestPath), ...lines.map((l) => l.file)] });
  }
  recordStage(ctx, 'voice', ctx.flags.dryRun ? 'dry-run' : 'done', { cost: ctx.ledger.summary() });
  return results;
}
