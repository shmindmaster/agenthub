#!/usr/bin/env node
// cloud-ai: hosted AI steps for media-studio films, so no local model runs.
//
//   node cloud-ai.mjs qa     --images <a.jpg> [<b.jpg>...] [--prompt <text|file>] --out <report.json>
//   node cloud-ai.mjs review --files <script.md> [<more>...] [--rubric <text|file>] [--threshold 85] --out <review.json>
//
// opts: --provider anthropic|openai|gemini (default: anthropic, then openai, then gemini on rate limits, exhausted quota or outages)
//       --model <id>   --client (client material: Anthropic is refused; pass --provider openai explicitly)
// Keys come from ANTHROPIC_API_KEY / OPENAI_API_KEY (process env, then the Windows user environment). Never printed.
// Output: one JSON report (score 0-100, pass, findings, summary, provider, model, usage). Exit 0 = report written and pass.
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

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
    // An exhausted balance never clears by waiting: spill to the next provider at once.
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
async function callGemini({ system, text, images, model }) {
  const key = userEnv('GEMINI_API_KEY');
  if (!key) throw new Error('GEMINI_API_KEY is not set');
  if (!model && !geminiModel) {
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?pageSize=200&key=${key}`);
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

/** Anthropic first, then OpenAI and Gemini on rate limits, exhausted quota or outages. --client refuses Anthropic (client material stays off that org). */
export function providerOrder(opts) {
  if (opts.client && opts.provider !== 'openai') throw new Error('--client material may not go to Anthropic; pass --provider openai explicitly if that provider is approved for it');
  if (opts.client && opts.provider === 'openai') return ['openai'];
  if (opts.provider) return [opts.provider];
  return ['anthropic', 'openai', 'gemini'];
}

async function ask(opts, request) {
  const errors = [];
  for (const p of providerOrder(opts)) {
    try {
      const r = await { anthropic: callAnthropic, openai: callOpenAi, gemini: callGemini }[p]({ ...request, model: p === (opts.provider || 'anthropic') ? opts.model : undefined });
      return { provider: p, ...r, spilled: errors };
    } catch (err) {
      errors.push(`${p}: ${err.message}`);
      if (!(err instanceof RateLimited)) break;
    }
  }
  throw new Error(`no provider answered: ${errors.join('; ')}`);
}

const REPORT_SHAPE = 'Reply with JSON only: {"score": <0-100 integer>, "pass": <boolean>, "summary": "<2-3 sentences>", "findings": [{"severity": "blocker|major|minor", "where": "<frame, timestamp, line or section>", "issue": "<what is wrong>", "fix": "<concrete fix>"}]}';

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
  if (!['qa', 'review'].includes(sub) || !opts.out) {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 11).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
    return sub ? 2 : 0;
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
