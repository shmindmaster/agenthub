#!/usr/bin/env node
// cloud-ai: hosted AI steps for media-studio films, so no local model runs.
//
//   node cloud-ai.mjs qa     --images <a.jpg> [<b.jpg>...] [--prompt <text|file>] --out <report.json>
//   node cloud-ai.mjs review --files <script.md> [<more>...] [--rubric <text|file>] [--threshold 85] --out <review.json>
//   node cloud-ai.mjs align  --take <take.wav> --script <locked-script.txt> --out <voice/align/<id>.json | qa/encoded-alignment.json>
//                            [--provider azure|azure-s0|deepgram]   (default Azure F0 only; name another provider explicitly to use it)
//
// opts: --provider anthropic|azure-openai|gemini|openai (default: anthropic only; name another provider explicitly to use it)
//       --model <id>   --client (client material: never Anthropic; defaults to Azure OpenAI in the owner tenant)
// Keys come from ANTHROPIC_API_KEY / OPENAI_API_KEY (process env, then the Windows user environment). Never printed.
// Output: one JSON report (score 0-100, pass, findings, summary, provider, model, usage). Exit 0 = report written and pass.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { CLOUD_ALIGN_LIMITS, CLOUD_ALIGN_SCHEMA, cloudAlignCoverage } from '../screencast/sync-lib.mjs';

const ANTHROPIC_MODEL = 'claude-opus-5-5';
const OPENAI_PREFERRED = /^gpt-(\d+)(?:\.(\d+))?$/;

export function parseArgs(argv) {
  const sub = argv[0];
  const opts = { images: [], files: [] };
  let list = null;
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    const m = a.match(/^--([\w-]+)(?:=(.*))?$/);
    if (!m) {
      if (list) opts[list].push(a);
      continue;
    }
    const key = m[1].replace(/-(\w)/g, (_, c) => c.toUpperCase());
    list = null;
    if (key === 'images' || key === 'files') {
      list = key;
      if (m[2]) opts[key].push(m[2]);
      continue;
    }
    if (key === 'client') {
      opts.client = true;
      continue;
    }
    opts[key] = m[2] ?? argv[++i];
  }
  return { sub, opts };
}

/** Pull the first JSON object out of a model reply (models sometimes wrap it in prose or a code fence). */
export function extractJson(text) {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = fenced ? fenced[1] : text;
  const start = body.indexOf('{');
  const end = body.lastIndexOf('}');
  if (start < 0 || end <= start) throw new Error('model reply has no JSON object');
  return JSON.parse(body.slice(start, end + 1));
}

function userEnv(name) {
  if (process.env[name]) return process.env[name];
  if (process.platform !== 'win32') return null;
  const r = spawnSync('reg', ['query', 'HKCU\\Environment', '/v', name], { encoding: 'utf8', windowsHide: true });
  const m = r.status === 0 && r.stdout.match(new RegExp(`${name}\\s+REG_(?:EXPAND_)?SZ\\s+(.+)`));
  return m ? m[1].trim() : null;
}
const textOrFile = (v) => (v && fs.existsSync(v) ? fs.readFileSync(v, 'utf8') : v);

class RateLimited extends Error {}

async function postJson(url, headers, body) {
  for (let attempt = 0; ; attempt++) {
    const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
    if (res.ok) return res.json();
    const text = await res.text();
    // An exhausted balance never clears by waiting: stop at once (ask/align never spill to another paid provider).
    if (/insufficient_quota|credit_balance|RESOURCE_EXHAUSTED|billing/i.test(text)) throw new RateLimited(`HTTP ${res.status} quota exhausted`);
    const transient = res.status === 429 || res.status === 529 || res.status >= 500;
    if (transient && attempt < 2) {
      const wait = Number(res.headers.get('retry-after')) * 1000 || 2000 * 2 ** attempt;
      await new Promise((r) => setTimeout(r, Math.min(wait, 20000)));
      continue;
    }
    const err = transient ? new RateLimited(`HTTP ${res.status}`) : new Error(`HTTP ${res.status}: ${text.slice(0, 300)}`);
    throw err;
  }
}

const mediaType = (f) => ({ '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif' })[path.extname(f).toLowerCase()];

async function callAnthropic({ system, text, images, model }) {
  const key = userEnv('ANTHROPIC_API_KEY');
  if (!key) throw new Error('ANTHROPIC_API_KEY is not set');
  const content = [
    ...images.map((f) => ({ type: 'image', source: { type: 'base64', media_type: mediaType(f), data: fs.readFileSync(f).toString('base64') } })),
    { type: 'text', text },
  ];
  const j = await postJson('https://api.anthropic.com/v1/messages', { 'x-api-key': key, 'anthropic-version': '2023-06-01' }, { model: model || ANTHROPIC_MODEL, max_tokens: 4096, system, messages: [{ role: 'user', content }] });
  return { text: j.content.filter((c) => c.type === 'text').map((c) => c.text).join('\n'), model: j.model, usage: j.usage };
}

let openaiModel = null;
async function pickOpenAiModel(key) {
  if (openaiModel) return openaiModel;
  const res = await fetch('https://api.openai.com/v1/models', { headers: { Authorization: `Bearer ${key}` } });
  if (!res.ok) throw new Error(`OpenAI models: HTTP ${res.status}`);
  const ids = (await res.json()).data.map((m) => m.id).filter((id) => OPENAI_PREFERRED.test(id));
  ids.sort((a, b) => {
    const [, a1, a2 = 0] = a.match(OPENAI_PREFERRED);
    const [, b1, b2 = 0] = b.match(OPENAI_PREFERRED);
    return b1 - a1 || b2 - a2;
  });
  if (!ids.length) throw new Error('no gpt-N model available to this OpenAI key');
  return (openaiModel = ids[0]);
}

async function callOpenAi({ system, text, images, model }) {
  const key = userEnv('OPENAI_API_KEY');
  if (!key) throw new Error('OPENAI_API_KEY is not set');
  const chosen = model || (await pickOpenAiModel(key));
  const content = [
    ...images.map((f) => ({ type: 'image_url', image_url: { url: `data:${mediaType(f)};base64,${fs.readFileSync(f).toString('base64')}` } })),
    { type: 'text', text },
  ];
  const j = await postJson('https://api.openai.com/v1/chat/completions', { Authorization: `Bearer ${key}` }, { model: chosen, messages: [{ role: 'system', content: system }, { role: 'user', content }] });
  return { text: j.choices[0].message.content, model: j.model, usage: j.usage };
}

let geminiModel = null;
export async function callGemini({ system, text, images, model }) {
  const key = userEnv('GEMINI_API_KEY');
  if (!key) throw new Error('GEMINI_API_KEY is not set');
  if (!model && !geminiModel) {
    const res = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': key } });
    if (!res.ok) throw new Error(`Gemini models: HTTP ${res.status}`);
    const rx = /^models\/gemini-(\d+)(?:\.(\d+))?-(pro|flash)$/;
    const ids = (await res.json()).models.map((m) => m.name).filter((n) => rx.test(n));
    ids.sort((a, b) => {
      const [, a1, a2 = 0, at] = a.match(rx);
      const [, b1, b2 = 0, bt] = b.match(rx);
      return b1 - a1 || b2 - a2 || (at === 'pro' ? -1 : 1) - (bt === 'pro' ? -1 : 1);
    });
    if (!ids.length) throw new Error('no gemini-N model available');
    geminiModel = ids[0].replace(/^models\//, '');
  }
  const chosen = model || geminiModel;
  const parts = [...images.map((f) => ({ inline_data: { mime_type: mediaType(f), data: fs.readFileSync(f).toString('base64') } })), { text }];
  const j = await postJson(`https://generativelanguage.googleapis.com/v1beta/models/${chosen}:generateContent`, { 'x-goog-api-key': key }, { system_instruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts }] });
  return { text: j.candidates[0].content.parts.map((p) => p.text || '').join(''), model: chosen, usage: j.usageMetadata };
}

// Azure OpenAI in the owner's tenant (Entra token, key auth disabled). Endpoint and deployment come from the
// cloud-render config written by Provision-CloudRender.ps1.
function azureOpenAiConfig() {
  const file = path.join(process.env.LOCALAPPDATA || '', 'AgentHub', 'media-studio', 'cloud-render.json');
  const cfg = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
  if (!cfg.azureOpenAI?.endpoint) throw new Error(`no azureOpenAI endpoint in ${file}; run Provision-CloudRender.ps1`);
  return { ...cfg.azureOpenAI, subscriptionId: cfg.subscriptionId };
}
let azureToken = null;
function azureOpenAiToken(subscriptionId) {
  if (azureToken && azureToken.expires - 300 > Date.now() / 1000) return azureToken.value;
  const r = spawnSync(process.platform === 'win32' ? 'az.cmd' : 'az', ['account', 'get-access-token', '--resource', 'https://cognitiveservices.azure.com', '--subscription', subscriptionId, '--query', '{t:accessToken,e:expires_on}', '-o', 'json'], { encoding: 'utf8', windowsHide: true, shell: process.platform === 'win32' });
  if (r.status !== 0) throw new Error('az could not issue a Cognitive Services token (az login?)');
  const j = JSON.parse(r.stdout);
  azureToken = { value: j.t, expires: Number(j.e) };
  return azureToken.value;
}
async function callAzureOpenAi({ system, text, images, model }) {
  const cfg = azureOpenAiConfig();
  const deployment = model || cfg.deployment;
  const content = [
    ...images.map((f) => ({ type: 'image_url', image_url: { url: `data:${mediaType(f)};base64,${fs.readFileSync(f).toString('base64')}` } })),
    { type: 'text', text },
  ];
  const url = `${cfg.endpoint.replace(/\/$/, '')}/openai/deployments/${deployment}/chat/completions?api-version=2025-04-01-preview`;
  const j = await postJson(url, { Authorization: `Bearer ${azureOpenAiToken(cfg.subscriptionId)}` }, { messages: [{ role: 'system', content: system }, { role: 'user', content }] });
  return { text: j.choices[0].message.content, model: `azure:${j.model || deployment}`, usage: j.usage };
}

/**
 * Anthropic by default (today's expiring credit). There is no spillover: on exhausted credit, auth failure or an outage
 * ask() stops with the blocker named, and another paid provider is used only when the caller names it with --provider.
 * The OpenAI platform org is reachable only with --provider openai. --client material never goes to Anthropic: it
 * defaults to Azure OpenAI in the owner's tenant; another provider must be named explicitly.
 */
export function providerOrder(opts) {
  if (opts.client) {
    if (!opts.provider) return ['azure-openai'];
    if (opts.provider === 'anthropic') throw new Error('--client material may not go to Anthropic; use the default (Azure OpenAI in the owner tenant) or name another provider');
    return [opts.provider];
  }
  if (opts.provider) return [opts.provider];
  return ['anthropic'];
}

/** One-line blocker for a provider that cannot answer. Never retried into a different paid provider. */
function blocker(provider, err, hint) {
  const kind = /not set/.test(err.message) ? 'credential missing'
    : /quota exhausted|insufficient_quota|credit_balance/i.test(err.message) ? 'credit or quota exhausted'
    : /HTTP (401|403)\b/.test(err.message) ? 'authentication or free-tier quota refused'
    : err instanceof RateLimited ? 'still rate limited or unavailable after retries'
    : 'failed';
  return new Error(`${provider} blocked (${kind}): ${err.message}. Not falling through to another provider; ${hint}`);
}

export async function ask(opts, request) {
  // Never spill from one paid provider to another. providerOrder() yields the caller's --provider, or the default
  // (Anthropic; Azure OpenAI for --client) and enforces the client guard. postJson already retries transient
  // rate limits on that same provider; credit exhaustion, auth failure and outages stop here with the blocker named.
  const [p] = providerOrder(opts);
  try {
    const r = await { anthropic: callAnthropic, 'azure-openai': callAzureOpenAi, openai: callOpenAi, gemini: callGemini }[p]({ ...request, model: opts.model });
    return { provider: p, ...r, spilled: [] };
  } catch (err) {
    throw blocker(p, err, 'name another provider explicitly with --provider to use it.');
  }
}

// ---------------------------------------------------------------- align
// Script-anchored cloud alignment. Hosted ASR word timestamps (Azure fast transcription by default; other providers
// only when named explicitly with --provider) are matched token-by-token to the locked script. Exact matches keep the acoustic times;
// script words the ASR heard differently take times bounded by their matched neighbours and are flagged
// precisionLimited. Times snap to the native aligner's 80 ms grid; take and script are SHA-256 bound. The
// sync gate accepts the report only while the precisionLimited share and runs stay inside ALIGN_LIMITS.
// The schema and acceptance limits live in the sync gate (kit/screencast/sync-lib.mjs), which re-checks them.
const ALIGN_SCHEMA = CLOUD_ALIGN_SCHEMA;
const ALIGN_LIMITS = CLOUD_ALIGN_LIMITS;
const GRID = 0.08;
const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
export const normToken = (w) => String(w ?? '').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]/gu, '');

const ONES = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split(' ');
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
function intWords(n) {
  if (n < 20) return ONES[n];
  if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? ONES[n % 10] : '');
  if (n < 1000) return ONES[Math.floor(n / 100)] + 'hundred' + (n % 100 ? intWords(n % 100) : '');
  for (const [size, name] of [[1e9, 'billion'], [1e6, 'million'], [1e3, 'thousand']]) {
    if (n >= size) return intWords(Math.floor(n / size)) + name + (n % size ? intWords(n % size) : '');
  }
  return String(n);
}

/**
 * Comparison key: normalized letters/digits, with numbers spoken out so the script's "thirty" or "one point seven
 * one dollars" meets the ASR's "30" or "$1.71" ("$5M" -> fivemilliondollars, "10%" -> tenpercent, "1,200" -> onethousandtwohundred).
 */
const CONTRACTIONS = { im: 'iam', ive: 'ihave', ill: 'iwill', id: 'iwould', youre: 'youare', were: 'were', its: 'its', cant: 'cannot', dont: 'donot', wont: 'willnot', isnt: 'isnot', thats: 'thatis', lets: 'letus', theyre: 'theyare', weve: 'wehave', youll: 'youwill', doesnt: 'doesnot', didnt: 'didnot' };
export function canonKey(text) {
  const s = String(text ?? '').normalize('NFKC').toLowerCase().replace(/[‘’]/g, "'");
  const m = s.match(/^[^\p{L}\p{N}$]*(\$)?([\d,]*\d)(?:\.(\d+))?([kmb]|%|percent)?[^\p{L}\p{N}]*$/u);
  if (!m || /,\d{1,2}(?:\D|$)/.test(m[2])) {
    // Contractions only when written with an apostrophe ("I'm" and "I am" meet; "ill" the adjective is untouched).
    const key = normToken(s);
    const expanded = /'/.test(s) && CONTRACTIONS[key] ? CONTRACTIONS[key] : key;
    return expanded.replace(/\d+/g, (d) => (d.length < 10 ? intWords(Number(d)) : d));
  }
  const whole = Number(m[2].replace(/,/g, ''));
  if (!Number.isSafeInteger(whole)) return normToken(s);
  let out = intWords(whole) + (m[3] ? 'point' + [...m[3]].map((d) => ONES[+d]).join('') : '');
  out += { k: 'thousand', m: 'million', b: 'billion', '%': 'percent', percent: 'percent' }[m[4]] || '';
  return out + (m[1] ? 'dollars' : '');
}

/** Script tokens in reading order (whitespace-split, dropping tokens with no letters or digits). */
export function scriptTokens(text) {
  return String(text).split(/\s+/).filter((t) => normToken(t)).map((t) => ({ text: t, key: canonKey(t) }));
}

/**
 * Times for script tokens that spell the same characters as a run of heard words ("language-model" = "language" +
 * "model", "one percent" = "1%"). A currency word the ASR repeats or moves ("$800 million" for "eight hundred million")
 * is ignored on both sides. A token is precisionLimited when its onset falls inside a heard word, not on its edge.
 */
function compoundTimes(scriptRun, heard) {
  const bare = (k) => k.replace(/dollars?$/, '');
  if (!heard.length || scriptRun.map((t) => bare(t.key)).join('') !== heard.map((h) => bare(h.key)).join('')) return null;
  const edges = [];
  let pos = 0;
  for (const h of heard) {
    const len = bare(h.key).length;
    if (len) edges.push({ from: pos, until: pos + len, start: h.start, end: h.end });
    pos += len;
  }
  if (!edges.length) return null;
  const timeAt = (c, side) => {
    const e = edges.find((x) => (side === 'start' ? c >= x.from && c < x.until : c > x.from && c <= x.until)) || edges.at(-1);
    if (side === 'start' && c === e.from) return { t: e.start, exact: true };
    if (side === 'end' && c >= e.until) return { t: e.end, exact: true };
    return { t: e.start + ((e.end - e.start) * (c - e.from)) / (e.until - e.from), exact: false };
  };
  pos = 0;
  return scriptRun.map((t) => {
    const len = bare(t.key).length;
    if (!len) {
      // A bare currency word ("dollars") spoken after the number: it sits at the end of the run's last heard word.
      const end = edges.at(-1).end;
      return { text: t.text, start: end, end, precisionLimited: true };
    }
    const s = timeAt(pos, 'start');
    pos += len;
    const e = timeAt(pos, 'end');
    return { text: t.text, start: s.t, end: e.t, precisionLimited: !s.exact };
  });
}

/** Levenshtein alignment of script keys to ASR keys. Returns, per script index, the matched ASR index or -1. */
export function matchTokens(script, asr) {
  const n = script.length, m = asr.length;
  const cost = new Uint32Array((n + 1) * (m + 1));
  const at = (i, j) => i * (m + 1) + j;
  for (let i = 0; i <= n; i++) cost[at(i, 0)] = i;
  for (let j = 0; j <= m; j++) cost[at(0, j)] = j;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const sub = cost[at(i - 1, j - 1)] + (script[i - 1].key === asr[j - 1].key ? 0 : 1);
      cost[at(i, j)] = Math.min(sub, cost[at(i - 1, j)] + 1, cost[at(i, j - 1)] + 1);
    }
  }
  const match = new Array(n).fill(-1);
  for (let i = n, j = m; i > 0 && j > 0; ) {
    const same = script[i - 1].key === asr[j - 1].key;
    if (cost[at(i, j)] === cost[at(i - 1, j - 1)] + (same ? 0 : 1)) {
      if (same) match[i - 1] = j - 1;
      i--;
      j--;
    } else if (cost[at(i, j)] === cost[at(i - 1, j)] + 1) i--;
    else j--;
  }
  return match;
}

/** Script words with times: exact matches keep ASR times, gaps are spread by character length inside their bounds. */
export function alignScript(script, asr, durationSeconds) {
  const match = matchTokens(script, asr);
  const words = script.map((t, i) => (match[i] >= 0 ? { text: t.text, start: asr[match[i]].start, end: asr[match[i]].end, precisionLimited: false } : null));
  for (let i = 0; i < script.length; ) {
    if (words[i]) {
      i++;
      continue;
    }
    let j = i;
    while (j < script.length && !words[j]) j++;
    const lo = i > 0 ? words[i - 1].end : 0;
    const hi = j < script.length ? words[j].start : durationSeconds;
    const prevAsr = i > 0 ? match[i - 1] : -1;
    const nextAsr = j < script.length ? match[j] : asr.length;
    const heard = asr.slice(prevAsr + 1, nextAsr);
    const compound = compoundTimes(script.slice(i, j), heard);
    if (compound) {
      compound.forEach((w, k) => (words[i + k] = w));
      i = j;
      continue;
    }
    const from = heard.length ? Math.max(lo, heard[0].start) : lo;
    const until = heard.length ? Math.min(hi, heard.at(-1).end) : hi;
    const chars = script.slice(i, j).reduce((s, t) => s + t.key.length, 0);
    let cursor = from;
    for (let k = i; k < j; k++) {
      const span = ((until - from) * script[k].key.length) / chars;
      words[k] = { text: script[k].text, start: cursor, end: cursor + span, precisionLimited: true };
      cursor += span;
    }
    i = j;
  }
  // Snap to the 80 ms grid without reordering or overlapping.
  const last = Math.floor(durationSeconds / GRID + 1e-9);
  let prev = 0;
  for (const w of words) {
    let s = Math.min(Math.max(Math.round(w.start / GRID), prev), last);
    const e = Math.min(Math.max(Math.round(w.end / GRID), s), last);
    w.start = +(s * GRID).toFixed(2);
    w.end = +(e * GRID).toFixed(2);
    prev = e;
  }
  const c = cloudAlignCoverage(words);
  return { words, coverage: { ...c, exactRatio: +c.exactRatio.toFixed(4), ...ALIGN_LIMITS } };
}

function wavSeconds(buf) {
  if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') return null;
  let byteRate = 0;
  for (let off = 12; off + 8 <= buf.length; ) {
    const id = buf.toString('ascii', off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    if (id === 'fmt ') byteRate = buf.readUInt32LE(off + 16);
    if (id === 'data' && byteRate) return Math.min(size, buf.length - off - 8) / byteRate;
    off += 8 + size + (size % 2);
  }
  return null;
}

/** Comparison keys for heard words. "$800 million" is spoken "eight hundred million dollars": move the currency after the scale word. */
export function heardKeys(words) {
  const out = words.map((w) => ({ key: canonKey(w.text), start: w.start, end: w.end, currency: /^\W*\$/.test(w.text) }));
  out.forEach((w, i) => {
    const next = out[i + 1];
    if (w.currency && next && ['thousand', 'million', 'billion', 'trillion'].includes(next.key)) {
      w.key = w.key.replace(/dollars$/, '');
      next.key += 'dollars';
    }
  });
  return out.map(({ currency, ...w }) => w);
}

async function azureWords(buf, keyVar, regionVar) {
  const key = userEnv(keyVar), region = userEnv(regionVar);
  if (!key || !region) throw new Error(`${keyVar}/${regionVar} not set`);
  const fd = new FormData();
  fd.append('audio', new Blob([buf]), 'take.wav');
  fd.append('definition', JSON.stringify({ locales: ['en-US'] }));
  const res = await fetch(`https://${region}.api.cognitive.microsoft.com/speechtotext/transcriptions:transcribe?api-version=2024-11-15`, { method: 'POST', headers: { 'Ocp-Apim-Subscription-Key': key }, body: fd });
  const text = await res.text();
  if (res.status === 429 || res.status === 403 || res.status >= 500) throw new RateLimited(`HTTP ${res.status}`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);
  const j = JSON.parse(text);
  const words = j.phrases.flatMap((p) => p.words || []).map((w) => ({ text: w.text, start: w.offsetMilliseconds / 1000, end: (w.offsetMilliseconds + w.durationMilliseconds) / 1000 }));
  return { words: heardKeys(words), durationSeconds: j.durationMilliseconds / 1000, provider: { name: 'azure-fast-transcription', region, apiVersion: '2024-11-15', keyVar } };
}

async function deepgramWords(buf) {
  const key = userEnv('DEEPGRAM_API_KEY');
  if (!key) throw new Error('DEEPGRAM_API_KEY not set');
  const res = await fetch('https://api.deepgram.com/v1/listen?model=nova-3&language=en&punctuate=false&smart_format=false', { method: 'POST', headers: { Authorization: `Token ${key}`, 'Content-Type': 'audio/wav' }, body: buf });
  const text = await res.text();
  if (res.status === 429 || res.status === 402 || res.status >= 500) throw new RateLimited(`HTTP ${res.status}`);
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${text.slice(0, 200)}`);
  const j = JSON.parse(text);
  const words = j.results.channels[0].alternatives[0].words.map((w) => ({ text: w.word, start: w.start, end: w.end }));
  return { words: heardKeys(words), durationSeconds: j.metadata?.duration, provider: { name: 'deepgram', model: 'nova-3' } };
}

export const alignOutPath = (out, ok) => (ok ? out : `${out}.failed.json`);

export async function align(opts) {
  if (!opts.take || !opts.script) throw new Error('align: --take <audio> and --script <locked script> are required');
  const take = fs.readFileSync(opts.take);
  const scriptBytes = fs.readFileSync(opts.script);
  const scriptText = scriptBytes.toString('utf8').replace(/^﻿/, '');
  // Stay on the default free-tier provider unless the caller named another one explicitly.
  const p = opts.provider || 'azure';
  let heard;
  try {
    heard = p === 'azure' ? await azureWords(take, 'AZURE_SPEECH_KEY', 'AZURE_SPEECH_REGION')
      : p === 'azure-s0' ? await azureWords(take, 'AZURE_AI_SERVICES_KEY', 'AZURE_AI_SERVICES_REGION')
      : await deepgramWords(take);
  } catch (err) {
    throw blocker(p, err, 'name a paid speech provider explicitly with --provider azure-s0|deepgram to use it.');
  }
  const durationSeconds = wavSeconds(take) ?? heard.durationSeconds;
  const { words, coverage } = alignScript(scriptTokens(scriptText), heard.words.filter((w) => w.key), durationSeconds);
  const ok = coverage.exactRatio >= ALIGN_LIMITS.minExactRatio && coverage.longestUnmatchedRun <= ALIGN_LIMITS.maxUnmatchedRun;
  const report = {
    schema: ALIGN_SCHEMA,
    // Honest label: hosted ASR word times anchored to the script, not forced alignment. Gates accept it only where
    // job.json opts in (clockPolicy.allowAsrAnchored); `agreement` records how it compared with the retired Local-AI
    // forced aligner (a historical measurement; Local AI is off and nothing here starts it).
    method: 'asr-anchored-alignment',
    agreement: {
      measuredAgainst: 'Local-AI forced alignment (Qwen3-ForcedAligner), 3 owner takes, 2026-10-26',
      exactOnsetMedianMs: '0-80',
      exactOnsetP90Ms: 80,
      wordSyncOffsetMs: 0,
      wordSyncDriftMs: 0,
      note: 'precisionLimited onsets (words the ASR heard differently) are bounded by neighbours, not measured',
    },
    ok,
    errors: ok ? [] : [`script coverage too low for a picture clock: ${coverage.exact}/${coverage.total} exact, longest unmatched run ${coverage.longestUnmatchedRun}`],
    createdAt: new Date().toISOString(),
    units: 'seconds',
    gridSeconds: GRID,
    durationSeconds: +durationSeconds.toFixed(3),
    script: { path: path.resolve(opts.script), sha256: sha256(scriptBytes), text: scriptText },
    take: { path: path.resolve(opts.take), sha256: sha256(take) },
    provider: { ...heard.provider, spilled: [] },
    clock: { policy: 'asr-anchored-script-alignment-80ms-grid', note: 'exact token matches carry hosted ASR word times; precisionLimited words are bounded by matched neighbours' },
    coverage,
    independentContentReviewRequired: true,
    words,
    heard: heard.words.map((w) => ({ key: w.key, start: +w.start.toFixed(3), end: +w.end.toFixed(3) })),
  };

  // A report that fails the coverage limits never lands at the requested path: gates and cue-sheet builders read
  // that path as the picture clock. It is kept beside it as <out>.failed.json for diagnosis.
  const outPath = path.resolve(alignOutPath(opts.out, ok));
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, `${JSON.stringify(report, null, 2)}\n`);
  return report;
}

const REPORT_SHAPE ='Reply with JSON only: {"score": <0-100 integer>, "pass": <boolean>, "summary": "<2-3 sentences>", "findings": [{"severity": "blocker|major|minor", "where": "<frame, timestamp, line or section>", "issue": "<what is wrong>", "fix": "<concrete fix>"}]}';

const QA_SYSTEM = `You are a strict film QA reviewer for product and training videos. You inspect contact sheets and frames.
Fail on: blank or black frames, frozen or duplicated frames where motion is expected, clipped or overlapping text, text running off-frame,
illegible text, broken layout, placeholder or lorem text, visible errors or stack traces, mismatched branding, cursor or zoom artifacts,
and any claim on screen that the provided context contradicts. Do not invent problems you cannot see. ${REPORT_SHAPE}`;

const REVIEW_SYSTEM = `You are a senior story editor reviewing a script (and any storyboard) for a short professional film.
Score 0-100 against the rubric. Judge: a clear hook in the first lines, one idea per beat, concrete specifics over generic claims,
no filler or hype, every number or claim supported by the material provided, spoken-language rhythm, a clean ending with one ask.
Quote the exact line for each finding and give a rewritten line as the fix. ${REPORT_SHAPE}`;

async function main() {
  const { sub, opts } = parseArgs(process.argv.slice(2));
  if (!['qa', 'review', 'align'].includes(sub) || !opts.out) {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 14).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
    return sub ? 2 : 0;
  }
  if (sub === 'align') {
    const report = await align(opts);
    console.log(JSON.stringify({ out: alignOutPath(opts.out, report.ok), ok: report.ok, errors: report.errors, coverage: report.coverage, provider: report.provider.name, words: report.words.length }, null, 2));
    return report.ok ? 0 : 1;
  }
  const threshold = Number(opts.threshold ?? 85);
  let request;
  if (sub === 'qa') {
    if (!opts.images.length) throw new Error('qa: --images is required');
    for (const f of opts.images) {
      if (!mediaType(f)) throw new Error(`qa: unsupported image type ${f}`);
      if (fs.statSync(f).size > 5 * 1024 * 1024) throw new Error(`qa: ${f} is over 5 MB; downscale the contact sheet`);
    }
    request = { system: QA_SYSTEM, images: opts.images, text: `${textOrFile(opts.prompt) || 'Inspect these frames.'}\nPass threshold: ${threshold}.` };
  } else {
    if (!opts.files.length) throw new Error('review: --files is required');
    const docs = opts.files.map((f) => `=== ${path.basename(f)} ===\n${fs.readFileSync(f, 'utf8')}`).join('\n\n');
    request = { system: REVIEW_SYSTEM, images: [], text: `Rubric: ${textOrFile(opts.rubric) || 'House story standard.'}\nPass threshold: ${threshold}.\n\n${docs}` };
  }
  const started = Date.now();
  const r = await ask(opts, request);
  const verdict = extractJson(r.text);
  const report = {
    kind: sub,
    score: verdict.score,
    pass: Number(verdict.score) >= threshold && verdict.pass !== false,
    threshold,
    summary: verdict.summary,
    findings: verdict.findings || [],
    provider: r.provider,
    model: r.model,
    usage: r.usage,
    spilled: r.spilled,
    inputs: sub === 'qa' ? opts.images : opts.files,
    seconds: (Date.now() - started) / 1000,
    createdAt: new Date().toISOString(),
  };
  fs.mkdirSync(path.dirname(path.resolve(opts.out)), { recursive: true });
  fs.writeFileSync(opts.out, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ out: opts.out, score: report.score, pass: report.pass, findings: report.findings.length, provider: report.provider, model: report.model }, null, 2));
  return report.pass ? 0 : 1;
}

const realpath = (p) => {
  try {
    return fs.realpathSync.native(p).toLowerCase();
  } catch {
    return path.resolve(p).toLowerCase();
  }
};
if (process.argv[1] && realpath(process.argv[1]) === realpath(fileURLToPath(import.meta.url))) {
  main().then(
    (code) => process.exit(code),
    (err) => {
      console.error(`cloud-ai: ${err.message}`);
      process.exit(2);
    },
  );
}
