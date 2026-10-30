#!/usr/bin/env node
// Vision QA on an encoded ad. Samples frames for an injected local vision reviewer (Local AI is off: the default refuses
// before decoding), or explicit ledger-governed OpenAI, with a
// rubric, parses a strict JSON verdict and fails on any high-severity finding. It supplements, never replaces, the
// encoded-file gates and a full human watch: vision models miss small text, so every finding is evidence to check.
//
// CLI: node vision-qa.mjs <candidate.mp4> --spec <ad.json> --ratio 16x9 --out <report.json> [--brand brand.json]
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validate } from './lib/schema.mjs';
import { estimateVisionUsd, visionUsdFromUsage } from './lib/prices.mjs';
import { LOCAL_AI_OFF, fileSha, readJson, round } from './lib/util.mjs';

export const CATEGORIES = ['typo', 'unreadable-text', 'banned-claim', 'prospect-name', 'missing-label', 'caption-overlap', 'people-or-children', 'fabricated-ui', 'other'];
export const SEVERITIES = ['high', 'medium', 'low'];

export const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false, required: ['frames', 'overall'],
  properties: {
    frames: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false, required: ['label', 'issues'],
        properties: {
          label: { type: 'string' },
          issues: {
            type: 'array',
            items: {
              type: 'object', additionalProperties: false, required: ['category', 'severity', 'detail', 'evidence'],
              properties: { category: { enum: CATEGORIES }, severity: { enum: SEVERITIES }, detail: { type: 'string' }, evidence: { type: 'string' } },
            },
          },
        },
      },
    },
    overall: {
      type: 'object', additionalProperties: false, required: ['labelPresentWhereRequired', 'summary'],
      properties: { labelPresentWhereRequired: { type: 'boolean' }, summary: { type: 'string' } },
    },
  },
};

export class VerdictError extends Error { constructor(m) { super(m); this.name = 'VerdictError'; } }

export const CAPTION_MARGIN_SECONDS = 0.25;

/**
 * Frame times every `everySeconds`, nudged off caption transitions: a frame within `margin` seconds of a cue start or end
 * can catch a caption mid fade-in (every word transparent) and be misread as unreadable or incomplete. A sample moves forward
 * to the first clear time (then backward) within half the interval; if none exists it stays.
 */
export function sampleTimes(durationSeconds, everySeconds = 1.5, { cues = [], margin = CAPTION_MARGIN_SECONDS } = {}) {
  const near = (t) => cues.some((c) => Math.abs(t - c.startSec) < margin || Math.abs(t - c.endSec) < margin);
  const nudge = (t) => {
    if (!near(t)) return t;
    for (let d = 0.05; d <= everySeconds / 2 + 1e-9; d += 0.05) {
      for (const cand of [t + d, t - d]) if (cand > 0.1 && cand < durationSeconds - 0.1 && !near(cand)) return round(cand, 2);
    }
    return t;
  };
  const out = [];
  for (let t = 0.4; t < durationSeconds - 0.2; t += everySeconds) out.push(round(t, 2));
  if (!out.length || durationSeconds - out[out.length - 1] > everySeconds * 0.6) out.push(round(Math.max(0.2, durationSeconds - 0.4), 2));
  const moved = out.map(nudge);
  return moved.filter((t, i) => moved.indexOf(t) === i);
}

export function buildInstructions({ spec, brand, ratio }) {
  const forbidden = (brand?.forbiddenNames || []).join(', ') || '(none)';
  const spoken = (spec.cuts?.flatMap((c) => c.beats) || spec.beats || []).map((b) => [b.narration, b.onScreenText].filter(Boolean).join(' | ')).filter(Boolean);
  return [
    `You are the visual QA reviewer for a ${ratio} marketing ad for ${spec.product}. Review each frame like a skeptical compliance editor.`,
    `The required disclosure line is: "${spec.labels}". It belongs on the closing end card (the frame with the call to action), not over the product picture. Report missing-label (high) when an end-card frame lacks it or it is illegible there, and set overall.labelPresentWhereRequired accordingly (true when no end-card frame was sampled).`,
    `The product UI in the frames is real captured software on synthetic data. Do NOT report the product's own synthetic names or numbers as problems; DO report typos or garbled text in OVERLAY text (captions, headlines, label, call to action) as high.`,
    `Report unreadable-text (high for overlay text, medium for UI text) when text is too small, low-contrast or cut off to read on a phone held at arm's length.`,
    `Report banned-claim (high) for any overlay text asserting: submission or transmission to a payer, payer approval or payment outcomes, guarantees, HIPAA certification, testimonials, superlatives, invented percentages or dollar figures.`,
    `Report prospect-name (high) if any of these names appear anywhere in a frame: ${forbidden}.`,
    `Report caption-overlap (high) when captions or graphics cover the focal point of the UI (the highlighted row, the pointer, the control being acted on).`,
    `Report people-or-children (high) for photographic or illustrated people, faces or children ADDED by the ad (b-roll, overlays, backgrounds). Ignore the small profile avatars that are part of the captured product UI. Report fabricated-ui (high) for any dashboard, chart or screen that does not look like captured software.`,
    `The captions are 4-7 word chunks of ONE spoken sentence, shown one chunk at a time and highlighted word by word: a caption that is a fragment of a longer sentence is normal and is NOT a typo or an incomplete sentence. Sampled frames avoid caption transitions, but if a caption looks faded or partly transparent treat it as mid-animation and do not report it.`,
    `Every issue needs a one-sentence detail and a short evidence string quoting the visible text. If a frame has no issues return an empty list. Do not invent issues.`,
    `Approved overlay copy for reference (anything else on overlay is suspicious): ${spoken.join(' // ')} // ${spec.cta?.text || ''}`,
  ].join('\n');
}

export function parseVerdict(text) {
  const cleaned = String(text).trim().replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '');
  let json;
  try { json = JSON.parse(cleaned); } catch { throw new VerdictError('vision verdict is not valid JSON'); }
  const problems = validate(VERDICT_SCHEMA, json);
  if (problems.length) throw new VerdictError(`vision verdict does not match the schema: ${problems.slice(0, 3).join('; ')}`);
  return json;
}

/** Fail on any high-severity finding or a missing label on any frame. */
export function evaluate(verdict, { failOn = 'high' } = {}) {
  const rank = { high: 3, medium: 2, low: 1 };
  const threshold = rank[failOn];
  const findings = [];
  for (const f of verdict.frames) for (const i of f.issues) findings.push({ frame: f.label, ...i });
  const blocking = findings.filter((f) => rank[f.severity] >= threshold);
  const labelOk = verdict.overall.labelPresentWhereRequired === true;
  const reasons = blocking.map((f) => `${f.frame}: ${f.category} (${f.severity}) ${f.detail}`);
  if (!labelOk) reasons.push('overall: the synthetic-data disclosure is missing or illegible on the end card');
  return { ok: blocking.length === 0 && labelOk, blocking: blocking.length, findings, labelPresentWhereRequired: labelOk, reasons };
}

/**
 * Reviewer arbitration of vision findings. Honoured ONLY when the file names this exact candidate hash and a reviewer, and
 * only for items that name a finding (frame + category), carry verdict "false-positive" and a reason. mvg never writes this
 * file: a person who looked at the frames does. Returns the evaluation with arbitrated findings removed from `blocking`.
 */
export function applyArbitration(result, arbitration, candidateSha256) {
  const record = { file: !!arbitration, honoured: false, reviewer: arbitration?.reviewer ?? null, applied: [], ignored: [] };
  if (!arbitration) return { ...result, arbitration: record };
  if (arbitration.candidateSha256 !== candidateSha256) { record.ignored.push({ reason: 'arbitration is bound to a different candidate hash; ignored' }); return { ...result, arbitration: record }; }
  if (!String(arbitration.reviewer || '').trim()) { record.ignored.push({ reason: 'arbitration names no reviewer; ignored' }); return { ...result, arbitration: record }; }
  record.honoured = true;
  const items = Array.isArray(arbitration.items) ? arbitration.items : [];
  const used = new Set();
  const isBlocking = (f) => f.severity === 'high';
  for (const item of items) {
    const ok = item && item.verdict === 'false-positive' && String(item.reason || '').trim().length >= 8 && item.frame && item.category;
    if (!ok) { record.ignored.push({ ...item, reason: 'needs frame, category, verdict "false-positive" and a reason of at least 8 characters' }); continue; }
    const hits = result.findings.filter((f, i) => !used.has(i) && f.frame === item.frame && f.category === item.category);
    if (!hits.length && !(item.frame === 'overall' && item.category === 'missing-label')) { record.ignored.push({ ...item, reason: 'no such finding' }); continue; }
    result.findings.forEach((f, i) => { if (f.frame === item.frame && f.category === item.category) used.add(i); });
    record.applied.push({ frame: item.frame, category: item.category, reason: item.reason });
  }
  const remaining = result.findings.filter((f, i) => isBlocking(f) && !used.has(i));
  const labelArbitrated = record.applied.some((a) => a.frame === 'overall' && a.category === 'missing-label');
  const labelOk = result.labelPresentWhereRequired || labelArbitrated;
  const reasons = remaining.map((f) => `${f.frame}: ${f.category} (${f.severity}) ${f.detail}`);
  if (!labelOk) reasons.push('overall: the synthetic-data disclosure is missing or illegible on the end card');
  return { ...result, ok: remaining.length === 0 && labelOk, blocking: remaining.length, reasons, arbitration: record };
}

function ffprobeDuration(file) {
  return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file], { windowsHide: true }).toString());
}

export function extractFramesFfmpeg(candidate, times, dir, { maxWidth = 1080 } = {}) {
  mkdirSync(dir, { recursive: true });
  return times.map((t, i) => {
    const out = join(dir, `f${String(i + 1).padStart(2, '0')}.jpg`);
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-hwaccel', 'none', '-ss', String(t), '-i', candidate, '-frames:v', '1', '-vf', `scale='min(${maxWidth},iw)':-2`, '-q:v', '3', out], { windowsHide: true });
    return { label: `F${String(i + 1).padStart(2, '0')}`, t, path: out, dataUrl: `data:image/jpeg;base64,${readFileSync(out).toString('base64')}` };
  });
}

/**
 * @param {object} o
 * @param {string} o.candidate encoded mp4
 * @param {object} o.spec ad spec; o.brand brand file; o.ratio
 * @param {object} [o.ledger] CostLedger (budget-checked before the call, charged after)
 * @param {Function} [o.vision] injected (args) => { text, usage } for tests; default OpenAI Responses
 * @param {Function} [o.localVision] injected local reviewer (args) => { text | frameTexts, model }; no default (Local AI is off)
 * @param {Function} [o.frames] injected (candidate, times, dir) => frames; default ffmpeg
 */
export async function runVisionQa(o) {
  const provider = o.provider || o.brand?.vision?.provider || 'local';
  if (!['local', 'openai'].includes(provider)) throw new Error('vision provider must be local or explicit paid openai');
  if (provider === 'openai' && (typeof o.ledger?.check !== 'function' || typeof o.ledger?.charge !== 'function')) throw new Error('paid OpenAI vision requires a governed cost ledger; use mvg --stage qa');
  if (provider === 'local' && typeof o.localVision !== 'function') throw new Error(`local vision: ${LOCAL_AI_OFF}; or pass --vision-provider openai (paid, ledger-governed)`);
  let model = provider === 'openai' ? (o.brand?.vision?.model || 'gpt-5.6-sol') : null;
  const every = o.spec?.qa?.visionEverySeconds || 1.5;
  const candidateSha = existsSync(o.candidate) ? fileSha(o.candidate) : null;
  const duration = o.duration ?? ffprobeDuration(o.candidate);
  const times = sampleTimes(duration, every, { cues: o.cues || [] });
  const frames = (o.frames || extractFramesFfmpeg)(o.candidate, times, o.framesDir || join(tmpdir(), 'mvg-vision-frames', basename(o.candidate)));
  const estimate = provider === 'openai' ? estimateVisionUsd(model, frames.length) : 0;
  if (provider === 'openai') o.ledger.check('openai', estimate, 'vision QA');
  const vision = provider === 'local'
    ? o.localVision
    : (o.vision || (async (args) => (await import('./lib/providers/openai.mjs')).visionJson(args)));
  const res = await vision({
    model, detail: o.brand?.vision?.detail || 'high', schema: VERDICT_SCHEMA, schemaName: 'ad_vision_verdict',
    system: 'You are a meticulous, skeptical visual QA reviewer. You only report what you can see.',
    instructions: buildInstructions({ spec: o.spec, brand: o.brand, ratio: o.ratio }),
    frames: frames.map(({ label, t, dataUrl }) => ({ label, t, dataUrl })),
  });
  // Account for the completed paid call even if its verdict is malformed.
  const usd = provider === 'openai' ? (res.usage ? visionUsdFromUsage(model, res.usage) : estimate) : 0;
  if (provider === 'openai') o.ledger.charge({ stage: 'qa', provider: 'openai', service: 'vision', units: usd, estimated: !res.usage, ref: `${o.ratio}:${frames.length} frames` });
  if (provider === 'local') model = res.model || 'local';
  const parts = res.frameTexts?.map(parseVerdict);
  const verdict = parts ? {
    frames: parts.flatMap((p) => p.frames),
    overall: { labelPresentWhereRequired: parts.every((p) => p.overall.labelPresentWhereRequired), summary: parts.map((p) => p.overall.summary).join(' ') },
  } : parseVerdict(res.text);
  const labels = verdict.frames.map((f) => f.label);
  if (labels.length !== frames.length || new Set(labels).size !== frames.length || frames.some((f) => !labels.includes(f.label))) throw new VerdictError('vision verdict must cover every sampled frame exactly once');
  if (candidateSha && fileSha(o.candidate) !== candidateSha) throw new Error('candidate changed during vision QA');
  const result = applyArbitration(evaluate(verdict), o.arbitration || null, candidateSha);
  return {
    generator: 'media-studio/mvg-vision-qa', provider, model, ratio: o.ratio,
    candidate: { path: o.candidate, sha256: candidateSha, durationSeconds: round(duration, 2) },
    sampled: frames.map(({ label, t }) => ({ label, t })), everySeconds: every, costUsd: round(usd, 4), ...result, verdict,
  };
}

// The deployed kit is reached through a link (%LOCALAPPDATA%\AgentHub\media-studio -> MEDIA_STUDIO_ROOT, default D:\Media-Studio), so compare real paths.
function isMain() {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; }
}

// ---- CLI
if (isMain()) {
  const argv = process.argv.slice(2);
  const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
  const candidate = argv.find((a) => !a.startsWith('--') && /\.mp4$/i.test(a));
  const specPath = flag('--spec');
  const ratio = flag('--ratio');
  if (!candidate || !specPath || !ratio) { console.error('usage: node vision-qa.mjs <candidate.mp4> --spec <ad.json> --ratio 16x9|4x5|9x16 [--brand brand.json] [--out report.json]'); process.exit(2); }
  const spec = readJson(resolve(specPath));
  const brandPath = flag('--brand') || join(dirname(resolve(specPath)), '..', 'brand', 'brand.json');
  const brand = existsSync(brandPath) ? readJson(brandPath) : {};
  const arbPath = flag('--arbitration');
  const report = await runVisionQa({ candidate: resolve(candidate), spec, brand, ratio, provider: flag('--provider'), arbitration: arbPath && existsSync(arbPath) ? readJson(resolve(arbPath)) : null });
  const out = resolve(flag('--out', 'vision-qa.json'));
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
  for (const r of report.reasons) console.error(`[vision-qa] ${r}`);
  console.log(JSON.stringify({ ok: report.ok, blocking: report.blocking, report: out }));
  process.exit(report.ok ? 0 : 1);
}
const __file = fileURLToPath(import.meta.url);
export const moduleDir = dirname(__file);
