#!/usr/bin/env node
// Read-only by default. Execute only a pinned, funded AssemblyAI quote.
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { homedir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const urls = {
  assemblyai: 'https://www.assemblyai.com/docs/getting-started/models.md',
  deepgram: 'https://deepgram.com/product/text-to-speech',
  openai: 'https://developers.openai.com/api/docs/models/gpt-realtime-2.1-mini.md',
};
const models = { assemblyai: 'assemblyai-tts-1', deepgram: 'flux-haley-en', openai: 'gpt-realtime-2.1-mini' };
const keys = { assemblyai: 'ASSEMBLYAI_API_KEY', deepgram: 'DEEPGRAM_API_KEY', openai: 'OPENAI_API_KEY' };
const hosts = { us: 'https://tts.us.assemblyai.com', eu: 'https://tts.eu.assemblyai.com' };
const methods = { assemblyai: 'grouped-http', deepgram: 'native-complete-text-batch', openai: 'realtime-per-request' };
const realtimeModels = new Set([models.openai, 'gpt-realtime-2.1']);
// Built-in Realtime voices, per the official audio.output.voice contract.
const realtimeVoices = new Set(['alloy', 'ash', 'ballad', 'cedar', 'coral', 'echo', 'marin', 'sage', 'shimmer', 'verse']);
const segmenter = new Intl.Segmenter(undefined, { granularity: 'word' });
const require = createRequire(import.meta.url);
const deepgramPolicy = JSON.parse(readFileSync(new URL('./narration-deepgram-policy.json', import.meta.url), 'utf8'));
const limits = { assemblyai: 5000, deepgram: deepgramPolicy.maxCharacters, openai: 1500 };
const usd = n => Math.ceil(n * 1e6) / 1e6;
const count = t => [...t].length;
const assemblyNanos = (characters, rate) => characters * Math.round(rate.usdPerMillionCharacters * 1000);
const nanosToUsd = value => Math.ceil(value / 1000) / 1e6;
const hash = x => createHash('sha256').update(x).digest('hex');
const canonical = x => JSON.stringify(x);
const fileJSON = file => JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const save = (file, value, flag = 'w') => writeFileSync(file, JSON.stringify(value, null, 2) + '\n', { flag, flush: true });
const fixedGap = 24 * 60 * 60 * 1000;
const defaultSpendDir = () => process.platform === 'win32' && process.env.LOCALAPPDATA ?
  join(process.env.LOCALAPPDATA, 'AgentHub', 'media-studio', '_shared', 'spend') :
  join(homedir(), '.local', 'share', 'AgentHub', 'media-studio', 'spend');
const submissionSchema = 'CREATE TABLE IF NOT EXISTS submissions (take_id TEXT PRIMARY KEY, evidence TEXT NOT NULL) STRICT;';
const marketingSchema = `CREATE TABLE IF NOT EXISTS voice_spend (
  request_id TEXT PRIMARY KEY, account TEXT NOT NULL, entity TEXT NOT NULL, micros INTEGER NOT NULL,
  completed_at INTEGER, audio_sha256 TEXT
) STRICT; CREATE INDEX IF NOT EXISTS voice_spend_account ON voice_spend(account, completed_at);`;
function migrateMarketingWallet(db) {
  db.exec(marketingSchema);
  if (!db.prepare('PRAGMA table_info(voice_spend)').all().some(column => column.name === 'audio_sha256'))
    db.exec('ALTER TABLE voice_spend ADD COLUMN audio_sha256 TEXT');
}
const marketingRequestId = (output, lineKey) => hash(canonical([realpathSync(dirname(output)), basename(output), lineKey]));

function speechWordEstimate(text) {
  const words = [...segmenter.segment(text)].filter(segment => segment.isWordLike).length;
  const unspaced = text.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]/gu);
  return Math.max(1, words, Math.ceil((unspaced?.length ?? 0) / 2));
}

export function resolveOpenAIKey({ env = process.env, platform = process.platform, run = spawnSync } = {}) {
  if (platform === 'win32' && !env.NODE_TEST_CONTEXT) {
    const result = run('reg', ['query', 'HKCU\\Environment', '/v', keys.openai],
      { encoding: 'utf8', windowsHide: true, timeout: 5000 });
    const match = result.status === 0 && result.stdout.match(/OPENAI_API_KEY\s+REG_(?:EXPAND_)?SZ\s+(.+)/);
    if (match?.[1].trim()) return match[1].trim();
  }
  return env.OPENAI_API_KEY || null;
}

function deepgramBudget() {
  const script = fileURLToPath(new URL('./governed_deepgram.py', import.meta.url));
  const result = spawnSync(process.platform === 'win32' ? 'python' : 'python3', ['-B', script, '--budget-status'],
    { encoding: 'utf8', windowsHide: true, timeout: 5000 });
  if (result.status !== 0) return null;
  try { return JSON.parse(result.stdout).availableUsdMicros; } catch { return null; }
}

export function parseRate(provider, doc) {
  const num = value => value !== undefined && Number.isFinite(+value) && +value > 0 ? +value : null;
  if (provider === 'assemblyai') {
    const rate = num(doc.match(/\|\s*AssemblyAI-TTS-1\s*\|\s*\\?\$([\d.]+) per 1M input characters\s*\|/i)?.[1]);
    return rate === null ? null : { usdPerMillionCharacters: rate };
  }
  if (provider === 'deepgram') {
    const rate = num(doc.match(/Flux TTS is \$([\d.]+) per 1,000 characters on pay-as-you-go/)?.[1]);
    return rate === null ? null : { usdPerMillionCharacters: rate * 1000 };
  }
  const text = doc.match(/### Text tokens([\s\S]*?)### Audio tokens/)?.[1] || '';
  const audio = doc.match(/### Audio tokens([\s\S]*?)### Image tokens/)?.[1] || '';
  const input = num(text.match(/\| Input \| \$([\d.]+) \| 1M tokens \|/)?.[1]);
  const output = num(audio.match(/\| Output \| \$([\d.]+) \| 1M tokens \|/)?.[1]);
  return input === null || output === null ? null : { usdPerMillionInputTextTokens: input, usdPerMillionOutputAudioTokens: output };
}

function marketingRealtimeRate(doc) {
  const [text, audio] = [doc.match(/### Text tokens([\s\S]*?)### Audio tokens/)?.[1],
    doc.match(/### Audio tokens([\s\S]*?)### Image tokens/)?.[1]];
  const row = (section, label) => Number(section?.match(new RegExp(`\\| ${label} \\| \\$([\\d.]+) \\| 1M tokens \\|`))?.[1]);
  const rate = { in: row(audio, 'Input'), out: row(audio, 'Output'), textIn: row(text, 'Input'),
    textOut: row(text, 'Output'), cachedIn: row(audio, 'Cached input'), cachedTextIn: row(text, 'Cached input') };
  return Object.values(rate).every(n => Number.isFinite(n) && n >= 0) ? rate : null;
}

// Marketing keeps beat boundaries for its timing compositor and uses the model and credential of the exact request.
export async function preflightMarketingOpenAI({ entity, model = models.openai, voice = 'marin', lines, instructions, snapshot },
  { now = Date.now(), fetcher = fetch, key = resolveOpenAIKey(),
    spendDir = defaultSpendDir(), recoverInterrupted = false } = {}) {
  if (!['abacare', 'mahumtech', 'personal'].includes(entity) || !realtimeModels.has(model) || !lines.length)
    throw new Error('OpenAI narration preflight requires an entity, a supported exact Realtime model, and lines');
  if (!realtimeVoices.has(voice)) throw new Error('OpenAI narration requires a supported built-in Realtime voice');
  const url = `https://developers.openai.com/api/docs/models/${model}.md`;
  const [doc, funding] = await Promise.all([
    response(fetcher, url).then(r => r.text()),
    account('openai', { entity }, snapshot, [], now, fetcher, key, model),
  ]);
  const rate = marketingRealtimeRate(doc);
  if (!rate || funding.access !== 'verified' || funding.balance !== 'dashboard-recorded')
    throw new Error('OpenAI narration needs current model rates, access, and fresh funding evidence for this credential and entity');
  const reservations = lines.map(text => {
    const maxOutputTokens = 18 * speechWordEstimate(text) + 256;
    if (maxOutputTokens > 4096) throw new Error('OpenAI narration beat exceeds the bounded output window. Split it at a natural break.');
    const inputCeiling = Buffer.byteLength(text) + Buffer.byteLength(instructions || '') + 256;
    return { maxOutputTokens, usdMicros: Math.ceil(inputCeiling * rate.textIn + maxOutputTokens * Math.max(rate.out, rate.textOut)) };
  });
  const totalMicros = reservations.reduce((sum, part) => sum + part.usdMicros, 0);
  const wallet = marketingWallet(spendDir, entity, funding, recoverInterrupted);
  const availableMicros = wallet.available();
  if (totalMicros > availableMicros) throw new Error('Insufficient available OpenAI balance for narration');
  return { key, model, rate, availableMicros, reservations, totalMicros, wallet,
    rateEvidence: { url, checkedAt: new Date(now).toISOString(), documentSha256: hash(doc) }, funding };
}

function marketingWallet(spendDir, entity, funding, recoverInterrupted) {
  const file = join(spendDir, 'openai-narration.sqlite3');
  const account = funding.credentialSha256;
  const observedAt = Date.parse(funding.observedAt);
  const budgetMicros = Math.floor(funding.availableUsd * 1e6);
  const spent = db => {
    const mismatch = db.prepare('SELECT 1 FROM voice_spend WHERE account = ? AND entity != ? LIMIT 1').get(account, entity);
    if (mismatch) throw new Error('OpenAI credential is already tied to a different billing entity');
    return db.prepare(`SELECT COALESCE(SUM(micros), 0) AS total FROM voice_spend
      WHERE account = ? AND (completed_at IS NULL OR completed_at >= ?)`).get(account, observedAt).total;
  };
  const available = () => {
    if (!existsSync(file)) return budgetMicros;
    return readMarketingWallet(spendDir, recoverInterrupted, db => Math.max(0, budgetMicros - spent(db)));
  };
  return {
    available,
    reserve: (output, lineKey, micros) => {
      mkdirSync(dirname(file), { recursive: true });
      const id = marketingRequestId(output, lineKey);
      withSqliteJournal(file, false, db => {
        migrateMarketingWallet(db);
        db.exec('BEGIN IMMEDIATE');
        if (db.prepare('SELECT 1 FROM voice_spend WHERE request_id = ?').get(id))
          throw new Error('Previously submitted OpenAI narration line requires reconciliation');
        if (spent(db) + micros > budgetMicros) throw new Error('Insufficient available OpenAI balance for narration');
        db.prepare('INSERT INTO voice_spend (request_id, account, entity, micros) VALUES (?, ?, ?, ?)')
          .run(id, account, entity, micros);
        db.exec('COMMIT');
      });
      return {
        stageAndPublish: (billedMicros, bytes) => {
          const staged = output + '.staged';
          save(staged + '.json', { requestId: id, billedMicros, audioSha256: hash(bytes) }, 'wx');
          writeFileSync(staged, bytes, { flag: 'wx', flush: true });
          recoverMarketingAudio(output, lineKey, { spendDir });
        },
        cancelUnsubmitted: () => withSqliteJournal(file, false, db => {
          db.prepare('DELETE FROM voice_spend WHERE request_id = ? AND completed_at IS NULL').run(id);
        }),
      };
    },
  };
}

function readMarketingWallet(spendDir, recoverInterrupted, work) {
  const file = join(spendDir, 'openai-narration.sqlite3');
  const read = () => withSqliteJournal(file, true, work);
  try { return read(); }
  catch (error) {
    const interrupted = error.cause?.errcode === 776 || (error.errcode === 1 && error.message === 'no such table: voice_spend');
    if (!recoverInterrupted || !interrupted) throw error;
    recoverLedgers(undefined, spendDir);
    return read();
  }
}

export function recoverMarketingAudio(output, lineKey, { spendDir = defaultSpendDir() } = {}) {
  const staged = output + '.staged';
  if (!existsSync(staged) || existsSync(output)) return false;
  const id = marketingRequestId(output, lineKey);
  const file = join(spendDir, 'openai-narration.sqlite3');
  if (!existsSync(file) || !existsSync(staged + '.json'))
    throw new Error('Staged OpenAI narration requires reconciliation before it can be reused');
  const receipt = fileJSON(staged + '.json');
  const actualHash = hash(readFileSync(staged));
  if (receipt.requestId !== id || receipt.audioSha256 !== actualHash ||
      !Number.isSafeInteger(receipt.billedMicros) || receipt.billedMicros < 0)
    throw new Error('Staged OpenAI narration requires reconciliation before it can be reused');
  const lookup = db => db.prepare('SELECT completed_at, audio_sha256 FROM voice_spend WHERE request_id = ?').get(id);
  const verify = row => {
    if (!row || (row.completed_at !== null && row.audio_sha256 !== actualHash))
      throw new Error('Staged OpenAI narration settlement does not match the saved audio');
  };
  withSqliteJournal(file, false, migrateMarketingWallet);
  verify(readMarketingWallet(spendDir, true, lookup));
  withSqliteJournal(file, false, db => {
    db.exec('BEGIN IMMEDIATE');
    verify(lookup(db));
    db.prepare(`UPDATE voice_spend SET micros = MAX(micros, ?), completed_at = ?, audio_sha256 = ?
      WHERE request_id = ? AND completed_at IS NULL`).run(receipt.billedMicros, Date.now(), actualHash, id);
    db.exec('COMMIT');
  });
  renameSync(staged, output);
  return { billedMicros: receipt.billedMicros };
}

function validate(script) {
  if (!['abacare', 'mahumtech', 'personal'].includes(script.entity))
    throw new Error('Name the entity: abacare, mahumtech or personal');
  if (script.provider !== undefined && !Object.hasOwn(models, script.provider))
    throw new Error('Use assemblyai, deepgram or openai for this preflight');
  if (!Array.isArray(script.turns) || !script.turns.length || script.turns.some(t =>
    typeof t.text !== 'string' || !t.text.trim() || /[\u0000\uD800-\uDFFF]/u.test(t.text) ||
    (t.speaker !== undefined && (typeof t.speaker !== 'string' || !t.speaker.trim())) ||
    (t.voices !== undefined && (t.voices === null || typeof t.voices !== 'object' || Array.isArray(t.voices) ||
      Object.entries(t.voices).some(([p, v]) => !Object.hasOwn(models, p) || typeof v !== 'string' || !v.trim())))))
    throw new Error('Provide non-empty turns with valid text, speaker and optional voice choices');
  if (!Object.hasOwn(hosts, script.region ?? 'us')) throw new Error('Use us or eu for the AssemblyAI data zone');
}

// Preserve internal whitespace and text. Prefer paragraph and sentence breaks, then whitespace,
// and split an oversized unbroken token only when the endpoint limit makes it unavoidable.
function chunks(text, limit) {
  const result = [];
  let remaining = [...text.trim()];
  while (remaining.length > limit) {
    const head = remaining.slice(0, limit).join('');
    const breaks = [...head.matchAll(/\n\n+|[.!?]["”']?\s+|\s+/g)]
      .map(m => ({ position: count(head.slice(0, m.index + m[0].length)), preferred: /[.!?\n]/.test(m[0]) }));
    const late = breaks.filter(b => b.position >= limit * 0.65);
    const cut = late.filter(b => b.preferred).at(-1)?.position ?? breaks.at(-1)?.position ?? limit;
    result.push(remaining.slice(0, cut).join(''));
    remaining = remaining.slice(cut);
  }
  return [...result, remaining.join('')];
}

export function makeBatches(script, provider) {
  validate(script);
  if (!Object.hasOwn(models, provider)) throw new Error('Unknown narration provider');
  const speakers = new Set(script.turns.map(t => t.speaker || 'narrator'));
  const defaults = { assemblyai: 'aai-jane', deepgram: models.deepgram, openai: 'marin' };
  const groups = [];
  for (const [index, turn] of script.turns.entries()) {
    const speaker = turn.speaker || 'narrator';
    const voice = turn.voices?.[provider] ?? (speakers.size === 1 && !script.explicitCast && !turn.voices ? defaults[provider] : null);
    if (!voice) return null;
    const text = turn.text.trim();
    const length = count(text);
    const previous = groups.at(-1);
    if (!turn.keepSeparate && previous && !previous.keepSeparate &&
      previous.speaker === speaker && previous.voice === voice) {
      const start = previous.length + 2;
      previous.text += '\n\n' + text;
      previous.length = start + length;
      previous.spans.push({ turn: index + 1, start, end: previous.length });
    } else groups.push({ text, length, speaker, voice, spans: [{ turn: index + 1, start: 0, end: length }],
      keepSeparate: !!turn.keepSeparate });
  }
  return groups.flatMap(({ text, speaker, voice, spans }) => {
    let offset = 0;
    return chunks(text, limits[provider]).flatMap(block => {
      const start = offset;
      offset += count(block);
      if (!block.trim()) return [];
      const turns = spans.filter(span => span.start < offset && span.end > start).map(span => span.turn);
      return [{ text: block, speaker, voice, turns }];
    });
  });
}

async function response(fetcher, url, options = {}) {
  const res = await fetcher(url, { redirect: 'error', signal: AbortSignal.timeout(15000), ...options });
  if (!res.ok) throw new Error('HTTP ' + res.status);
  return res;
}

// A private clone needs an explicit job-scoped approval and live provider consent.
export function eligibleAssemblyVoice(v, voice, script, now) {
  const common = v.status === 'active' && v.language === (script.language || 'english') &&
    v.ready_models?.includes(models.assemblyai);
  if (!common) return false;
  if (v.source === 'assemblyai' && v.visibility === 'public') return true;
  const approvedOwners = new Set(['sarosh-hussain', 'syeda-fatima-abidi']);
  const approval = Array.isArray(script.privateVoiceApprovals) && script.privateVoiceApprovals.find(a => a && a.voice === voice &&
    a.entity === script.entity && typeof a.ownerApproval === 'string' && a.ownerApproval.trim());
  return Boolean(approval && approvedOwners.has(voice) && ['abacare', 'personal'].includes(script.entity) &&
    v.slug === voice && v.source === 'customer_upload' && v.visibility === 'private' &&
    v.zone === (script.region ?? 'us') && v.consent?.attested === true &&
    Number.isFinite(Date.parse(v.consent.attested_at)) && Date.parse(v.consent.attested_at) <= now &&
    Number.isFinite(Date.parse(v.retention?.expires_at)) && Date.parse(v.retention.expires_at) > now);
}

async function account(provider, script, snapshot, voices, now, fetcher, key, model = models[provider]) {
  if (!key) return { access: 'missing-key', balance: 'unknown' };
  let access = 'unverified';
  let balanceEndpoint = null;
  try {
    if (provider === 'assemblyai') {
      const region = hosts[script.region ?? 'us'];
      const catalog = await Promise.all(voices.map(async voice =>
        (await response(fetcher, region + '/v1/voices/' + encodeURIComponent(voice),
          { headers: { Authorization: key } })).json()));
      access = catalog.length && catalog.every((v, i) => eligibleAssemblyVoice(v, voices[i], script, now))
        ? 'verified' : 'voice-ineligible';
    } else if (provider === 'openai') {
      await response(fetcher, 'https://api.openai.com/v1/models/' + model,
        { headers: { Authorization: 'Bearer ' + key } });
      access = voices.every(voice => realtimeVoices.has(voice)) ? 'verified' : 'voice-ineligible';
    } else {
      const r = await response(fetcher, 'https://api.deepgram.com/v1/projects', { headers: { Authorization: 'Token ' + key } });
      const data = await r.json();
      const projects = data.projects ?? [];
      const project = snapshot?.projectId ? projects.find(p => p.project_id === snapshot.projectId) :
        projects.length === 1 ? projects[0] : null;
      access = project ? 'verified' : 'unverified';
      if (project?.project_id) {
        try {
          const balances = await response(fetcher, 'https://api.deepgram.com/v1/projects/' +
            encodeURIComponent(project.project_id) + '/balances', { headers: { Authorization: 'Token ' + key } });
          const entries = (await balances.json()).balances;
          // This endpoint reports outstanding balances, which do not establish spendable TTS credit.
          balanceEndpoint = Array.isArray(entries) ? 'outstanding balances visible' : 'unexpected response';
        } catch {
          balanceEndpoint = 'unavailable to this credential';
        }
      }
    }
  } catch {
    access = 'unverified';
  }
  const evidence = balanceEndpoint ? { balanceEndpoint } : {};
  const at = Date.parse(snapshot?.observedAt);
  const fresh = Number.isFinite(at) && at <= now && now - at <= fixedGap;
  const sameKey = snapshot?.credentialSha256 === hash(key);
  if (snapshot?.entity !== script.entity || snapshot?.source !== 'dashboard' || !fresh || !sameKey ||
      typeof snapshot?.availableUsd !== 'number' || !Number.isFinite(snapshot.availableUsd) || snapshot.availableUsd < 0)
    return { access, ...evidence, balance: 'unknown', balanceSource: 'account dashboard evidence required' };
  return { access, ...evidence, balance: 'dashboard-recorded', availableUsd: snapshot.availableUsd,
    balanceSource: 'account dashboard', observedAt: snapshot.observedAt, credentialSha256: hash(key) };
}

function estimate(provider, rate, batches) {
  const chars = batches.reduce((n, b) => n + count(b.text), 0);
  if (!rate) return { characters: chars, estimatedUsd: null };
  if (provider === 'openai') {
    const words = batches.reduce((sum, b) => sum + speechWordEstimate(b.text), 0);
    return { characters: chars, estimatedUsd: usd(((words / 150 * 1200) * rate.usdPerMillionOutputAudioTokens +
      (Math.ceil(chars / 4) + 100 * batches.length) * rate.usdPerMillionInputTextTokens) / 1e6) };
  }
  if (provider === 'assemblyai') return { characters: chars, estimatedUsd: nanosToUsd(assemblyNanos(chars, rate)) };
  // Deepgram's existing governed adapter reserves UTF-8 bytes; quoted list cost is per character.
  return { characters: chars, estimatedUsd: usd(chars * rate.usdPerMillionCharacters / 1e6),
    ...(provider === 'deepgram' ? { adapterReservationUsd: usd(batches.reduce((n, b) =>
      n + Buffer.byteLength(b.text), 0) * deepgramPolicy.usdMicrosPerUtf8Byte / 1e6) } : {}) };
}

// The account inventory exposes the speech multiplier. Dialogue settlement can differ,
// so do not apply the speech multiplier to a different endpoint.
export async function inspectElevenLabs(modelId, { fetcher = fetch, env = process.env } = {}) {
  const key = env.ELEVENLABS_API_KEY;
  if (!key) throw new Error('ELEVENLABS_API_KEY unavailable');
  const headers = { 'xi-api-key': key };
  const base = 'https://api.elevenlabs.io/v1/';
  const [subscription, models] = await Promise.all(['user/subscription', 'models'].map(async endpoint =>
    (await response(fetcher, base + endpoint, { headers })).json()));
  const model = models.find(m => m.model_id === modelId && m.can_do_text_to_speech);
  if (!model) throw new Error('ElevenLabs model absent from the account inventory');
  const { character_cost_multiplier: speechRate, cost_discount_multiplier: discount } = model.model_rates ?? {};
  const used = subscription.character_count, limit = subscription.character_limit;
  return {
    model: modelId, checkedAt: new Date().toISOString(), status: subscription.status ?? 'unknown',
    availableCredits: Number.isFinite(used) && Number.isFinite(limit) ? Math.max(0, limit - used) : null,
    overageEnabled: typeof subscription.can_extend_character_limit === 'boolean' ? subscription.can_extend_character_limit : null,
    speechCreditsPerCharacter: Number.isFinite(speechRate) && speechRate > 0 ? speechRate : null,
    reportedModelDiscountMultiplier: Number.isFinite(discount) && discount > 0 ? discount : null,
    dialogueRate: 'verify against dialogue billing history separately',
  };
}

export async function preflight(script, { snapshots = {}, fetcher = fetch, now = Date.now(), env = process.env,
  openaiKey = env === process.env ? resolveOpenAIKey() : env.OPENAI_API_KEY, readDeepgramBudget = deepgramBudget, outputDir } = {}) {
  validate(script);
  const output = outputDir ? resolve(outputDir) : null;
  const candidates = await Promise.all(Object.keys(models).map(async provider => {
    const batches = makeBatches(script, provider);
    let rate = null, rateEvidence = null;
    try {
      const doc = await (await response(fetcher, urls[provider])).text();
      rate = parseRate(provider, doc);
      if (rate) rateEvidence = { url: urls[provider], checkedAt: new Date(now).toISOString(), documentSha256: hash(doc) };
    } catch { /* No rate from an unavailable or changed source. */ }
    const funding = await account(provider, script, snapshots[provider], [...new Set((batches || []).map(b => b.voice))],
      now, fetcher, provider === 'openai' ? openaiKey : env[keys[provider]]);
    const quote = estimate(provider, rate, batches || []);
    const reasons = [];
    let localBudgetUsd = null, remainingUsd = quote.estimatedUsd, priorReservedUsd = 0, cacheError = null;
    if (!rate) reasons.push('current rate unavailable');
    if (funding.access !== 'verified') reasons.push('voice or account access unverified');
    if (funding.balance !== 'dashboard-recorded') reasons.push('available account balance unknown');
    if (provider === 'assemblyai' && output && batches && rate && env.ASSEMBLYAI_API_KEY) {
      try {
        const plan = assemblyPlan(script, output, rate, env.ASSEMBLYAI_API_KEY, hash(canonical(script)));
        const priorNanos = plan.reduce((sum, part) => sum + (part.prior ? part.reservedNanos : 0), 0);
        const remainingNanos = plan.reduce((sum, part) => sum + (part.prior ? 0 : part.reservedNanos), 0);
        priorReservedUsd = nanosToUsd(priorNanos);
        remainingUsd = nanosToUsd(remainingNanos);
        quote.estimatedUsd = nanosToUsd(priorNanos + remainingNanos);
      } catch (error) {
        cacheError = error.message;
      }
    }
    if (remainingUsd !== null && funding.availableUsd < (quote.adapterReservationUsd ?? remainingUsd)) reasons.push('insufficient available balance');
    if (!batches) reasons.push('compatible full cast required');
    if (provider === 'assemblyai' && (script.requiresDirection || script.requiresLinkedDialogue))
      reasons.push('requires directed performance or linked dialogue');
    if (provider === 'deepgram') {
      const available = funding.access === 'verified' ? readDeepgramBudget() : null;
      if (!Number.isSafeInteger(available) || available < 0) reasons.push('governed Deepgram local budget unavailable');
      else {
        localBudgetUsd = available / 1e6;
        if (quote.adapterReservationUsd > localBudgetUsd) reasons.push('insufficient governed Deepgram local budget');
      }
      if (new Date(now).toISOString().slice(0, 10) > deepgramPolicy.validThrough ||
          rate?.usdPerMillionCharacters !== deepgramPolicy.usdMicrosPerUtf8Byte)
        reasons.push('governed Deepgram reservation policy requires refresh');
      if ((script.language ?? 'english') !== deepgramPolicy.language || script.requiresDirection ||
          script.requiresLinkedDialogue || batches?.some(b => !deepgramPolicy.voices.includes(b.voice)))
        reasons.push('requires unsupported Deepgram language, cast or performance controls');
    }
    if (provider === 'openai' && script.requiresLinkedDialogue)
      reasons.push('Realtime speech renders one speaker per request');
    if ((script.region ?? 'us') === 'eu' && provider !== 'assemblyai') reasons.push('EU synthesis not configured on this lane');
    return { provider, model: models[provider], voices: [...new Set((batches || []).map(b => b.voice))],
      method: methods[provider], discountedBatch: false,
      rate, rateEvidence, funding, ...quote, remainingUsd, priorReservedUsd, localBudgetUsd, cacheError,
      requests: batches?.length ?? null, reasons };
  }));
  const eligible = candidates.filter(c => !c.reasons.length && !c.cacheError);
  // Owner direction 2026-11-23: stock voices for ABACare films use AssemblyAI on ABACare credit;
  // every other film defaults to Deepgram, and AssemblyAI is only chosen there when the job names it.
  const abacare = script.entity === 'abacare';
  const routed = abacare ? eligible : eligible.filter(c => c.provider !== 'assemblyai');
  const stockDefault = routed.find(c => c.provider === (abacare ? 'assemblyai' : 'deepgram'));
  const longForm = script.longForm ?? script.turns.reduce((n, t) => n + t.text.trim().split(/\s+/).length, 0) >= 1200;
  const pick = script.provider ? eligible.find(c => c.provider === script.provider) :
    stockDefault || routed.sort((a, b) => a.estimatedUsd - b.estimatedUsd)[0];
  return { schema: 1, checkedAt: new Date(now).toISOString(), scriptSha256: hash(canonical(script)),
    entity: script.entity, region: script.region ?? 'us', outputDir: output, longForm, candidates, pick: pick?.provider ?? null,
    assemblyExecution: pick?.provider === 'assemblyai' ? 'available after exact job authorization' : 'use selected governed adapter',
    elevenlabs: 'explicit owner-authorized lane only; never chosen by automatic routing' };
}

export async function executeAssembly(script, quote, authorization, directory, options = {}) {
  const output = resolve(directory);
  const current = await preflight(script, { ...options, outputDir: output });
  const { quoteSha256: printedHash, ...pinned } = quote;
  const age = Date.parse(current.checkedAt) - Date.parse(pinned.checkedAt);
  const digest = hash(canonical(pinned));
  const expected = current.candidates.find(c => c.provider === 'assemblyai');
  const locked = pinned.candidates?.find(c => c.provider === 'assemblyai');
  const key = (options.env ?? process.env).ASSEMBLYAI_API_KEY;
  if (quote.pick !== 'assemblyai' ||
      expected.reasons.some(reason => reason !== 'insufficient available balance') ||
      expected.funding.credentialSha256 !== locked?.funding?.credentialSha256 ||
      current.scriptSha256 !== pinned.scriptSha256 ||
      !Number.isFinite(age) || age < 0 || age > fixedGap ||
      (printedHash !== undefined && printedHash !== digest) || authorization.quoteSha256 !== digest ||
      typeof authorization.ownerApproval !== 'string' || !authorization.ownerApproval.trim() ||
      authorization.entity !== script.entity ||
      (pinned.outputDir && pinned.outputDir !== output) ||
      typeof authorization.outputDir !== 'string' || resolve(authorization.outputDir) !== output ||
      typeof authorization.maxUsd !== 'number' || !Number.isFinite(authorization.maxUsd) ||
      authorization.maxUsd < expected.estimatedUsd || expected.estimatedUsd !== locked?.estimatedUsd ||
      canonical(expected.rate) !== canonical(locked.rate))
    throw new Error('Fresh funded quote and exact AssemblyAI job authorization required');
  if (expected.cacheError) throw new Error(expected.cacheError);
  mkdirSync(output, { recursive: true });
  const identity = join(output, 'assemblyai-job.json');
  const lock = { entity: script.entity, scriptSha256: current.scriptSha256, credentialSha256: hash(key) };
  try {
    save(identity, lock, 'wx');
  } catch (error) {
    if (error.code !== 'EEXIST' || canonical(fileJSON(identity)) !== canonical(lock)) throw error;
  }
  const planned = assemblyPlan(script, output, expected.rate, key, current.scriptSha256);
  const host = hosts[current.region];
  const fetcher = options.fetcher ?? fetch;
  if (nanosToUsd(planned.reduce((sum, part) => sum + part.reservedNanos, 0)) > authorization.maxUsd)
    throw new Error('Existing reservations plus remaining narration exceed the authorized cap');
  const remainingUsd = nanosToUsd(planned.reduce((sum, part) => sum + (part.prior ? 0 : part.reservedNanos), 0));
  if (remainingUsd > expected.funding.availableUsd) throw new Error('Insufficient balance for remaining narration');
  const results = [];
  for (const { batch, input, requestHash, takeId, wav, receipt, marker, staged, prior, priorFile, reservedNanos } of planned) {
    if (prior) {
      if (priorFile === staged && existsSync(staged)) renameSync(staged, receipt);
      results.push(prior);
      continue;
    }
    // Exclusive marker goes before the provider call. A timeout or torn result stays fenced on rerun.
    const submission = { requestSha256: requestHash, quoteSha256: authorization.quoteSha256, reservedNanos,
      submittedAt: new Date().toISOString(), model: input.model_id, voice: input.voice_id, characters: count(batch.text) };
    reserveSubmission(output, takeId, submission);
    save(marker, submission, 'wx');
    const res = await fetcher(host + '/v1/speech', {
      method: 'POST', redirect: 'error', headers: { Authorization: key, 'Content-Type': 'application/json' },
      body: canonical(input), signal: AbortSignal.timeout(240000),
    });
    const providerRequestId = res.headers.get('x-request-id') ?? res.headers.get('x-tts-request-id');
    save(receipt + '.response', { requestSha256: requestHash, providerRequestId, status: res.status,
      receivedAt: new Date().toISOString() }, 'wx');
    if (!res.ok) throw new Error('AssemblyAI HTTP ' + res.status);
    const audio = Buffer.from(await res.arrayBuffer());
    if (!validWav(audio)) {
      writeFileSync(receipt + '.rejected', audio, { flag: 'wx', flush: true });
      throw new Error('AssemblyAI response failed WAV verification; the billed bytes are kept beside the receipt for reconciliation');
    }
    const record = { provider: 'assemblyai', model: models.assemblyai, voice: batch.voice, speaker: batch.speaker,
      turns: batch.turns, requestSha256: requestHash, outputSha256: hash(audio), characters: count(batch.text),
      estimatedUsd: nanosToUsd(reservedNanos), actualUsd: null,
      providerRequestId, wav };
    save(staged, record, 'wx');
    writeFileSync(wav, audio, { flag: 'wx', flush: true });
    renameSync(staged, receipt);
    results.push(record);
  }
  save(join(output, 'narration-manifest.json'), { quoteSha256: authorization.quoteSha256, results });
  return results;
}

function withSqliteJournal(file, readOnly, work) {
  if (file.startsWith('\\\\') || file.startsWith('//')) throw new Error('Use a local narration ledger');
  let DatabaseSync;
  try { ({ DatabaseSync } = require('node:sqlite')); }
  catch (error) { throw new Error('Narration ledgers need Node 22.13 or later (built-in node:sqlite)', { cause: error }); }
  const db = new DatabaseSync(file, { readOnly });
  try {
    db.exec('PRAGMA busy_timeout=5000');
    if (!readOnly) db.exec('PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA;');
    return work(db);
  } catch (error) {
    if (readOnly && error.errcode === 776)
      throw new Error('Interrupted local ledger requires narration-preflight.mjs recover-ledgers', { cause: error });
    throw error;
  } finally {
    db.close();
  }
}

export function recoverLedgers(output, spendDir = defaultSpendDir()) {
  const targets = [[join(spendDir, 'openai-narration.sqlite3'), 'voice_spend', marketingSchema]];
  if (output) targets.push([join(resolve(output), 'assemblyai-submissions.sqlite3'), 'submissions', submissionSchema]);
  let checked = 0;
  for (const [file, table, schema] of targets.filter(([candidate]) => existsSync(candidate))) {
    // A writable integrity read rolls back any interrupted transaction. Committed rows stay reserved.
    withSqliteJournal(file, false, db => {
      const rows = db.prepare('PRAGMA quick_check').all();
      if (rows.length !== 1 || rows[0].quick_check !== 'ok') throw new Error('Narration ledger integrity check failed');
      const tables = db.prepare("SELECT name FROM sqlite_schema WHERE type = 'table'").all();
      if (tables.length === 0) db.exec(schema);
      else if (tables.length !== 1 || tables[0].name !== table) throw new Error('Unexpected narration ledger schema');
    });
    checked++;
  }
  return { checked };
}

function reserveSubmission(output, takeId, submission) {
  // SQLite commits the reservation on local disk before transport. The JSON marker is operator evidence.
  withSqliteJournal(join(output, 'assemblyai-submissions.sqlite3'), false, db => {
    db.exec(submissionSchema);
    const claim = db.prepare('INSERT INTO submissions VALUES (?, ?) ON CONFLICT DO NOTHING')
      .run(takeId, canonical(submission));
    if (claim.changes !== 1) throw new Error('Previously submitted request requires reconciliation');
  });
}

function assemblyPlan(script, output, rate, key, scriptSha256) {
  const identity = join(output, 'assemblyai-job.json');
  const hasIdentity = existsSync(identity);
  const lock = { entity: script.entity, scriptSha256, credentialSha256: hash(key) };
  if (hasIdentity && canonical(fileJSON(identity)) !== canonical(lock))
    throw new Error('AssemblyAI output belongs to a different job or account');
  const journalFile = join(output, 'assemblyai-submissions.sqlite3');
  const journal = !existsSync(journalFile) ? new Map() : withSqliteJournal(journalFile, true,
    db => new Map(db.prepare('SELECT take_id, evidence FROM submissions')
      .all().map(row => [row.take_id, JSON.parse(row.evidence)])));
  const host = hosts[script.region ?? 'us'];
  return makeBatches(script, 'assemblyai').map((batch, i) => {
    const input = { model_id: models.assemblyai, voice_id: batch.voice, text: batch.text, sample_rate: 24000,
      language: script.language ?? 'english', encoding: 'pcm_s16le', container: 'wav', stream: false };
    const requestHash = hash(canonical({ host, input }));
    const takeNumber = String(i + 1).padStart(4, '0');
    const takeId = `${takeNumber}:${requestHash}`;
    const stem = join(output, `${takeNumber}-${requestHash.slice(0, 20)}`);
    const wav = stem + '.wav', receipt = stem + '.json', marker = stem + '.submitted.json';
    const staged = receipt + '.staged';
    const priorFile = existsSync(receipt) ? receipt : existsSync(staged) && existsSync(wav) ? staged : null;
    const prior = priorFile ? fileJSON(priorFile) : null;
    let reservedNanos = assemblyNanos(count(batch.text), rate);
    if (prior) {
      const submission = journal.get(takeId) ?? fileJSON(marker);
      const audio = readFileSync(wav);
      if (!hasIdentity || prior.requestSha256 !== requestHash || prior.outputSha256 !== hash(audio) || !validWav(audio) ||
          submission.requestSha256 !== requestHash || !Number.isSafeInteger(submission.reservedNanos) || submission.reservedNanos < 0)
        throw new Error('Cached audio or receipt integrity check failed');
      reservedNanos = submission.reservedNanos;
    } else if (journal.has(takeId) || existsSync(marker) || existsSync(wav) || existsSync(staged)) {
      throw new Error('Previously submitted request requires reconciliation');
    }
    return { batch, input, requestHash, takeId, wav, receipt, marker, staged, prior, priorFile, reservedNanos };
  });
}

function validWav(audio) {
  if (audio.length < 46 || audio.length > 64 * 1024 * 1024 ||
      audio.toString('ascii', 0, 4) !== 'RIFF' || audio.toString('ascii', 8, 12) !== 'WAVE' ||
      audio.readUInt32LE(4) !== audio.length - 8) return false;
  let format = false, hasAudio = false;
  for (let at = 12; at + 8 <= audio.length;) {
    const type = audio.toString('ascii', at, at + 4);
    const size = audio.readUInt32LE(at + 4), start = at + 8;
    if (start + size > audio.length) return false;
    if (type === 'fmt ' && size >= 16) format = audio.readUInt16LE(start) === 1 &&
      audio.readUInt16LE(start + 2) === 1 && audio.readUInt32LE(start + 4) === 24000 &&
      audio.readUInt16LE(start + 14) === 16;
    if (type === 'data') hasAudio = size > 0 && size % 2 === 0;
    at = start + size + (size % 2);
  }
  return format && hasAudio;
}

async function main(args) {
  const [action, scriptFile, snapshotsFile, quoteFile, approvalFile, output] = args;
  if (action === 'recover-ledgers' && args.length <= 2) {
    console.log(JSON.stringify(recoverLedgers(scriptFile)));
    return;
  }
  if (action === 'inspect-elevenlabs' && scriptFile) {
    console.log(JSON.stringify(await inspectElevenLabs(scriptFile), null, 2));
    return;
  }
  if (action === 'fingerprint' && Object.hasOwn(keys, scriptFile)) {
    const credential = scriptFile === 'openai' ? resolveOpenAIKey() : process.env[keys[scriptFile]];
    if (!credential) throw new Error('Credential unavailable');
    console.log(hash(credential)); return;
  }
  if (action === 'batches' && scriptFile && Object.hasOwn(models, snapshotsFile)) {
    const batches = makeBatches(fileJSON(scriptFile), snapshotsFile);
    if (!batches) throw new Error('Compatible full cast required');
    console.log(JSON.stringify({ provider: snapshotsFile, method: methods[snapshotsFile], batches }, null, 2));
    return;
  }
  if (!['quote', 'execute'].includes(action) || !scriptFile || (action === 'execute' && (!snapshotsFile || !quoteFile || !approvalFile || !output)))
    throw new Error('Usage: narration-preflight.mjs quote script.json [funding.json [output-dir]] | execute script.json funding.json quote.json approval.json output-dir | batches script.json provider | fingerprint provider | inspect-elevenlabs model-id | recover-ledgers [output-dir]');
  const script = fileJSON(scriptFile);
  const snapshots = snapshotsFile ? fileJSON(snapshotsFile) : {};
  if (action === 'execute') {
    const records = await executeAssembly(script, fileJSON(quoteFile), fileJSON(approvalFile), output, { snapshots });
    console.log(JSON.stringify({ completed: records.length, output: resolve(output) }));
    return;
  }
  const quote = await preflight(script, { snapshots, outputDir: quoteFile });
  console.log(JSON.stringify({ ...quote, quoteSha256: hash(canonical(quote)) }, null, 2));
}

function isMain() {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); }
  catch { return false; }
}

if (isMain()) {
  main(process.argv.slice(2)).catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
