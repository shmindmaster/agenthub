#!/usr/bin/env node
// Vision QA on an encoded ad. Samples a frame every N seconds, sends the frames to an OpenAI vision model with a
// rubric, parses a strict JSON verdict and fails on any high-severity finding. It supplements, never replaces, the
// encoded-file gates and a full human watch: vision models miss small text, so every finding is evidence to check.
//
// CLI: node vision-qa.mjs <candidate.mp4> --spec <ad.json> --ratio 16x9 --out <report.json> [--brand brand.json]
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validate } from './lib/schema.mjs';
import { estimateVisionUsd, visionUsdFromUsage } from './lib/prices.mjs';
import { fileSha, readJson, round } from './lib/util.mjs';

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
      type: 'object', additionalProperties: false, required: ['labelPresentOnAllFrames', 'summary'],
      properties: { labelPresentOnAllFrames: { type: 'boolean' }, summary: { type: 'string' } },
    },
  },
};

export class VerdictError extends Error { constructor(m) { super(m); this.name = 'VerdictError'; } }

export function sampleTimes(durationSeconds, everySeconds = 1.5) {
  const out = [];
  for (let t = 0.4; t < durationSeconds - 0.2; t += everySeconds) out.push(round(t, 2));
  if (!out.length || durationSeconds - out[out.length - 1] > everySeconds * 0.6) out.push(round(Math.max(0.2, durationSeconds - 0.4), 2));
  return out;
}

export function buildInstructions({ spec, brand, ratio }) {
  const forbidden = (brand?.forbiddenNames || []).join(', ') || '(none)';
  const spoken = (spec.cuts?.flatMap((c) => c.beats) || spec.beats || []).map((b) => [b.narration, b.onScreenText].filter(Boolean).join(' | ')).filter(Boolean);
  return [
    `You are the visual QA reviewer for a ${ratio} marketing ad for ${spec.product}. Review each frame like a skeptical compliance editor.`,
    `The required persistent on-screen label is: "${spec.labels}". Report missing-label (high) for any frame where it is absent or illegible, and set overall.labelPresentOnAllFrames accordingly.`,
    `The product UI in the frames is real captured software on synthetic data. Do NOT report the product's own synthetic names or numbers as problems; DO report typos or garbled text in OVERLAY text (captions, headlines, label, call to action) as high.`,
    `Report unreadable-text (high for overlay text, medium for UI text) when text is too small, low-contrast or cut off to read on a phone held at arm's length.`,
    `Report banned-claim (high) for any overlay text asserting: submission or transmission to a payer, payer approval or payment outcomes, guarantees, HIPAA certification, testimonials, superlatives, invented percentages or dollar figures.`,
    `Report prospect-name (high) if any of these names appear anywhere in a frame: ${forbidden}.`,
    `Report caption-overlap (high) when captions or graphics cover the focal point of the UI (the highlighted row, the pointer, the control being acted on).`,
    `Report people-or-children (high) for any photographic or illustrated people, faces or children; fabricated-ui (high) for any dashboard, chart or screen that does not look like captured software.`,
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
  const labelOk = verdict.overall.labelPresentOnAllFrames === true;
  const reasons = blocking.map((f) => `${f.frame}: ${f.category} (${f.severity}) ${f.detail}`);
  if (!labelOk) reasons.push('overall: the synthetic label is not present on all frames');
  return { ok: blocking.length === 0 && labelOk, blocking: blocking.length, findings, labelPresentOnAllFrames: labelOk, reasons };
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
 * @param {Function} [o.frames] injected (candidate, times, dir) => frames; default ffmpeg
 */
export async function runVisionQa(o) {
  const model = o.brand?.vision?.model || 'gpt-5.6-sol';
  const every = o.spec?.qa?.visionEverySeconds || 1.5;
  const duration = o.duration ?? ffprobeDuration(o.candidate);
  const times = sampleTimes(duration, every);
  const frames = (o.frames || extractFramesFfmpeg)(o.candidate, times, o.framesDir || join(dirname(o.candidate), '.vision-frames'));
  const estimate = estimateVisionUsd(model, frames.length);
  o.ledger?.check('openai', estimate, 'vision QA');
  const vision = o.vision || (async (args) => (await import('./lib/providers/openai.mjs')).visionJson(args));
  const res = await vision({
    model, detail: o.brand?.vision?.detail || 'high', schema: VERDICT_SCHEMA, schemaName: 'ad_vision_verdict',
    system: 'You are a meticulous, skeptical visual QA reviewer. You only report what you can see.',
    instructions: buildInstructions({ spec: o.spec, brand: o.brand, ratio: o.ratio }),
    frames: frames.map(({ label, t, dataUrl }) => ({ label, t, dataUrl })),
  });
  const verdict = parseVerdict(res.text);
  const usd = res.usage ? visionUsdFromUsage(model, res.usage) : estimate;
  o.ledger?.charge({ stage: 'qa', provider: 'openai', service: 'vision', units: usd, estimated: !res.usage, ref: `${o.ratio}:${frames.length} frames` });
  const result = evaluate(verdict);
  return {
    generator: 'media-studio/mvg-vision-qa', model, ratio: o.ratio,
    candidate: { path: o.candidate, sha256: existsSync(o.candidate) ? fileSha(o.candidate) : null, durationSeconds: round(duration, 2) },
    sampled: frames.map(({ label, t }) => ({ label, t })), everySeconds: every, costUsd: round(usd, 4), ...result, verdict,
  };
}

// The deployed kit is reached through a link (%LOCALAPPDATA%\AgentHub\media-studio -> D:\Local-AI), so compare real paths.
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
  const report = await runVisionQa({ candidate: resolve(candidate), spec, brand, ratio });
  const out = resolve(flag('--out', 'vision-qa.json'));
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
  for (const r of report.reasons) console.error(`[vision-qa] ${r}`);
  console.log(JSON.stringify({ ok: report.ok, blocking: report.blocking, report: out }));
  process.exit(report.ok ? 0 : 1);
}
const __file = fileURLToPath(import.meta.url);
export const moduleDir = dirname(__file);
