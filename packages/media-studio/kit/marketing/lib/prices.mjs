// Conservative price estimates used BEFORE a paid call (budget check) and as the recorded cost when the provider
// returns no usage. Sources: playbook research 2026-10-20 (developers.openai.com pricing, elevenlabs.io/pricing).
// Estimates round up; actual spend is read from provider usage where the response carries it.

/** Per-image USD at 1536x1024 by quality (planning estimates from OPENAI_IMAGE_USD_PER_M; the ledger records real usage). */
const IMAGE_USD = {
  'gpt-image-2.6-flare': { low: 0.04, medium: 0.13, high: 0.19, xhigh: 0.29, max: 0.37 }, // from OPENAI_IMAGE_USD_PER_M and the token estimates below
  'gpt-image-2.6-sunburst': { low: 0.04, medium: 0.13, high: 0.19, xhigh: 0.29, max: 0.37 },
};

export function estimateImageUsd(model, quality = 'medium') {
  const row = IMAGE_USD[model] || IMAGE_USD['gpt-image-2.6-flare'];
  return row[quality] ?? row.high;
}

/** OpenAI speech (gpt-realtime-2.1-mini): about 1,200 audio tokens a minute at $20/1M, about $0.024 per minute (measured 2026-11-13). */
export function estimateOpenAiSpeechUsd(text) {
  const wordCount = String(text).split(/\s+/).filter(Boolean).length;
  return Math.max(0.002, (wordCount / 150) * 0.024);
}

/** Hosted word-timing transcription (gpt-transcribe): about $0.27 per audio hour. */
export function estimateWhisperUsd(seconds) {
  return Math.max(0.0005, (Math.ceil(seconds) / 3600) * 0.27);
}

/** Azure speech-to-text, USD per audio hour (owner-supplied rates). */
const STT_USD_PER_HOUR = { 'gpt-transcribe': 0.27 };
export function estimateSttUsd(model, seconds) {
  const perHour = STT_USD_PER_HOUR[model] ?? 0.27;
  return Math.max(0.0005, (Math.ceil(seconds) / 3600) * perHour);
}

const VISION_USD_PER_M = {
  'gpt-6-astra': { in: 10, out: 50 },
  'gpt-6.1-sol': { in: 2, out: 10 },
  'gpt-6.1-terra': { in: 1, out: 5 },
  'gpt-6-luna': { in: 0.1, out: 0.5 },
};

export function visionRates(model) {
  return VISION_USD_PER_M[model] || VISION_USD_PER_M['gpt-6-astra'];
}

/** Frames cost about 1,800 input tokens each at high detail; the verdict about 2,500 output tokens. */
export function estimateVisionUsd(model, frames) {
  const r = visionRates(model);
  return ((frames * 1800 + 1500) * r.in + 2500 * r.out) / 1e6;
}

export function visionUsdFromUsage(model, usage) {
  const r = visionRates(model);
  const i = usage?.input_tokens ?? usage?.prompt_tokens ?? 0;
  const o = usage?.output_tokens ?? usage?.completion_tokens ?? 0;
  return (i * r.in + o * r.out) / 1e6;
}

/** ElevenLabs speech: credits per character by model (live /v1/models character_cost_multiplier, 2026-10-20). */
const TTS_RATE = { eleven_v4: 1, eleven_v4_turbo: 0.5, eleven_v3: 1, eleven_multilingual_v2: 1, eleven_flash_v2_5: 0.5, eleven_turbo_v2_5: 0.5 };

/** Tight reservation: 1.2x the character estimate, rounded up (unsettled reservations count against the ledger ceiling). */
export function estimateTtsCredits(text, model) {
  const rate = TTS_RATE[model] ?? 1;
  return Math.ceil(String(text).length * rate * 1.2);
}

export function estimateSfxCredits(seconds) { return Math.max(200, Math.ceil(seconds * 40)); }
export function estimateMusicCredits(ms) { return Math.ceil((ms * 900 * 1.15) / 60000); }

// ---------------------------------------------------------------------------------------------------------------
// OpenAI direct API (OPENAI_API_KEY), price table revision 2026-11-13 (owner research, OpenAI API pricing pages).
// Estimates are reserved before a paid call; the ledger records actual spend from response usage when present.
// ---------------------------------------------------------------------------------------------------------------
export const OPENAI_PRICES_REVISION = '2026-11-13';
/** Text models, USD per 1M tokens. Batch and Flex halve both rates. Cache reads: 0.1x input (0.05x on Sol/Terra). */
export const OPENAI_TEXT_USD_PER_M = {
  'gpt-6-astra': { in: 10, out: 50, cacheRead: 0.1 },
  'gpt-6.1-sol': { in: 2, out: 10, cacheRead: 0.05 },
  'gpt-6.1-terra': { in: 1, out: 5, cacheRead: 0.05 },
  'gpt-6-luna': { in: 0.1, out: 0.5, cacheRead: 0.1 },
};
/** Image models (gpt-image-2.6 flare and sunburst share one token price), USD per 1M tokens. */
export const OPENAI_IMAGE_USD_PER_M = { textIn: 5, imageIn: 8, cachedTextIn: 1.25, cachedImageIn: 2, imageOut: 30 };
/**
 * Output tokens per image at 1536x1024 by quality. These are planning estimates, not sourced counts: the bill
 * depends on resolution, quality, complexity and edit inputs, so record the real usage.output_tokens after each call.
 */
const IMAGE_OUT_TOKENS_EST = { low: 1100, medium: 4200, high: 6200, xhigh: 9500, max: 12000 };
/** Realtime, USD per 1M tokens: audio in/out, text in/out, cached input. About 1,200 audio output tokens per minute of
 * speech (measured 2026-11-13). Source: developers.openai.com/api/docs/pricing, read 2026-11-14. */
export const OPENAI_REALTIME_USD_PER_M = {
  'gpt-realtime-2.1-mini': { in: 10, out: 20, textIn: 0.6, textOut: 2.4, cachedIn: 0.3, cachedTextIn: 0.06 },
  'gpt-realtime-2.1': { in: 32, out: 64, textIn: 4, textOut: 24, cachedIn: 0.4, cachedTextIn: 0.4 },
};
/** Billed USD from a realtime response.done usage block, every dimension priced. Null when usage is missing. */
export function realtimeUsdFromUsage(model, usage, rate) {
  if (!usage) return null;
  const r = rate ?? (OPENAI_REALTIME_USD_PER_M[model] || OPENAI_REALTIME_USD_PER_M['gpt-realtime-2.1']);
  const i = usage.input_token_details || {};
  const o = usage.output_token_details || {};
  const cached = i.cached_tokens_details || {};
  const cachedAudio = Number(cached.audio_tokens ?? 0);
  const cachedText = Number(cached.text_tokens ?? (i.cached_tokens && !cached.audio_tokens ? i.cached_tokens : 0));
  const audioIn = Math.max(0, Number(i.audio_tokens ?? 0) - cachedAudio);
  const textIn = Math.max(0, Number(i.text_tokens ?? 0) - cachedText);
  const usd = audioIn * r.in + textIn * r.textIn + cachedAudio * r.cachedIn + cachedText * r.cachedTextIn
    + Number(o.audio_tokens ?? 0) * r.out + Number(o.text_tokens ?? 0) * r.textOut;
  return usd / 1e6;
}
const REALTIME_OUT_TOKENS_PER_MIN_EST = 1200;
/** gpt-transcribe file transcription, USD per audio hour (same rate as the Azure deployment above). */
const OPENAI_STT_USD_PER_HOUR = { 'gpt-transcribe': 0.27 };

export function estimateOpenAiTextUsd(model, inTokens, outTokens, { batch = false, cachedInTokens = 0 } = {}) {
  const r = OPENAI_TEXT_USD_PER_M[model] || OPENAI_TEXT_USD_PER_M['gpt-6-astra'];
  const k = batch ? 0.5 : 1;
  const fresh = Math.max(0, inTokens - cachedInTokens);
  return k * (fresh * r.in + cachedInTokens * r.in * r.cacheRead + outTokens * r.out) / 1e6;
}
export function estimateOpenAiImageUsd(quality = 'medium', { promptTokens = 300, refImageTokens = 0, batch = false, size = '1536x1024' } = {}) {
  const out = IMAGE_OUT_TOKENS_EST[quality] ?? IMAGE_OUT_TOKENS_EST.high;
  const [w, h] = String(size).split('x').map(Number);
  const scale = w && h ? (w * h) / (1536 * 1024) : 1;
  const r = OPENAI_IMAGE_USD_PER_M;
  return (batch ? 0.5 : 1) * (promptTokens * r.textIn + refImageTokens * r.imageIn + out * scale * r.imageOut) / 1e6;
}
export function estimateOpenAiRealtimeSpeechUsd(text, model = 'gpt-realtime-2.1-mini') {
  const minutes = String(text).split(/\s+/).filter(Boolean).length / 150;
  const r = OPENAI_REALTIME_USD_PER_M[model] || OPENAI_REALTIME_USD_PER_M['gpt-realtime-2.1'];
  return Math.max(0.002, minutes * REALTIME_OUT_TOKENS_PER_MIN_EST * r.out / 1e6);
}
export function estimateOpenAiTranscribeUsd(seconds, model = 'gpt-transcribe') {
  return Math.max(0.0005, (Math.ceil(seconds) / 3600) * (OPENAI_STT_USD_PER_HOUR[model] ?? 0.27));
}
