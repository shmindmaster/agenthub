// Film-mode aware lint. Verified assertions require evidence; fictional and
// envisioned scenes may be fully synthetic if their representation is clear.
// banned phrases, invented figures, forbidden names, people/children b-roll and voice-policy violations stop the run
// before any paid provider is contacted.
import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, join, resolve } from 'node:path';
import { validate } from './schema.mjs';
import { inspectNarrativeArc } from './narrative.mjs';
import { creativeMode, isConceptPresentation } from './creative-modes.mjs';
import { fileSha, readJson, sentences, words } from './util.mjs';

/** Narration that talks about the demo data, the film or its making instead of the viewer's problem. */
export const FLUFF = /\b(synthetic|sample data|demo data|in this (?:video|film|demo)|welcome to|let's take a look|as you can see)\b/i;
export const WORDS_PER_SECOND = 2.55; // ~153 wpm, the brisk end of the measured ABACare narration band
export const LEAD_SECONDS = 0.3;
export const TAIL_SECONDS = 0.45;

const NEGATION = /\b(no|not|nothing|never|without|none|neither|nor|n't|cannot)\b/i;

// No global brand/domain-specific banned phrases: each film's approved
// claims and optional brand policy govern assertions. See HEALTHCARE_BANNED
// for a *separately opt-in* healthcare marketing policy example.
export const DEFAULT_BANNED = [];
export const HEALTHCARE_BANNED = [
  { id: 'sent-to-payer', pattern: '\\b(submit(?:s|ted|ting)?|sen[dt]s?|sending|transmit(?:s|ted|ting)?|file[ds]?)\\b[^.!?]{0,40}\\b(payers?|insurers?|insurance)\\b', flags: 'i', unlessNegated: true, reason: 'Ready to Bill is local readiness; never imply submission to a payer.' },
  { id: 'payer-outcome', pattern: '\\b(approved|paid|reimbursed|accepted)\\s+(?:by\\s+)?(?:the\\s+|a\\s+)?(payers?|insurers?)\\b|\\bget paid\\b|\\bpaid faster\\b|\\bfewer denials\\b|\\breduces? denials\\b|\\bno denials\\b', flags: 'i', unlessNegated: true, reason: 'No payer outcome may be implied.' },
  { id: 'guarantee', pattern: '\\bguarantee[sd]?\\b', flags: 'i', reason: 'No guarantees.' },
  { id: 'hipaa-status', pattern: '\\bHIPAA[\\s-]*(certified|compliant|approved)\\b', flags: 'i', reason: 'HHS recognizes no HIPAA certification; state only evidenced facts.' },
  { id: 'superlative', pattern: '(#1|\\bnumber one\\b|\\bbest[- ]in[- ]class\\b|\\bindustry[- ]leading\\b|\\bworld[- ]class\\b)', flags: 'i', reason: 'Unsubstantiated superlative.' },
  { id: 'testimonial', pattern: '\\b(testimonials?|customers? (?:say|love|trust)|trusted by|loved by)\\b', flags: 'i', reason: 'No testimonials or customer praise.' },
  { id: 'comparative', pattern: '\\b(better than|faster than|cheaper than|unlike)\\b', flags: 'i', reason: 'No comparative claims without substantiation.' },
];

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
  return [{ id: 'main', ratios: spec.ratios || [], targetSeconds: spec.targetSeconds, beats: spec.beats || [] }];
}

export function estimateBeatSeconds(beat) {
  const n = words(beat.narration || '').length;
  if (!n) return Number(beat.minSeconds || 2);
  return Math.max(Number(beat.minSeconds || 0), LEAD_SECONDS + n / WORDS_PER_SECOND + TAIL_SECONDS);
}

export function estimateCutSeconds(cut) {
  return cut.beats.reduce((sum, beat) => sum + estimateBeatSeconds(beat), 0);
}

function resolveBannedPatterns(brand, spec) {
  // The inherited restrictions are appropriate only to verified commercial
  // demo claims. A fictional screenplay is not a clinical product assertion.
  const defaults = creativeMode(spec) === 'verified-demo' ? DEFAULT_BANNED : [];
  return [...defaults, ...(brand?.bannedPhrases || [])].map((b) => ({ ...b, regex: new RegExp(b.pattern, b.flags || 'i') }));
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
  const banned = resolveBannedPatterns(brand, spec);
  const forbidden = (brand?.forbiddenNames || []).map((n) => ({ name: n, re: new RegExp(`(^|[^A-Za-z0-9])${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^A-Za-z0-9])`, 'i') }));
  return (text, where) => {
    for (const h of bannedHits(text, banned)) err('banned-phrase', `"${h.match}" (${h.id}): ${h.reason || 'banned'} — "${h.sentence}"`, where);
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

function lintVoice(spec, err, warn, options) {
  const v = spec.voice;
  const manifest = options.authorizationManifest ?? process.env.MVG_ELEVENLABS_AUTHORIZATION;
  const ownerClone = v.ownerVoice === true && v.provider === 'elevenlabs' && Boolean(v.voiceId) && manifestVoiceId(manifest) === v.voiceId;
  if (v.ownerVoice === true && !ownerClone) err('owner-voice', "marketing narration is the owner voice clone only under that job's owner manifest", 'voice');
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
  // Film-wide synthetic/vision disclosure is meaningful; healthcare-specific
  // 'NO PHI' text is never imposed on an unrelated product or documentary.
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

function lintBeatText(beat, where, claimsById, err, warn, scanText, mode) {
  const texts = [...sentences(beat.narration || ''), ...(beat.onScreenText ? [beat.onScreenText] : [])];
  for (const t of texts) scanText(t, where);
  const fluff = FLUFF.exec(beat.narration || '');
  if (fluff && mode === 'verified-demo') err('narration-fluff', `narration spends words on "${fluff[0]}"; say what the viewer gains, and leave data disclosure to an end card`, where);
  if (beat.onScreenText && words(beat.onScreenText).length > 8) warn('on-screen-length', 'on-screen text longer than 8 words may not survive phone-size reading', where);
  const refs = (beat.claims || []).map(id => claimsById.get(id));
  (beat.claims || []).forEach(id => { if (!claimsById.has(id)) err('claim-missing', `beat references unknown claim ${id}`, where); });
  const known = refs.filter(Boolean);
  // A dramatic situation, envisioned interface or fictional patient journey
  // does not need evidence proving that it already happened. Real assertions
  // always keep the evidence gate, including within a hybrid film.
  const verified = beat.truthStatus === 'verified' ||
    (!beat.truthStatus && mode === 'verified-demo');
  if (verified && texts.length && !known.length) err('claim-unmapped', 'verified spoken or screen claim has no evidence reference', where);
  if (verified) for (const t of texts) {
    if (known.length && !known.some(c => claimCovers(c, t))) err('claim-uncovered', `"${t}" is not covered by any referenced claim`, where);
    for (const token of numericTokens(t)) if (!claimMentions(known, token)) err('figure-unsupported', `"${token}" in "${t}" is unsupported by this verified claim`, where);
  }
}

function lintBroll(beat, where, err, warn, scanText, mode) {
  if (!beat.broll) return;
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
  scanText(beat.broll.prompt || '', where);
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
  lintBeatText(beat, where, state.claimsById, state.err, state.warn, state.scanText, state.mode);
  lintBroll(beat, where, state.err, state.warn, state.scanText, state.mode);
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
  for (const finding of inspectNarrativeArc(state.spec, cut, estimateBeatSeconds)) state.err(finding.code, finding.message, finding.where);
  const estimate = estimateCutSeconds(cut);
  state.estimates.push({ cut: cut.id, estimateSeconds: Number(estimate.toFixed(1)), targetSeconds: cut.targetSeconds });
  if (estimate > cut.targetSeconds + 4) state.err('too-long', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target; trim the script before spending on voice`, cut.id);
  else if (estimate > cut.targetSeconds + 1.5) state.warn('long', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target`, cut.id);
  else if (estimate < cut.targetSeconds * 0.6) state.warn('short', `cut ${cut.id} is estimated at ${estimate.toFixed(1)} s against a ${cut.targetSeconds} s target`, cut.id);
  if (state.music?.provider === 'elevenlabs' && state.music.lengthSeconds !== undefined && state.music.lengthSeconds < cut.targetSeconds + 2) state.err('music-length', `music.lengthSeconds ${state.music.lengthSeconds} s is shorter than cut ${cut.id} (${cut.targetSeconds} s target) plus 2 s; the bed must outlast the program (the assets stage re-checks against the measured length)`, 'music');
  if (state.mode === 'verified-demo' && !cut.beats.some((b) => b.kind === 'ui')) state.err('no-ui', `verified demo ${cut.id} has no captured UI proof. Other film modes can use fully generated visuals.`, cut.id);
}

export function lintSpec(spec, brand, options = {}) {
  const errors = [];
  const warnings = [];
  const err = (code, message, where) => errors.push({ code, message, where });
  const warn = (code, message, where) => warnings.push({ code, message, where });
  const io = options.io || defaultIo(options.specDir);
  lintSchemas(spec, brand, options, err);
  if (errors.length) return { ok: false, errors, warnings, estimates: [] };

  const cuts = normalizeCuts(spec);
  const claimsById = lintClaims(spec, io, err);
  const scanText = createTextScanner(brand, spec, err);
  lintVoice(spec, err, warn, options);
  const music = spec.music;
  lintMusic(music, err);
  lintLabelsAndCta(spec, brand, claimsById, err, warn, scanText);
  const state = { spec, mode: creativeMode(spec), seenRatios: new Set(), claimsById, scanText, io, err, warn, music, estimates: [] };
  for (const cut of cuts) lintCut(cut, state);
  return { ok: errors.length === 0, errors, warnings, estimates: state.estimates };
}
