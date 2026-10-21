// Conservative price estimates used BEFORE a paid call (budget check) and as the recorded cost when the provider
// returns no usage. Sources: playbook research 2026-10-20 (developers.openai.com pricing, elevenlabs.io/pricing).
// Estimates round up; actual spend is read from provider usage where the response carries it.

/** gpt-image-2 per-image USD at 1536x1024 / 1024x1536 (flagged as ~1.0 for square) by quality. */
const IMAGE_USD = {
  'gpt-image-2': { low: 0.006, medium: 0.053, high: 0.211 },
  'gpt-image-2.5-flare': { low: 0.01, medium: 0.07, high: 0.25 }, // token-priced; padded estimate
  'gpt-image-2.5-sunburst': { low: 0.01, medium: 0.07, high: 0.25 },
  'gpt-image-1.5': { low: 0.013, medium: 0.05, high: 0.2 },
};

export function estimateImageUsd(model, quality = 'medium') {
  const row = IMAGE_USD[model] || IMAGE_USD['gpt-image-2.5-sunburst'];
  return row[quality] ?? row.high;
}

/** gpt-4o-mini-tts: $0.60/1M text in + $12/1M audio out tokens, about $0.015/min of speech; pad to $0.02/min. */
export function estimateOpenAiSpeechUsd(text) {
  const wordCount = String(text).split(/\s+/).filter(Boolean).length;
  return Math.max(0.002, (wordCount / 150) * 0.02);
}

/** whisper-1: $0.006 per audio minute (billed per second, rounded up to the second). */
export function estimateWhisperUsd(seconds) {
  return Math.max(0.0005, (Math.ceil(seconds) / 60) * 0.006);
}

const VISION_USD_PER_M = {
  'gpt-5.6-sol': { in: 4, out: 20 },
  'gpt-5.6-terra': { in: 2, out: 10 },
  'gpt-5.6-luna': { in: 0.2, out: 1.2 },
  'gpt-5.5': { in: 5, out: 30 },
  'gpt-5.4': { in: 2.5, out: 15 },
};

export function visionRates(model) {
  return VISION_USD_PER_M[model] || { in: 5, out: 30 };
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
