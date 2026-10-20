// OpenAI REST client for mvg: images (gpt-image), speech (gpt-4o-mini-tts), word timing (whisper-1, the only OpenAI
// STT with word timestamps) and vision QA (Responses API with a JSON schema). The Sora Videos API was shut down on
// 2026-09-24; there is no OpenAI video call here. Requests carry only approved ad text and sampled frames.
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';

const BASE = 'https://api.openai.com/v1';

export class OpenAiError extends Error {
  constructor(message, status) { super(message); this.name = 'OpenAiError'; this.status = status; }
}

function apiKey() {
  const key = process.env.OPENAI_API_KEY;
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

export async function generateImage({ prompt, model = 'gpt-image-2', size = '1536x1024', quality = 'medium', fetchImpl }) {
  const res = await call('/images/generations', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, prompt, size, quality, n: 1, output_format: 'png' }),
  }, { fetchImpl });
  const json = await res.json();
  const b64 = json.data?.[0]?.b64_json;
  if (!b64) throw new OpenAiError('image response carried no image data');
  return { bytes: Buffer.from(b64, 'base64'), usage: json.usage || null, model, size, quality };
}

export async function speech({ text, voice, instructions, model = 'gpt-4o-mini-tts', format = 'mp3', fetchImpl }) {
  const res = await call('/audio/speech', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, voice, input: text, response_format: format, ...(instructions ? { instructions } : {}) }),
  }, { fetchImpl });
  return { bytes: Buffer.from(await res.arrayBuffer()), model, voice };
}

/** whisper-1 with word timestamps. Returns the raw verbose_json payload. */
export async function transcribeWords(file, { fetchImpl } = {}) {
  const form = new FormData();
  form.append('file', new Blob([readFileSync(file)]), basename(file));
  form.append('model', 'whisper-1');
  form.append('response_format', 'verbose_json');
  form.append('timestamp_granularities[]', 'word');
  form.append('language', 'en');
  const res = await call('/audio/transcriptions', { method: 'POST', body: form }, { fetchImpl });
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
