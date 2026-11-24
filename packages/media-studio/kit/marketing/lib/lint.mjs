// Film-mode aware lint. Verified assertions require evidence; fictional and
// envisioned scenes may be fully synthetic if their representation is clear.
// banned phrases, invented figures, forbidden names, people/children b-roll and voice-policy violations stop the run
// before any paid provider is contacted.
import { existsSync, readFileSync } from 'node:fs';
import { realpathSync } from 'node:fs';
import { extname, isAbsolute, join, resolve, sep } from 'node:path';
import { validate } from './schema.mjs';
import { inspectNarrativeArc, productNames } from './narrative.mjs';
import { beatIsFactual, creativeMode, mentions } from './creative-modes.mjs';
import { withProductProfile } from './product-profile.mjs';
import { FILM_TYPES, rolesOf } from './story-profiles.mjs';
import { fileSha, readJson, sentences, sha256, words } from './util.mjs';

export const NARRATION_IMPORT_SCHEMA = 'media-studio/narration-import/1';
export const SYNTHETIC_SOURCES = ['assemblyai', 'deepgram', 'azure', 'openai', 'elevenlabs'];
/** The manifest line for a beat: a line naming this cut wins over one that names no cut. */
export function importLineFor(manifest, cutId, beatId) {
  const lines = (Array.isArray(manifest?.lines) ? manifest.lines : []).filter((l) => l.beatId === beatId && (l.cut === undefined || l.cut === cutId));
  return lines.find((l) => l.cut === cutId) || lines[0] || null;
}

/**
 * Whether the spec's ask (spec.cta) is mandatory. Undeclared film type: yes, as it always was. Declared on the spec (and per
 * cut): only a film type with a cta slot (product-marketing, founder-pitch) needs one. An unknown type counts as undeclared.
 */
export function ctaRequired(spec) {
  const cuts = Array.isArray(spec.cuts) && spec.cuts.length ? spec.cuts : [{}];
  const types = cuts.map((c) => c.filmType || spec.filmType);
  if (types.some((t) => !t || !FILM_TYPES[t])) return true;
  return types.some((t) => FILM_TYPES[t].slots.includes('cta'));
}

/** True when `real` is one of the roots or lies under one. Roots that cannot be resolved fall back to their plain path. */
export function insideAny(real, roots) {
  return roots.filter(Boolean).some((r) => {
    let root = resolve(r);
    try { root = realpathSync(root); } catch { /* not created yet */ }
    return real === root || real.startsWith(root + sep);
  });
}

const CENTRAL = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Chicago', hourCycle: 'h23', hour: '2-digit', minute: '2-digit' });
/** The end of a calendar day in US Central: the first instant of the next day there. */
export function endOfDayCentral(date) {
  const [y, m, d] = date.split('-').map(Number);
  const next = Date.UTC(y, m - 1, d + 1);
  for (const hours of [6, 5]) {
    const at = next + hours * 3600000;
    const parts = Object.fromEntries(CENTRAL.formatToParts(at).map((p) => [p.type, p.value]));
    if (parts.hour === '00' && parts.minute === '00') return at;
  }
  return next + 6 * 3600000;
}
const DAY_MS = 86400000;
const OFFSET_END = /(Z|[+-]\d{2}:?\d{2})$/i;
/** Parse a consent date: a date alone is the end of that day in US Central; a date-time must carry an offset. */
function consentInstant(value, name) {
  const s = String(value ?? '').trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) { const at = name === 'validUntil' ? endOfDayCentral(s) : Date.parse(s); return Number.isFinite(at) ? { at, dateOnly: Date.parse(s) } : { problem: `consent.${name} is not a date` }; }
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) {
    if (!OFFSET_END.test(s)) return { problem: `consent.${name} is a date-time without an explicit offset (Z or +hh:mm)` };
    const at = Date.parse(s);
    return Number.isFinite(at) ? { at } : { problem: `consent.${name} is not a date` };
  }
  return { problem: `consent.${name} is not a date` };
}

/** Why a consent record cannot stand for an imported owner clone, or null. */
export function consentProblem(consent, { now = Date.now(), voiceName } = {}) {
  if (!consent || typeof consent !== 'object') return 'consent {subject, approvedBy, approvedAt, validUntil} is required on the manifest or on every narrated line';
  if (!String(consent.approvedBy || '').trim()) return 'consent.approvedBy is empty';
  const subject = String(consent.subject || '').trim();
  if (!subject) return 'consent.subject is empty';
  if (subject !== String(voiceName || '').trim()) return `consent.subject "${subject}" must equal voice.name "${String(voiceName || '').trim()}"`;
  const approvedField = consent.approvedAt ?? consent.recordedAt;
  if (!approvedField) return 'consent needs approvedAt (or recordedAt): when the subject agreed';
  const approved = consentInstant(approvedField, consent.approvedAt ? 'approvedAt' : 'recordedAt');
  if (approved.problem) return approved.problem;
  const until = consentInstant(consent.validUntil, 'validUntil');
  if (until.problem) return until.problem;
  // Two bare dates are compared as calendar days; the end-of-day rule applies only to the expiry check below.
  const span = approved.dateOnly !== undefined && until.dateOnly !== undefined ? until.dateOnly - approved.dateOnly : until.at - approved.at;
  if (span > 60 * DAY_MS) return 'consent.validUntil is more than 60 days after approvedAt';
  if (until.at < now) return `consent expired on ${consent.validUntil}`;
  return null;
}

const isCloneReceipt = (r) => Boolean(r) && (r.clone === true || r.visibility === 'private');
const exceptionOk = (e) => Boolean(e) && String(e.reason || '').trim() && String(e.approvedBy || '').trim();
/** Message when two entities disagree and no exception is recorded, else null. */
export function entityProblem(brandEntity, recordEntity, exception, what, recordName = 'record') {
  if (exceptionOk(exception)) return null;
  const anyway = 'record an entityException {reason, approvedBy} to use it anyway';
  if (!brandEntity) return `${what} is imported but brand.entity is missing; set brand.entity (abacare, mahumtech or personal) or ${anyway}`;
  if (!recordEntity) return `${what} cannot be attributed: the ${recordName} has no entity; add it or ${anyway}`;
  if (brandEntity === recordEntity) return null;
  return `${what} is for entity "${recordEntity}" but the brand is "${brandEntity}"; record an entityException {reason, approvedBy} to use it anyway`;
}

/**
 * Policy checks of an import manifest that the lint and the voice stage both apply (so --only voice cannot skip them):
 * lines shape, recording provenance, clone voices, owner consent and entity. Returns [{code, message, where}].
 */
export function importPolicyProblems(spec, manifest, brand, now = Date.now()) {
  const v = spec.voice;
  const out = [];
  const add = (code, message) => out.push({ code, message, where: 'voice' });
  if (!Array.isArray(manifest?.lines)) { add('voice-import', 'import manifest lines must be an array'); return out; }
  const narrated = [];
  for (const cut of normalizeCuts(spec)) for (const beat of cut.beats) if (beat.narration) narrated.push(importLineFor(manifest, cut.id, beat.id));
  const lines = narrated.filter(Boolean);
  if (v.source === 'recording') {
    if (!String(manifest.recordedBy || '').trim()) add('voice-import', 'a recording needs recordedBy (who recorded it) on the manifest');
    if (lines.some((l) => l.receipt?.provider)) add('voice-import', 'a recording line must not carry receipt.provider; only synthetic audio has a provider receipt');
  }
  if (lines.some((l) => isCloneReceipt(l.receipt)) && v.ownerVoice !== true) add('owner-voice', 'a clone or private voice is marked in the receipt, so voice.ownerVoice must be true under the owner consent route');
  if (v.ownerVoice === true) {
    if (v.source !== 'assemblyai') add('owner-voice', `only an assemblyai import may be an owner voice clone (this import is ${v.source})`);
    else {
      const manifestLevel = manifest.consent;
      const problem = manifestLevel ? consentProblem(manifestLevel, { now, voiceName: v.name })
        : lines.length && lines.every((l) => l.receipt?.consent) ? lines.map((l) => consentProblem(l.receipt.consent, { now, voiceName: v.name })).find(Boolean) || null
          : 'consent must sit on the manifest or on every narrated line';
      if (problem) add('owner-voice', `an imported AssemblyAI owner clone needs valid consent: ${problem}`);
    }
  }
  const entity = entityProblem(brand?.entity, manifest.entity, v.entityException, 'this narration', 'manifest');
  if (entity) add('entity', entity);
  return out;
}

const STILL_TYPES = { '.png': 'png', '.jpg': 'jpg', '.jpeg': 'jpg', '.webp': 'webp' };
const VIDEO_EXT = new Set(['.mp4', '.mov', '.webm', '.m4v', '.mkv', '.avi', '.gif']);
function stillKind(bytes) {
  if (bytes.length > 12 && bytes[0] === 0x89 && bytes.toString('ascii', 1, 4) === 'PNG') return 'png';
  if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'jpg';
  if (bytes.length > 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  return null;
}
/** Problem with a b-roll still on disk (compose is image-only), or null. A supplied sha256 must match. */
function stillProblem(file, specDir, io, sha) {
  const abs = isAbsolute(file) ? file : resolve(specDir || process.cwd(), file);
  if (!io.exists(abs)) return `b-roll file not found: ${abs}`;
  let real = abs;
  try { real = realpathSync(abs); } catch { /* io is injected; fall back to the plain path */ }
  if (!insideAny(real, [specDir || process.cwd(), resolve(specDir || process.cwd(), '..')])) return `b-roll file ${file} lies outside the spec folder and its workspace`;
  const ext = extname(file).toLowerCase();
  if (VIDEO_EXT.has(ext)) return `b-roll file ${file} is a video; compose is image-only, so supply a still image (png, jpg or webp)`;
  if (!STILL_TYPES[ext]) return `b-roll file ${file} must be a png, jpg or webp still (compose is image-only)`;
  let bytes;
  try { bytes = readFileSync(abs); } catch (e) { return `b-roll file ${abs} cannot be read: ${e.message}`; }
  const kind = stillKind(bytes);
  if (!kind) return `b-roll file ${file} is not a png, jpg or webp image (compose is image-only)`;
  if (kind !== STILL_TYPES[ext]) return `b-roll file ${file} has a .${ext.slice(1)} name but holds ${kind} data`;
  if (sha && sha256(bytes) !== sha) return `b-roll file ${file} does not match its sha256 (changed after it was recorded)`;
  return null;
}

/** Narration that talks about the demo data, the film or its making instead of the viewer's problem. */
export const FLUFF = /\b(synthetic|sample data|demo data|in this (?:video|film|demo)|welcome to|let's take a look|as you can see)\b/i;
export const WORDS_PER_SECOND = 2.55; // ~153 wpm, the brisk end of measured product narration; an estimate, corrected by the real voice timing
export const LEAD_SECONDS = 0.3;
export const TAIL_SECONDS = 0.45;

const NEGATION = /\b(no|not|nothing|never|without|none|neither|nor|n't|cannot)\b/i;

// Claim wording that no product may use about itself without substantiation
// stays on by default for factual beats. Wording that belongs to one industry
// is a named policy a product's brand file opts into (brand.claimPolicies).
const KNOWN_BANNED = [
  { id: 'sent-to-payer', pattern: '\\b(submit(?:s|ted|ting)?|sen[dt]s?|sending|transmit(?:s|ted|ting)?|file[ds]?)\\b[^.!?]{0,40}\\b(payers?|insurers?|insurance)\\b', flags: 'i', unlessNegated: true, reason: 'Never imply submission to a payer; say only what a claim with evidence states.' },
  { id: 'payer-outcome', pattern: '\\b(approved|paid|reimbursed|accepted)\\s+(?:by\\s+)?(?:the\\s+|a\\s+)?(payers?|insurers?)\\b|\\bget paid\\b|\\bpaid faster\\b|\\bfewer denials\\b|\\breduces? denials\\b|\\bno denials\\b', flags: 'i', unlessNegated: true, reason: 'No payer outcome may be implied.' },
  { id: 'guarantee', pattern: '\\bguarantee[sd]?\\b', flags: 'i', reason: 'No guarantees.' },
  { id: 'hipaa-status', pattern: '\\bHIPAA[\\s-]*(certified|compliant|approved)\\b', flags: 'i', reason: 'HHS recognizes no HIPAA certification; state only evidenced facts.' },
  { id: 'superlative', pattern: '(#1|\\bnumber one\\b|\\bbest[- ]in[- ]class\\b|\\bindustry[- ]leading\\b|\\bworld[- ]class\\b)', flags: 'i', reason: 'Unsubstantiated superlative.' },
  { id: 'testimonial', pattern: '\\b(testimonials?|customers? (?:say|love|trust)|trusted by|loved by)\\b', flags: 'i', reason: 'No testimonials or customer praise.' },
  { id: 'comparative', pattern: '\\b(better than|faster than|cheaper than|unlike)\\b', flags: 'i', reason: 'No comparative claims without substantiation.' },
];

const bannedById = (...ids) => KNOWN_BANNED.filter((b) => ids.includes(b.id));
/** Applies to every product's factual claims. */
export const DEFAULT_BANNED = bannedById('guarantee', 'superlative', 'testimonial', 'comparative');
/** Industry policies a brand file opts into by name. */
export const CLAIM_POLICIES = Object.freeze({
  'healthcare-payer': bannedById('sent-to-payer', 'payer-outcome', 'hipaa-status'),
});
/** The full healthcare marketing list, for a brand file that prefers to carry it inline. */
export const HEALTHCARE_BANNED = [...CLAIM_POLICIES['healthcare-payer'], ...DEFAULT_BANNED];

const PEOPLE = /\b(person|people|man|woman|men|women|adult|face|faces|portrait|doctor|nurse|therapist|clinician|coordinator|administrator|owner|parent|parents|family|families|human|hands?)\b/i;
const PROTECTED_PEOPLE = /\b(child|children|kid|kids|toddler|baby|boy|girl|minor|minors|patient|patients|student|students|infant|infants)\b/i;
const FAKE_PRODUCT = /\b(dashboard|software (?:screen|interface)|app(?:lication)? (?:screen|interface)|medical chart|patient record|claim form|billing screen)\b/i;
const CELEBRITY = /\b(morgan freeman|attenborough|mcconaughey|michael caine|sound[- ]?alike|in the style of|sounds? like|impersonat\w*)\b/i;
const NUMBER_WORDS = /\b(zero|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|percent)\b/gi;
const NUMBER_TOKEN = /\$\s?\d[\d,.]*|\b\d[\d,.]*\s?%?/g;
const STOP = new Set('a an the and or but so if then of to in on at by for from with without into as is are was were be been it its this that these those you your we our they their his her not no nothing before after when while who what which how why do does did done can could will would should may might must just only also than there here has have had having i me my us them'.split(' '));

const norm = (s) => String(s).toLowerCase().replace(/[’']/g, "'").replace(/[^a-z0-9$%']+/g, ' ').trim();
const content = (s) => norm(s).split(' ').filter((w) => w && !STOP.has(w));

export function normalizeCuts(spec) {
  if (Array.isArray(spec.cuts) && spec.cuts.length) return spec.cuts;
  return [{ id: 'main', ratios: spec.ratios || [], targetSeconds: spec.targetSeconds, beats: spec.beats || [], ...(spec.finalHoldSeconds !== undefined ? { finalHoldSeconds: spec.finalHoldSeconds } : {}) }];
}

export function estimateBeatSeconds(beat) {
  const n = words(beat.narration || '').length;
  if (!n) return Number(beat.minSeconds || 2);
  return Math.max(Number(beat.minSeconds || 0), LEAD_SECONDS + n / WORDS_PER_SECOND + TAIL_SECONDS);
}

/** The closing hold a cut declares after its last spoken word: cut.finalHoldSeconds, else spec.finalHoldSeconds, else 0. */
export function holdSeconds(cut, spec) {
  const hold = Number(cut?.finalHoldSeconds ?? spec?.finalHoldSeconds ?? 0);
  return hold > 0 ? hold : 0;
}

export function estimateCutSeconds(cut, spec) {
  return cut.beats.reduce((sum, beat) => sum + estimateBeatSeconds(beat), 0) + holdSeconds(cut, spec);
}

function resolveBannedPatterns(brand, factual) {
  // Default and industry policies govern factual statements. A line of
  // dialogue in a declared fiction is not a product assertion; the brand's own
  // list still applies to it, because a brand may forbid a phrase everywhere.
  const policies = factual ? (brand?.claimPolicies || []).flatMap((name) => CLAIM_POLICIES[name] || []) : [];
  const seen = new Set();
  return [...(factual ? DEFAULT_BANNED : []), ...policies, ...(brand?.bannedPhrases || [])]
    .filter((b) => (seen.has(b.id) ? false : seen.add(b.id)))
    .map((b) => ({ ...b, regex: new RegExp(b.pattern, b.flags || 'i') }));
}

/** First banned-phrase hit in `text`, honoring unlessNegated at sentence level. */
export function bannedHits(text, banned) {
  const hits = [];
  for (const sentence of sentences(text)) {
    for (const b of banned) {
      const m = b.regex.exec(sentence);
      if (!m) continue;
      if (b.unlessNegated && NEGATION.test(sentence.slice(0, m.index + m[0].length))) continue;
      hits.push({ id: b.id, match: m[0], sentence, reason: b.reason });
    }
  }
  return hits;
}

function numericTokens(text) {
  const out = [];
  for (const m of String(text).matchAll(NUMBER_TOKEN)) out.push(m[0].trim().toLowerCase());
  for (const m of String(text).matchAll(NUMBER_WORDS)) out.push(m[0].toLowerCase());
  return out;
}

function claimCovers(claim, text) {
  const t = norm(text);
  if (!t) return true;
  for (const phrase of claim.phrases || []) {
    const p = norm(phrase);
    if (p && t.includes(p)) return true;
  }
  const a = new Set(content(text));
  const b = new Set(content(claim.text));
  if (!a.size) return true;
  let hit = 0;
  for (const w of a) if (b.has(w)) hit++;
  return hit / a.size >= 0.6;
}

function claimMentions(claims, token) {
  const re = new RegExp(`(^|[^a-z0-9])${token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^a-z0-9])`, 'i');
  return claims.some((c) => re.test(c.text) || (c.phrases || []).some((p) => re.test(p)));
}

function defaultIo(specDir) {
  return {
    specDir,
    exists: (p) => existsSync(p),
    readJson: (p) => readJson(p),
    readText: (p) => readFileSync(p, 'utf8'),
  };
}

export function checkEvidence(claim, io) {
  const ev = String(claim.evidence || '');
  const base = io.specDir || process.cwd();
  const abs = (p) => (isAbsolute(p) ? p : resolve(base, p));
  if (ev.startsWith('approved:')) return ev.slice(9).trim().length >= 4 ? null : 'approved: evidence needs a named source';
  if (ev.startsWith('file:')) {
    const m = /^file:(.+?)(?::(\d+))?$/.exec(ev);
    if (!m) return 'file: evidence must be file:<path>[:line]';
    const path = abs(m[1].trim());
    if (!io.exists(path)) return `evidence file not found: ${path}`;
    if (m[2]) {
      const lines = io.readText(path).split(/\r?\n/).length;
      if (Number(m[2]) > lines) return `evidence line ${m[2]} is beyond the end of ${path} (${lines} lines)`;
    }
    return null;
  }
  if (ev.startsWith('clip:')) {
    const m = /^clip:(.+?)#([A-Za-z0-9_-]+)@([0-9.]+)-([0-9.]+)$/.exec(ev);
    if (!m) return 'clip: evidence must be clip:<sourceJob>#<clipId>@<t0>-<t1>';
    const receiptPath = join(abs(m[1].trim()), 'capture', 'receipt.json');
    if (!io.exists(receiptPath)) return `capture receipt not found: ${receiptPath}`;
    const clip = io.readJson(receiptPath).clips?.[m[2]];
    if (!clip) return `clip ${m[2]} is not in ${receiptPath}`;
    if (clip.valid === false) return `clip ${m[2]} is marked invalid in its receipt`;
    if (Number(m[4]) > Number(clip.clipSeconds) + 0.05 || Number(m[3]) >= Number(m[4])) return `clip range ${m[3]}-${m[4]} is outside the ${clip.clipSeconds}s capture`;
    return null;
  }
  return 'evidence must start with file:, clip: or approved:';
}

function lintSchemas(spec, brand, options, err) {
  const adSchema = options.adSchema;
  if (adSchema) for (const m of validate(adSchema, spec)) err('schema', m);
  if (options.brandSchema && brand) for (const m of validate(options.brandSchema, brand)) err('brand-schema', m);
}

function lintClaims(spec, io, err) {
  const claimsById = new Map();
  for (const c of spec.claims) {
    if (claimsById.has(c.id)) err('claim-duplicate', `duplicate claim id ${c.id}`, c.id);
    claimsById.set(c.id, c);
    const problem = checkEvidence(c, io);
    if (problem) err('evidence', `${c.id}: ${problem}`, c.id);
  }
  return claimsById;
}

function createTextScanner(brand, spec, err) {
  for (const name of brand?.claimPolicies || []) if (!CLAIM_POLICIES[name]) err('claim-policy', `unknown brand.claimPolicies entry "${name}". Known: ${Object.keys(CLAIM_POLICIES).join(', ')}.`, 'brand');
  const factualBanned = resolveBannedPatterns(brand, true);
  const fictionBanned = resolveBannedPatterns(brand, false);
  const forbidden = (brand?.forbiddenNames || []).map((n) => ({ name: n, re: new RegExp(`(^|[^A-Za-z0-9])${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^A-Za-z0-9])`, 'i') }));
  return (text, where, factual = true) => {
    for (const h of bannedHits(text, factual ? factualBanned : fictionBanned)) err('banned-phrase', `"${h.match}" (${h.id}): ${h.reason || 'banned'} — "${h.sentence}"`, where);
    for (const f of forbidden) if (f.re.test(text)) err('forbidden-name', `names "${f.name}", which must never appear in an ad`, where);
  };
}

// The manifest named by the same setting the speech provider reads, following a correction to its hash-bound parent.
function manifestVoiceId(path) {
  if (!path || !isAbsolute(path)) return null;
  try {
    let manifest = readJson(path);
    if (manifest.kind === 'elevenlabs-project-delivery-correction-v1') {
      const parent = manifest.parent_authorization;
      if (fileSha(parent.path) !== parent.sha256) return null;
      manifest = readJson(parent.path);
    }
    return manifest.kind === 'elevenlabs-owner-authorized-project-epoch-v2' ? manifest.voice_id : null;
  } catch {
    return null;
  }
}

/** The import manifest for lint: parsed, or an error already raised. Checks shape, source and per-beat text coverage. */
function lintImportManifest(spec, v, io, err) {
  if (!v.source) err('voice-import', 'voice.source is required when voice.provider is import (assemblyai, deepgram, azure, openai, elevenlabs or recording)', 'voice');
  if (!v.manifest) { err('voice-import', 'voice.manifest is required when voice.provider is import', 'voice'); return null; }
  if (isAbsolute(v.manifest)) { err('voice-import', 'voice.manifest must be a path relative to the spec folder', 'voice'); return null; }
  const path = resolve(io.specDir || process.cwd(), v.manifest);
  if (!io.exists(path)) { err('voice-import', `import manifest not found: ${path}`, 'voice'); return null; }
  let manifest;
  try { manifest = io.readJson(path); } catch (e) { err('voice-import', `import manifest is not valid JSON: ${e.message}`, 'voice'); return null; }
  if (manifest.schema !== NARRATION_IMPORT_SCHEMA) err('voice-import', `import manifest schema must be ${NARRATION_IMPORT_SCHEMA}`, 'voice');
  if (!Array.isArray(manifest.lines)) { err('voice-import', 'import manifest lines must be an array', 'voice'); return manifest; }
  if (v.source && manifest.source !== v.source) err('voice-import', `import manifest source "${manifest.source}" does not match voice.source "${v.source}"`, 'voice');
  for (const cut of normalizeCuts(spec)) for (const beat of cut.beats) {
    if (!beat.narration) continue;
    const line = importLineFor(manifest, cut.id, beat.id);
    if (!line) err('voice-import', `import manifest has no line for narrated beat ${cut.id}/${beat.id}`, `${cut.id}/${beat.id}`);
    else if (line.textSha256 !== sha256(beat.narration)) err('voice-import', `narration of ${cut.id}/${beat.id} changed since its audio was made (textSha256 differs); make that line again`, `${cut.id}/${beat.id}`);
  }
  return manifest;
}

function lintVoice(spec, err, warn, options, io) {
  const v = spec.voice;
  const manifest = options.authorizationManifest ?? process.env.MVG_ELEVENLABS_AUTHORIZATION;
  const isImport = v.provider === 'import';
  const importManifest = isImport ? lintImportManifest(spec, v, io, err) : null;
  const policy = importManifest && Array.isArray(importManifest.lines) ? importPolicyProblems(spec, importManifest, options.brand, options.now ?? Date.now()) : [];
  for (const p of policy) err(p.code, p.message, p.where);
  if (isImport && v.source === 'recording' && v.aiGenerated === true) err('voice-import', 'a recording is not AI-generated; remove voice.aiGenerated or set it to false', 'voice');
  if (isImport && v.source && v.source !== 'recording' && v.aiGenerated === false) err('voice-import', `${v.source} narration is AI-generated; voice.aiGenerated cannot be false`, 'voice');
  if (isImport && v.source !== 'recording' && !String(v.disclosure || '').trim()) err('disclosure', `Imported ${v.source || 'synthetic'} narration is AI-generated and needs a stated AI-voice disclosure`, 'voice');
  let ownerClone = v.ownerVoice === true && v.provider === 'elevenlabs' && Boolean(v.voiceId) && manifestVoiceId(manifest) === v.voiceId;
  let ownerProblem = "marketing narration is the owner voice clone only under that job's owner manifest";
  // An import's owner clone is judged by importPolicyProblems above (consent, source, entity); it never needs the ElevenLabs manifest.
  if (v.ownerVoice === true && isImport && v.source === 'assemblyai' && !policy.some((p) => p.code === 'owner-voice')) ownerClone = true;
  if (v.ownerVoice === true && !ownerClone && !isImport) err('owner-voice', ownerProblem, 'voice');
  if ((!ownerClone && /\b(sh|sarosh)\b/i.test(v.name || '')) || CELEBRITY.test(`${v.name || ''} ${v.instructions || ''}`)) err('voice-policy', 'owner clone names and celebrity sound-alikes are not allowed', 'voice');
  if (ownerClone && !String(v.disclosure || '').trim()) err('disclosure', 'An owner voice clone requires a stated AI-voice disclosure', 'voice');
  if (v.provider === 'openai' && !String(v.disclosure || '').trim()) err('disclosure', 'OpenAI voices require a stated AI-voice disclosure (usage policy)', 'voice');
  if (v.provider === 'elevenlabs') {
    const s = v.settings || {};
    if (v.model.startsWith('eleven_v4')) {
      for (const k of ['style', 'speed', 'use_speaker_boost']) if (k in s) err('voice-settings', `eleven_v4 accepts only stability and similarity_boost; remove "${k}"`, 'voice');
      if (!s.apply_text_normalization) err('voice-settings', 'eleven_v4 requires settings.apply_text_normalization', 'voice');
    } else if (!s.apply_text_normalization) err('voice-settings', 'governed ElevenLabs speech requires settings.apply_text_normalization', 'voice');
    if (v.stitching && v.model === 'eleven_v3') err('voice-settings', 'request stitching is not available on eleven_v3', 'voice');
    if (!v.pronunciationDictionaries?.length) warn('pronunciation', 'no pronunciation dictionary: the product name may be mispronounced; the listen gate must confirm', 'voice');
  }
}

function lintMusic(music, err) {
  if (music && music.provider === 'elevenlabs') {
    if (!music.prompt) err('music', 'music.prompt is required when music.provider is elevenlabs', 'music');
    if (!music.licenseBasis) err('music', 'music.licenseBasis is required (Eleven Music terms limit paid-ad use by plan)', 'music');
    if (music.prompt && /\b(in the style of|sounds? like|reminiscent of|feat\.?|by [A-Z][a-z]+ [A-Z][a-z]+)\b/.test(music.prompt)) err('music', 'music prompts must not name artists, songs or labels', 'music');
  }
}

function lintLabelsAndCta(spec, brand, claimsById, err, warn, scanText) {
  if (!spec.cta && ctaRequired(spec)) err('cta-required', 'cta is required: this film type (or an undeclared filmType) ends on one ask. Declare a filmType that needs none, or add cta {text, url}.', 'cta');
  else if (!spec.cta && normalizeCuts(spec).some((c) => c.beats.some((b) => rolesOf(b).includes('cta')))) err('cta-required', 'a beat has the cta role but the spec has no cta {text, url} for the end card', 'cta');
  // What a film must disclose is the product's decision, recorded in its brand
  // file (brand.disclosure). Shared code names no industry: a health product
  // lists "synthetic" and "no phi" there, another product lists what it needs.
  const flat = (v) => String(v || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  const disclosure = brand?.disclosure;
  if (disclosure?.required && !String(spec.labels || '').trim()) err('label', `${brand.product || 'This product'} requires a disclosure line on every film (brand.disclosure); labels is empty.`, 'labels');
  for (const phrase of (disclosure?.required ? (disclosure.mustInclude || []) : [])) {
    if (!flat(spec.labels).includes(flat(phrase))) err('label', `labels must state "${phrase}" (required by ${brand.product || 'the product'}'s brand.disclosure)`, 'labels');
  }
  if (spec.syntheticData === true && !/\bsynthetic\b/i.test(spec.labels || '')) {
    err('label', 'syntheticData was declared but no synthetic-data notice appears in labels.', 'labels');
  }
  scanText(spec.labels || '', 'labels');
  if (spec.cta?.text) scanText(spec.cta.text, 'cta');
  if (brand?.urls?.demo && spec.cta?.url) {
    try { if (new URL(spec.cta.url).host !== new URL(brand.urls.demo).host) warn('cta-url', `cta.url host differs from brand demo host ${brand.urls.demo}`, 'cta'); }
    catch { err('cta-url', 'cta.url is not a valid URL', 'cta'); }
  }
  if (spec.cta?.claim && !claimsById.has(spec.cta.claim)) err('claim-missing', `cta.claim ${spec.cta.claim} is not a claim id`, 'cta');
  if (spec.cta && !spec.cta.claim && creativeMode(spec) === 'verified-demo') warn('cta-claim', 'cta has no claim id; its wording is not mapped to evidence', 'cta');
}

function lintBeatShape(beat, where, err) {
  if (beat.kind === 'ui' && !beat.ui) err('beat-shape', 'ui beats need a ui source clip', where);
  if (beat.kind === 'broll' && !beat.broll) err('beat-shape', 'broll beats need a broll block', where);
  if (beat.kind !== 'ui' && beat.ui) err('beat-shape', `${beat.kind} beats must not carry a ui clip`, where);
}

function lintBeatText(beat, where, claimsById, err, warn, scanText, mode, names) {
  const texts = [...sentences(beat.narration || ''), ...(beat.onScreenText ? [beat.onScreenText] : []), ...(beat.actionTitle ? [beat.actionTitle] : [])];
  const verified = beatIsFactual(beat, mode, names);
  // Claim wording is checked on every factual line and on every line that names the product, in any mode and
  // under any label: "guaranteed" said of the product is a claim even inside a story.
  for (const t of texts) scanText(t, where, verified || mentions(t, names));
  const fluff = FLUFF.exec(beat.narration || '');
  if (fluff && mode === 'verified-demo') err('narration-fluff', `narration spends words on "${fluff[0]}"; say what the viewer gains, and leave data disclosure to an end card`, where);
  if (beat.onScreenText && words(beat.onScreenText).length > 8) warn('on-screen-length', 'on-screen text longer than 8 words may not survive phone-size reading', where);
  const refs = (beat.claims || []).map(id => claimsById.get(id));
  (beat.claims || []).forEach(id => { if (!claimsById.has(id)) err('claim-missing', `beat references unknown claim ${id}`, where); });
  const known = refs.filter(Boolean);
  // A dramatic situation, envisioned interface or fictional patient journey
  // does not need evidence proving that it already happened. Real assertions
  // always keep the evidence gate, including within a hybrid film.
  if (verified && texts.length && !known.length) err('claim-unmapped', 'verified spoken or screen claim has no evidence reference', where);
  if (verified) for (const t of texts) {
    if (known.length && !known.some(c => claimCovers(c, t))) err('claim-uncovered', `"${t}" is not covered by any referenced claim`, where);
    for (const token of numericTokens(t)) if (!claimMentions(known, token)) err('figure-unsupported', `"${token}" in "${t}" is unsupported by this verified claim`, where);
  }
}

function lintBrollProducer(beat, where, err, io, brand) {
  const b = beat.broll;
  if (b.provider === 'elevenlabs-video') err('broll-unproducible', 'elevenlabs-video has no governed adapter, so this b-roll can never be produced; use openai-image, or import a still (provider import)', where);
  else if (b.provider === 'stock') {
    if (!b.file) err('broll-unproducible', 'stock b-roll needs broll.file (a licensed still); without it nothing can produce this shot', where);
    else { const problem = stillProblem(b.file, io.specDir, io, b.sha256); if (problem) err('broll-file', problem, where); }
  } else if (b.provider === 'import') {
    if (!b.file) err('broll-import', 'imported b-roll needs broll.file', where);
    if (!b.sha256) err('broll-import', 'imported b-roll needs broll.sha256, the hash of the exact still', where);
    if (!b.source) err('broll-import', 'imported b-roll needs broll.source (runware, azure, openai or licensed)', where);
    if (typeof b.aiGenerated !== 'boolean') err('broll-import', 'imported b-roll must state broll.aiGenerated (true or false)', where);
    else if (b.source && b.source !== 'licensed' && b.aiGenerated !== true) err('broll-import', `${b.source} stills are AI-generated; aiGenerated cannot be false`, where);
    if (b.receipt?.outputSha256 && b.sha256 && b.receipt.outputSha256 !== b.sha256) err('broll-import', 'broll.receipt.outputSha256 does not match broll.sha256', where);
    if (b.source && b.source !== 'licensed') {
      if (!b.receipt?.requestId) err('broll-import', `${b.source} stills need broll.receipt with the provider requestId`, where);
      if (b.receipt && b.receipt.provider !== b.source) err('broll-import', `broll.receipt.provider must be "${b.source}", the declared source`, where);
      if (b.receipt && !b.receipt.outputSha256) err('broll-import', 'broll.receipt.outputSha256 is required and must equal broll.sha256', where);
    }
    // A provider receipt is the record that names an entity; a licensed still with no receipt has none to check.
    const entity = b.receipt ? entityProblem(brand?.entity, b.receipt.entity, b.entityException, 'this still', 'receipt') : null;
    if (entity) err('entity', entity, where);
    if (b.file && b.sha256) { const problem = stillProblem(b.file, io.specDir, io, b.sha256); if (problem) err('broll-file', problem, where); }
  }
}

function lintBroll(beat, where, err, warn, scanText, mode, brand, io) {
  if (!beat.broll) return;
  lintBrollProducer(beat, where, err, io, brand);
  // Whether generated people may appear is the product's policy
  // (brand.generatedPeople: any, adults-only, none). The default allows them,
  // but in a film about the current product they must be classified, so a
  // viewer is never shown an invented person as a real customer or patient.
  const prompt = beat.broll.prompt || '';
  const actor = beat.broll.actor;
  const minor = PROTECTED_PEOPLE.test(prompt) || ['child', 'minor', 'teen', 'infant'].includes(actor?.ageGroup);
  const anyone = minor || PEOPLE.test(prompt) || Boolean(actor);
  const policy = brand?.generatedPeople || 'any';
  if (policy === 'none' && anyone) err('broll-people', `${brand.product || 'This product'}'s brand file allows no generated people (generatedPeople: none).`, where);
  else if (policy === 'adults-only' && minor) err('broll-people', `${brand.product || 'This product'}'s brand file allows generated adults only (generatedPeople: adults-only); this shot describes a minor or a patient.`, where);
  else if (anyone && mode === 'verified-demo' && !['fictional', 'illustrative'].includes(beat.truthStatus) && !actor?.kind) {
    err('representation', 'A generated person in a film about the current product must be classified (truthStatus fictional or illustrative, or broll.actor.kind) so they are never read as a real customer, patient or testimonial.', where);
  }
  // Synthetic humans, children, patients, clinics, realistic faces, and
  // invented future interfaces are legitimate creative subjects. No blur
  // and no adult-only restriction. Truth-status separates an envisioned
  // screen from measured present-day product proof.
  if (beat.broll.depictsProductUI && mode === 'verified-demo' && beat.truthStatus !== 'illustrative' && beat.truthStatus !== 'fictional') {
    err('representation', 'Generated product UI in a verified demo must be classified illustrative/fictional context, not passed off as current functional proof; choose hybrid or future-vision for proposed features.', where);
  }
  if (beat.broll.actor?.kind === 'licensed-performer' && !beat.broll.actor?.consentReference) {
    warn('actor-rights', 'A real performer should have appropriate consent/usage-rights documentation.', where);
  }
  if (!beat.broll.actor && /\b(performer|celebrity|real person|actual patient)\b/i.test(beat.broll.prompt || '')) {
    warn('actor-rights', 'Confirm depicted real-person rights or make the person explicitly fictional.', where);
  }
  if (mode === 'verified-demo' && beat.claims?.length) {
    warn('broll-claims', 'Generated scene footage is illustration, not proof of measured software behavior; keep real UI evidence for current-feature claims', where);
  }
  scanText(beat.broll.prompt || '', where, false);
  if (beat.broll.provider === 'stock') warn('stock', 'Record rights or source licensing for supplied footage', where);
}

function lintUi(beat, cut, where, io, err, warn) {
  if (beat.ui) {
    const receiptPath = join(isAbsolute(beat.ui.sourceJob) ? beat.ui.sourceJob : resolve(io.specDir || '.', beat.ui.sourceJob), 'capture', 'receipt.json');
    if (!io.exists(receiptPath)) err('clip-missing', `capture receipt not found: ${receiptPath}`, where);
    else {
      const clip = io.readJson(receiptPath).clips?.[beat.ui.clipId];
      if (!clip) err('clip-missing', `clip ${beat.ui.clipId} not in ${receiptPath}`, where);
      else {
        if (clip.valid === false) err('clip-invalid', 'clip is marked invalid in its capture receipt', where);
        const needsFocus = cut.ratios.some((r) => r !== '16x9') && Number(clip.events?.clicks || 0) > 0 && clip.recast !== 'noZoom';
        if (needsFocus && !beat.ui.focus?.length) err('focus-required', 'clip has clicks (Recast zoom): pointer coordinates cannot be trusted for a 4:5 / 9:16 crop; add ui.focus', where);
        if (beat.ui.trimEnd && Number(beat.ui.trimEnd) > Number(clip.clipSeconds) + 0.05) err('clip-range', `trimEnd ${beat.ui.trimEnd} is beyond the ${clip.clipSeconds}s clip`, where);
      }
    }
    if (beat.ui.freshness === 'recapture-recommended') warn('clip-stale', `recapture recommended: ${beat.ui.freshnessNote || 'the clip predates a product change on this screen'}`, where);
  }
}

function lintSfx(beat, where, err) {
  for (const s of beat.sfx || []) if (!/^action:|^at:|^start$|^end$/.test(s.cue)) err('sfx-cue', `unsupported cue ${s.cue}`, where);
}

function lintBeat(beat, cut, where, state) {
  lintBeatShape(beat, where, state.err);
  lintBeatText(beat, where, state.claimsById, state.err, state.warn, state.scanText, state.mode, state.names);
  lintBroll(beat, where, state.err, state.warn, state.scanText, state.mode, state.brand, state.io);
  lintUi(beat, cut, where, state.io, state.err, state.warn);
  lintSfx(beat, where, state.err);
}

function lintCut(cut, state) {
  const where = (id) => `${cut.id}/${id}`;
  for (const r of cut.ratios) { if (state.seenRatios.has(r)) state.err('ratio-repeat', `ratio ${r} appears in more than one cut`, cut.id); state.seenRatios.add(r); }
  const beatIds = new Set();
  for (const beat of cut.beats) {
    if (beatIds.has(beat.id)) state.err('beat-duplicate', `duplicate beat id ${beat.id}`, where(beat.id));
    beatIds.add(beat.id);
    lintBeat(beat, cut, where(beat.id), state);
  }
  for (const finding of inspectNarrativeArc(state.spec, cut, estimateBeatSeconds, { brand: state.brand })) {
    // A waived story rule is a logged decision, not a blocked job.
    if (finding.waived) state.warn('story-override', `${finding.rule} waived: ${finding.waived} (was: ${finding.message})`, finding.where);
    else state.err(finding.code, finding.message, finding.where, finding.rule);
  }
  const lastBeat = cut.beats[cut.beats.length - 1];
  if ((state.brand?.disclosure?.required || String(state.spec.voice?.disclosure || '').trim()) && lastBeat && lastBeat.kind !== 'card') state.err('disclosure-card', `cut ${cut.id} must end on a card: the film label and the AI-voice disclosure are drawn only on the closing card`, cut.id);
  const estimate = estimateCutSeconds(cut, state.spec);
  state.estimates.push({ cut: cut.id, estimateSeconds: Number(estimate.toFixed(1)), targetSeconds: cut.targetSeconds });
  if (estimate > cut.targetSeconds + 4) state.err('too-long', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target; trim the script before spending on voice`, cut.id);
  else if (estimate > cut.targetSeconds + 1.5) state.warn('long', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target`, cut.id);
  else if (estimate < cut.targetSeconds * 0.6) state.warn('short', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target`, cut.id);
  const hold = holdSeconds(cut, state.spec);
  if (state.music?.provider === 'elevenlabs' && state.music.lengthSeconds !== undefined && state.music.lengthSeconds < cut.targetSeconds + hold + 2) state.err('music-length', `music.lengthSeconds ${state.music.lengthSeconds} s is shorter than cut ${cut.id} (${cut.targetSeconds} s target${hold ? ` plus a ${hold} s final hold` : ''}) plus 2 s; the bed must outlast the program (the assets stage re-checks against the measured length)`, 'music');
  if (state.mode === 'verified-demo' && !cut.beats.some((b) => b.kind === 'ui')) state.err('no-ui', `verified demo ${cut.id} has no captured UI proof. Other film modes can use fully generated visuals.`, cut.id);
}

export function lintSpec(spec, brand, options = {}) {
  const errors = [];
  const warnings = [];
  const err = (code, message, where, rule) => errors.push(rule ? { code, rule, message, where } : { code, message, where });
  const warn = (code, message, where) => warnings.push({ code, message, where });
  const io = options.io || defaultIo(options.specDir);
  lintSchemas(spec, brand, options, err);
  if (errors.length) return { ok: false, errors, warnings, estimates: [] };
  brand = withProductProfile(brand, spec, options.productProfiles);

  const cuts = normalizeCuts(spec);
  const claimsById = lintClaims(spec, io, err);
  const scanText = createTextScanner(brand, spec, err);
  lintVoice(spec, err, warn, { ...options, brand }, io);
  const music = spec.music;
  lintMusic(music, err);
  lintLabelsAndCta(spec, brand, claimsById, err, warn, scanText);
  const state = { spec, brand, names: productNames(spec, brand), mode: creativeMode(spec), seenRatios: new Set(), claimsById, scanText, io, err, warn, music, estimates: [] };
  for (const cut of cuts) lintCut(cut, state);
  return { ok: errors.length === 0, errors, warnings, estimates: state.estimates };
}
