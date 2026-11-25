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

// The deadline of kit/cloud/cloud-ai.mjs, repeated here because marketing/ is deployed as its own tree: a reply is
// not streamed, so it takes at most the 300 s Node waits for headers, plus sending time at 2 Mbit/s.
const REPLY_MS = 300_000;
const UPLOAD_BYTES_PER_MS = 250;
const MAX_WAIT_MS = 20_000;
const UNKNOWN_OUTCOME = 'not sent again; the provider may still finish and charge for it, so check its usage before rerunning';

const bodyBytes = (body) => (typeof body === 'string' ? Buffer.byteLength(body)
  : [...body.values()].reduce((n, v) => n + (v.size ?? Buffer.byteLength(v)), 0));

/** One bounded POST: the deadline covers connecting, sending and reading the whole body. Nothing here sends twice. */
async function post(what, url, init, fetchImpl) {
  const deadlineMs = REPLY_MS + Math.ceil(bodyBytes(init.body) / UPLOAD_BYTES_PER_MS);
  try {
    const res = await fetchImpl(url, { ...init, method: 'POST', redirect: 'error', signal: AbortSignal.timeout(deadlineMs) });
    return { res, text: await res.text() };
  } catch (e) { // never e.message: an invalid header error repeats the key
    const why = e.name === 'TimeoutError' ? `no complete response within ${deadlineMs / 1000} s` : `request failed: ${e.cause?.code || e.code || e.name}`;
    throw new OpenAiError(`${what}: ${why} (${UNKNOWN_OUTCOME})`);
  }
}

function parsed(what, text) {
  try { return JSON.parse(text); } catch { throw new OpenAiError(`${what}: the paid answer is not JSON`); }
}

/** A paid OpenAI call has no idempotency key, so only a refusal OpenAI answered before generating (429, its own 503) is retried. */
async function call(path, init, { retries = 3, fetchImpl = fetch } = {}) {
  const headers = { Authorization: `Bearer ${apiKey()}`, ...(init.headers || {}) };
  const what = `OpenAI ${path}`;
  for (let attempt = 0; ; attempt++) {
    const { res, text } = await post(what, BASE + path, { ...init, headers }, fetchImpl);
    if (res.ok) return parsed(what, text);
    let code = '';
    try { const j = JSON.parse(text); code = String(j.error?.code || j.error?.type || ''); } catch { /* not json */ }
    const refused = res.status === 429 || (res.status === 503 && code !== '');
    // An exhausted balance never clears by waiting.
    if (refused && attempt < retries && !/insufficient_quota|billing/.test(code)) {
      const seconds = Number(res.headers.get('retry-after'));
      await sleep(Math.min(seconds > 0 ? seconds * 1000 : 800 * 2 ** attempt, MAX_WAIT_MS));
      continue;
    }
    // The message can echo prompt text; report only the status and the machine code.
    throw new OpenAiError(`${what} returned HTTP ${res.status}${code ? ` (${code.slice(0, 60)})` : ''}${res.status >= 500 && !refused ? ` (${UNKNOWN_OUTCOME})` : ''}`, res.status);
  }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function generateImage({ prompt, model = OPENAI_MODELS.imageDefault, size = '1536x1024', quality = 'medium', fetchImpl }) {
  const json = await call('/images/generations', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, prompt, size, quality, n: 1, output_format: 'png' }),
  }, { fetchImpl });
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
  let attempted = false;
  const failure = message => Object.assign(new OpenAiError(message), { definitelyUnsubmitted: !attempted });
  if (!WebSocketImpl) throw failure('This Node has no WebSocket; use Node 22 or later');
  let ws;
  try {
    ws = new WebSocketImpl(`wss://api.openai.com/v1/realtime?model=${encodeURIComponent(model)}`, { headers: { Authorization: `Bearer ${credential}` } });
  } catch {
    throw failure('OpenAI realtime connection could not start');
  }
  const chunks = [];
  const usage = await new Promise((resolve, reject) => {
    const close = () => { try { ws.close(); } catch { /* closing */ } };
    const fail = message => { clearTimeout(timer); reject(failure(message)); close(); };
    const timer = setTimeout(() => fail('OpenAI realtime speech timed out'), timeoutMs);
    ws.onopen = () => {
      const rule = 'Read the user text aloud exactly as written. Do not add, answer or comment.';
      try {
        ws.send(JSON.stringify({ type: 'session.update', session: { type: 'realtime', output_modalities: ['audio'], instructions: instructions ? `${rule} Delivery: ${instructions}` : rule, audio: { output: { voice, format: { type: 'audio/pcm', rate: 24000 } } } } }));
        ws.send(JSON.stringify({ type: 'conversation.item.create', item: { type: 'message', role: 'user', content: [{ type: 'input_text', text }] } }));
        attempted = true;
        ws.send(JSON.stringify({ type: 'response.create',
          ...(maxOutputTokens === undefined ? {} : { response: { max_output_tokens: maxOutputTokens } }) }));
      } catch { fail('OpenAI realtime request could not be sent'); }
    };
    ws.onmessage = (e) => {
      let m;
      try { m = JSON.parse(typeof e.data === 'string' ? e.data : Buffer.from(e.data).toString()); }
      catch { return fail('OpenAI realtime returned an invalid event'); }
      if (m.type === 'response.output_audio.delta') chunks.push(Buffer.from(m.delta, 'base64'));
      else if (m.type === 'error') fail(`OpenAI realtime error${m.error?.code ? ` (${String(m.error.code).slice(0, 60)})` : ''}`);
      else if (m.type === 'response.done') {
        if (m.response?.status !== 'completed') return fail(`OpenAI realtime response ${m.response?.status}`);
        clearTimeout(timer);
        resolve(m.response?.usage || null);
        close();
      }
    };
    ws.onerror = () => fail('OpenAI realtime connection failed');
    ws.onclose = () => { clearTimeout(timer); reject(failure('OpenAI realtime connection closed')); };
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
}

/**
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
  const what = 'Azure transcription';
  const { res, text } = await post(what, url, { headers: { 'api-key': key }, body: form }, fetchImpl);
  if (!res.ok) throw new OpenAiError(`${what} returned HTTP ${res.status}${res.status >= 500 ? ` (${UNKNOWN_OUTCOME})` : ''}`, res.status);
  return parsed(what, text);
}

/** Vision over sampled frames with a strict JSON schema. Returns { json, usage, text }. */
export async function visionJson({ model, system, instructions, frames, schema, schemaName = 'verdict', detail = 'high', fetchImpl }) {
  const content = [{ type: 'input_text', text: instructions }];
  for (const f of frames) {
    content.push({ type: 'input_text', text: `Frame ${f.label} (t=${f.t}s)` });
    content.push({ type: 'input_image', image_url: f.dataUrl, detail });
  }
  const body = await call('/responses', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model, max_output_tokens: 6000,
      input: [{ role: 'system', content: [{ type: 'input_text', text: system }] }, { role: 'user', content }],
      text: { format: { type: 'json_schema', name: schemaName, schema, strict: true } },
    }),
  }, { fetchImpl });
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
  const json = await call('/responses', { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, { fetchImpl });
  const text = json.output_text ?? (json.output || []).flatMap((o) => o.content || []).filter((c) => c.type === 'output_text').map((c) => c.text).join('');
  return { text, usage: json.usage || null, model: json.model || m, cachedTokens: json.usage?.input_tokens_details?.cached_tokens ?? 0 };
}

/** File transcription with gpt-transcribe (text only, no word timestamps). */
export async function transcribeText(file, { model = OPENAI_MODELS.transcribe, fetchImpl } = {}) {
  const form = new FormData();
  form.append('model', model);
  form.append('file', new Blob([readFileSync(file)]), basename(file));
  const json = await call('/audio/transcriptions', { body: form }, { fetchImpl });
  return { text: json.text || '', usage: json.usage || null, model };
}

/** Free moderation check for text and images before publishing generated media. */
export async function moderate(input, { fetchImpl } = {}) {
  const json = await call('/moderations', { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: OPENAI_MODELS.moderation, input }) }, { fetchImpl });
  return { flagged: (json.results || []).some((r) => r.flagged), results: json.results || [] };
}
