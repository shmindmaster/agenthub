import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, relative, isAbsolute } from 'node:path';

// This validates provenance and review completeness, never substitutes numerical beat rules for judgment.
export function validateSpeechOnly({ root, job, sound, candidate, duration, cutTimes, cutSource }) {
  const errors = [], inputs = {};
  const bad = (s) => errors.push(s);
  const text = (s, n = 1) => typeof s === 'string' && s.trim().length >= n;
  const finite = (n) => typeof n === 'number' && Number.isFinite(n);
  const hash = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
  const load = (r, name, json = true) => {
    if (!r || !text(r.path) || !/^[a-f0-9]{64}$/.test(r.sha256 || '')) { bad(`${name}: hash-bound file reference required`); return null; }
    const p = resolve(root, r.path), rel = relative(root, p);
    if (rel.startsWith('..') || isAbsolute(rel) || !existsSync(p) || hash(p) !== r.sha256) { bad(`${name}: missing, outside job root or stale SHA-256`); return null; }
    inputs[name] = { path: rel.replace(/\\/g, '/'), sha256: r.sha256 };
    try {
      const value = json ? JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, '')) : readFileSync(p, 'utf8');
      if (json && (value === null || typeof value !== 'object' || Array.isArray(value))) { bad(`${name}: evidence must be a JSON object`); return null; }
      if (!json && !text(value)) { bad(`${name}: original evidence must not be empty`); return null; }
      return value;
    } catch { bad(`${name}: unreadable evidence`); return null; }
  };
  if (job.soundMode !== 'speech-only') bad('job.soundMode must explicitly authorize speech-only');
  if (!text(job.producer)) bad('job.producer required to check review independence');
  if (sound.bed !== false || sound.designCues !== 0) bad('speech-only must truthfully declare bed:false and designCues:0');
  const auth = load(sound.authorization, 'authorization');
  if (auth) {
    if (auth.schema !== 'media-studio/speech-only-authorization/1' || auth.soundMode !== 'speech-only' || !text(auth.authorizedBy) || !text(auth.reason, 20)) bad('authorization: explicit signed speech-only creative decision required');
    load(auth.creativeSource, 'creativeSource', false);
  }
  const review = load(sound.review, 'soundReview');
  const clock = load(sound.clock, 'speechClock');
  if (clock) {
    load(clock.source, 'clockSource', false);
    if (clock.schema !== 'media-studio/speech-edit-clock/1' || clock.candidateSha256 !== candidate.sha256 || !text(clock.method)) bad('speechClock: schema, exact candidate and actual timing method required');
    if (!(clock.uncertaintyMs === null || (finite(clock.uncertaintyMs) && clock.uncertaintyMs >= 0))) bad('speechClock: uncertaintyMs must be measured nonnegative number or null (unknown)');
    const script = load(clock.script, 'script', false), phrases = clock.phrases;
    let end = 0;
    if (!Array.isArray(phrases) || !phrases.length) bad('speechClock: nonempty phrases required');
    else {
      for (const p of phrases) {
        if (!finite(p.startSeconds) || !finite(p.endSeconds) || p.startSeconds < end || p.endSeconds < p.startSeconds || p.endSeconds > duration || !text(p.text)) bad('speechClock: invalid or overlapping phrase clocks');
        end = p.endSeconds;
      }
      const normalize = s => s.trim().replace(/\s+/g, ' ');
      if (script !== null && normalize(phrases.map(p => p.text).join(' ')) !== normalize(script)) bad('speechClock: phrases must preserve the full locked script');
    }
  }
  if (!cutTimes || !cutSource || !cutTimes.length) bad('edit-rhythm: actual EDL with cuts required');
  if (review) {
    if (review.schema !== 'media-studio/speech-only-review/1' || review.candidate?.sha256 !== candidate.sha256 || review.candidate?.bytes !== candidate.bytes) bad('soundReview: exact candidate binding required');
    if (!text(review.reviewer) || review.reviewer === job.producer || review.independentOf !== job.producer) bad('soundReview: independent reviewer must name the actual producer');
    if (!Array.isArray(review.coverage) || review.coverage.length !== 1 || review.coverage[0]?.startSeconds !== 0 || !finite(review.coverage[0]?.endSeconds) || Math.abs(review.coverage[0].endSeconds - duration) > 0.000001 || review.wholeFileSoundReviewed !== true || review.wholeFileEditRhythmReviewed !== true) bad('soundReview: whole exact-file sound and edit-rhythm coverage required');
    if (!Array.isArray(review.uncertainties)) bad('soundReview: uncertainties array required, including unknown timing precision');
    if (clock?.uncertaintyMs === null && !review.uncertainties?.some(x => text(x, 10))) bad('soundReview: unknown clock precision must remain explicit');
    for (const field of ['clarity', 'pauses', 'pacing', 'transitions']) if (review[field]?.verdict !== 'pass' || !text(review[field]?.evidence, 20)) bad(`soundReview: ${field} requires concrete observed evidence and pass`);
    for (const name of ['authorization', 'clock']) if (review[name]?.path !== sound[name]?.path || review[name]?.sha256 !== sound[name]?.sha256) bad(`soundReview: stale ${name} binding`);
    if (review.edl?.path !== cutSource?.path || review.edl?.sha256 !== cutSource?.sha256) bad('edit-rhythm: stale or different actual EDL');
    if (!Array.isArray(review.cuts) || review.cuts.length !== cutTimes?.length) bad('edit-rhythm: enumerate every actual cut exactly once');
    else for (let i = 0; i < review.cuts.length; i++) {
      const c = review.cuts[i];
      if (c.atSeconds !== cutTimes[i] || c.verdict !== 'pass' || !text(c.observedEffect, 20) || !text(c.reason, 20)) bad(`edit-rhythm: cut ${i} needs exact time and concrete observed adjudication`);
      if (!['phrase-boundary', 'continuous-speech', 'pause', 'visual-transition'].includes(c.relationship)) bad(`edit-rhythm: cut ${i} relationship required`);
      if (!Array.isArray(c.phraseIndices) || (c.relationship !== 'visual-transition' && !c.phraseIndices.length) || c.phraseIndices.some(n => !Number.isInteger(n) || n < 0 || n >= (clock?.phrases?.length ?? 0))) bad(`edit-rhythm: cut ${i} invalid phrase references`);
    }
  }
  return { ok: errors.length === 0, errors, inputs, cutTimes, uncertaintyMs: clock?.uncertaintyMs ?? null, scope: 'Evidence completeness and provenance; independent whole-file judgment, no musical grid or universal speech-cut tolerance.' };
}
