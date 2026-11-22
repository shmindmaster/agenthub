// OpenAI REST client for mvg: images, speech, word timing and vision QA (Responses API with a JSON schema), on current models.
// There is no OpenAI video call here. Requests carry only approved ad text and sampled frames.
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { basename } from 'node:path';

const BASE = 'https://api.openai.com/v1';

export class OpenAiError extends Error {
  constructor(message, status) { super(message); this.name = 'OpenAiError'; this.status = status; }
}

/** The Windows user environment wins over the process copy, which goes stale in long-running shells after a key rotation. */
function userEnv(name) {
  if (process.platform === 'win32' && !process.env.NODE_TEST_CONTEXT) {
    const r = spawnSync('reg', ['query', 'HKCU\\Environment', '/v', name], { encoding: 'utf8', windowsHide: true });
    const m = r.status === 0 && r.stdout.match(new RegExp(`${name}\\s+REG_(?:EXPAND_)?SZ\\s+(.+)`));
    if (m) return m[1].trim();
  }
  return process.env[name] || null;
}
function apiKey() {
  const key = userEnv('OPENAI_API_KEY');
  if (!key) throw new OpenAiError('OPENAI_API_KEY is not set');
  return key;
}

async function call(path, init, { retries = 3, fetchImpl = fetch } = {}) {
  let last;
  for (let attempt = 0; attempt <= retries; attempt++) {
    let res;
    try {
      res = await fetchImpl(BASE + path, { ...init, headers: { Authorization: `Bearer ${apiKey()}`, ...(init.headers || {}) } });
    } catch (e) { last = new OpenAiError(`OpenAI request failed: ${e.cause?.code || e.message}`); await sleep(500 * 2 ** attempt); continue; }
    if (res.ok) return res;
    const body = await res.text().catch(() => '');
    let code = '';
    try { const j = JSON.parse(body); code = j.error?.code || j.error?.type || ''; } catch { /* not json */ }
    // The message can echo prompt text; report only the status and the machine code.
    last = new OpenAiError(`OpenAI ${path} returned HTTP ${res.status}${code ? ` (${String(code).slice(0, 60)})` : ''}`, res.status);
    if (res.status === 429 || res.status >= 500) { await sleep(800 * 2 ** attempt); continue; }
    throw last;
  }
  throw last;
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function generateImage({ prompt, model = OPENAI_MODELS.imageDefault, size = '1536x1024', quality = 'medium', fetchImpl }) {
  const res = await call('/images/generations', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, prompt, size, quality, n: 1, output_format: 'png' }),
  }, { fetchImpl });
  const json = await res.json();
  const b64 = json.data?.[0]?.b64_json;
  if (!b64) throw new OpenAiError('image response carried no image data');
  return { bytes: Buffer.from(b64, 'base64'), usage: json.usage || null, model, size, quality };
}

/**
 * Narration through the Realtime API (gpt-realtime-2.1-mini; gpt-realtime-2.1 for complex direction). The session reads the
 * line verbatim with the chosen voice and delivery instructions; audio comes back as 24 kHz mono PCM, returned as WAV.
 */
export async function speech({ text, voice = 'marin', instructions, model = OPENAI_MODELS.realtimeSpeech,
  credential = apiKey(), maxOutputTokens, timeoutMs = 60000, WebSocketImpl = globalThis.WebSocket }) {
  if (!WebSocketImpl) throw new OpenAiError('This Node has no WebSocket; use Node 22 or later');
  const ws = new WebSocketImpl(`wss://api.openai.com/v1/realtime?model=${encodeURIComponent(model)}`, { headers: { Authorization: `Bearer ${credential}` } });
  const chunks = [];
  const usage = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { try { ws.close(); } catch { /* closing */ } reject(new OpenAiError('OpenAI realtime speech timed out')); }, timeoutMs);
    ws.onopen = () => {
      const rule = 'Read the user text aloud exactly as written. Do not add, answer or comment.';
      ws.send(JSON.stringify({ type: 'session.update', session: { type: 'realtime', output_modalities: ['audio'], instructions: instructions ? `${rule} Delivery: ${instructions}` : rule, audio: { output: { voice, format: { type: 'audio/pcm', rate: 24000 } } } } }));
      ws.send(JSON.stringify({ type: 'conversation.item.create', item: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] } }));
      ws.send(JSON.stringify({ type: 'response.create',
        ...(maxOutputTokens === undefined ? {} : { response: { max_output_tokens: maxOutputTokens } }) }));
    };
    ws.onmessage = (e) => {
      const m = JSON.parse(typeof e.data === 'string' ? e.data : Buffer.from(e.data).toString());
      if (m.type === 'response.output_audio.delta') chunks.push(Buffer.from(m.delta, 'base64'));
      else if (m.type === 'error') { clearTimeout(timer); ws.close(); reject(new OpenAiError(`OpenAI realtime error${m.error?.code ? ` (${String(m.error.code).slice(0, 60)})` : ''}`)); }
      else if (m.type === 'response.done') { clearTimeout(timer); ws.close(); if (m.response?.status !== 'completed') reject(new OpenAiError(`OpenAI realtime response ${m.response?.status}`)); else resolve(m.response?.usage || null); }
    };
    ws.onerror = () => { clearTimeout(timer); reject(new OpenAiError('OpenAI realtime connection failed')); };
  });
  return { bytes: pcmToWav(Buffer.concat(chunks), 24000), usage, model, voice, format: 'wav' };
}
function pcmToWav(pcm, rate) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}
/**
 * Hosted word timing. No current OpenAI transcription model returns word timestamps (gpt-transcribe returns text), so this
 * refuses and word timing stays on the forced aligner (kit/cloud/cloud-ai.mjs align). Tests inject their own provider.
 */
export async function transcribeWords() {
  throw new OpenAiError('No current OpenAI model returns word timestamps; use the forced aligner (kit/cloud/cloud-ai.mjs align)');
}/**
 * Azure OpenAI speech-to-text through the MahumTech resource (mt-foundary-resource), deployment gpt-transcribe. It returns
 * text, not word timestamps, so word timing stays on the forced aligner. Endpoint and key come from
 * AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY by name; neither is printed.
 */
export async function transcribeAzure(file, { deployment = 'gpt-transcribe', fetchImpl = fetch, endpoint = process.env.AZURE_OPENAI_ENDPOINT, key = process.env.AZURE_OPENAI_API_KEY } = {}) {
  if (!endpoint || !key) throw new OpenAiError('AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_API_KEY must be set');
  const form = new FormData();
  form.append('file', new Blob([readFileSync(file)]), basename(file));
  form.append('response_format', 'json');
  const url = `${endpoint.replace(/\/$/, '')}/openai/deployments/${encodeURIComponent(deployment)}/audio/transcriptions?api-version=2025-04-01-preview`;
  const res = await fetchImpl(url, { method: 'POST', headers: { 'api-key': key }, body: form });
  if (!res.ok) throw new OpenAiError(`Azure transcription returned HTTP ${res.status}`, res.status);
  return res.json();
}

/** Vision over sampled frames with a strict JSON schema. Returns { json, usage, text }. */
export async function visionJson({ model, system, instructions, frames, schema, schemaName = 'verdict', detail = 'high', fetchImpl }) {
  const content = [{ type: 'input_text', text: instructions }];
  for (const f of frames) {
    content.push({ type: 'input_text', text: `Frame ${f.label} (t=${f.t}s)` });
    content.push({ type: 'input_image', image_url: f.dataUrl, detail });
  }
  const res = await call('/responses', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, max_output_tokens: 6000,
      input: [{ role: 'system', content: [{ type: 'input_text', text: system }] }, { role: 'user', content }],
      text: { format: { type: 'json_schema', name: schemaName, schema, strict: true } },
    }),
  }, { fetchImpl });
  const body = await res.json();
  const text = body.output_text || (body.output || []).flatMap((o) => o.content || []).filter((c) => c.type === 'output_text').map((c) => c.text).join('');
  if (!text) throw new OpenAiError('vision response carried no text');
  return { text, usage: body.usage || null, model: body.model || model };
}

/**
 * Model roles for the direct OpenAI API (OPENAI_API_KEY). Studio's quality tier picks among them; the price table is
 * OPENAI_*_USD_PER_M in prices.mjs. Escalate a role only when a review shows the cheaper model fails the gate.
 */
export const OPENAI_MODELS = {
  premiumReasoning: 'gpt-6-astra', // hardest scripts, creative direction, difficult reviews
  creative: 'gpt-6.1-sol', // storyboards, narration writing, product messaging
  editorial: 'gpt-6.1-terra', // copy edits, frame and image review, structured plans
  bulk: 'gpt-6-luna', // captions, metadata, classification, repetitive transforms
  imageDefault: 'gpt-image-2.6-flare',
  imagePremium: 'gpt-image-2.6-sunburst',
  transcribe: 'gpt-transcribe',
  realtimeSpeech: 'gpt-realtime-2.1-mini',
  realtimeSpeechPremium: 'gpt-realtime-2.1',
  moderation: 'omni-moderation-latest',
};

/**
 * Text generation with the Responses API. `stable` is the cacheable prefix (brand guide, product facts, rules, output
 * schema) and goes first so repeated calls hit the prompt cache; `dynamic` is the scene-specific request.
 * Returns usage so the ledger records cached and fresh tokens instead of a theoretical discount.
 */
export async function generateText({ role = 'creative', model, stable = '', dynamic, schema, schemaName = 'result', maxOutputTokens = 4000, fetchImpl }) {
  const m = model || OPENAI_MODELS[role] || OPENAI_MODELS.creative;
  const input = [];
  if (stable) input.push({ role: 'developer', content: [{ type: 'input_text', text: stable }] });
  input.push({ role: 'user', content: [{ type: 'input_text', text: dynamic }] });
  const body = { model: m, input, max_output_tokens: maxOutputTokens };
  if (schema) body.text = { format: { type: 'json_schema', name: schemaName, schema, strict: true } };
  const res = await call('/responses', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, { fetchImpl });
  const json = await res.json();
  const text = json.output_text ?? (json.output || []).flatMap((o) => o.content || []).filter((c) => c.type === 'output_text').map((c) => c.text).join('');
  return { text, usage: json.usage || null, model: json.model || m, cachedTokens: json.usage?.input_tokens_details?.cached_tokens ?? 0 };
}

/** File transcription with gpt-transcribe (text only, no word timestamps). */
export async function transcribeText(file, { model = OPENAI_MODELS.transcribe, fetchImpl } = {}) {
  const form = new FormData();
  form.append('model', model);
  form.append('file', new Blob([readFileSync(file)]), basename(file));
  const res = await call('/audio/transcriptions', { method: 'POST', body: form }, { fetchImpl });
  const json = await res.json();
  return { text: json.text || '', usage: json.usage || null, model };
}

/** Free moderation check for text and images before publishing generated media. */
export async function moderate(input, { fetchImpl } = {}) {
  const res = await call('/moderations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: OPENAI_MODELS.moderation, input }) }, { fetchImpl });
  const json = await res.json();
  return { flagged: (json.results || []).some((r) => r.flagged), results: json.results || [] };
}
