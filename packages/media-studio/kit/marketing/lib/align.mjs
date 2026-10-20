// Voice-first alignment of a captured clip to the spoken line. The clip is cut so the first narrated pointer action
// lands on its spoken keyword, and the beat is made long enough for the result to hold after the last narrated action.
// Both the timing stage (beat length) and the compose stage (clip trim) use it, so they cannot disagree.
import { round } from './util.mjs';

export const RESULT_HOLD_SECONDS = 1.6; // the sync gate needs >= 1.5 s; the extra 0.1 s is encode slack

const ONES = { zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90, hundred: 100 };
const NUMBER_FOR_DIGITS = Object.fromEntries(Object.entries(ONES).map(([w, n]) => [String(n), w]));

const norm = (w) => String(w ?? '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');

/** "twelve" also matches the digits an ASR writes ("12"), and the reverse. */
export function expandKeywords(keywords) {
  const out = new Set();
  for (const k of keywords || []) {
    const n = norm(k);
    if (!n) continue;
    out.add(n);
    if (n in ONES) out.add(String(ONES[n]));
    if (n in NUMBER_FOR_DIGITS) out.add(NUMBER_FOR_DIGITS[n]);
  }
  return [...out];
}

/** Same rule as the sync tooling's wordMatches: equal, or a shared prefix of at least 4 letters (within 2 of the shorter). */
export function keywordMatches(word, keyword) {
  const x = norm(word);
  const y = norm(keyword);
  if (!x || !y) return false;
  if (x === y) return true;
  const min = Math.min(x.length, y.length);
  if (min < 4) return false;
  let cp = 0;
  while (cp < min && x[cp] === y[cp]) cp++;
  return cp >= Math.max(4, min - 2);
}

export function findWord(words, keywords) {
  const keys = expandKeywords(keywords);
  return words.find((w) => keys.some((k) => keywordMatches(w.word, k))) || null;
}

const ACTION_TYPES = new Set(['point', 'click', 'type']);

/** Receipt action by label, in clip seconds (Recast trims the blank lead-in off the head). */
export function receiptActionTime(receiptActions, label, headTrim = 0) {
  const hit = (receiptActions || []).find((a) => a.label === label && ACTION_TYPES.has(a.type));
  return hit ? hit.t - headTrim : null;
}

/**
 * @param {object} o
 * @param {Array<{label:string,keywords:string[]}>} o.actions narrated actions declared by the beat (ui.actions)
 * @param {Array} o.receiptActions the clip's receipt action log
 * @param {number} o.headTrim recastHeadTrimSeconds
 * @param {Array<{word:string,start:number}>} o.wordsRel narration words, seconds from the START OF THE BEAT
 * @param {number} o.fallbackTrim the authored ui.trimStart, used when nothing can be aligned
 * @returns {{trimStart:number, aligned:boolean, requiredSeconds:number|null, actions:Array, note:string|null}}
 */
export function alignBeat({ actions, receiptActions, headTrim = 0, wordsRel, fallbackTrim = 0 }) {
  const placed = [];
  for (const a of actions || []) {
    const t = receiptActionTime(receiptActions, a.label, headTrim);
    const word = findWord(wordsRel, a.keywords);
    placed.push({ label: a.label, clipSeconds: t, word: word?.word ?? null, wordRel: word ? word.start : null });
  }
  const anchor = placed.find((p) => p.clipSeconds !== null && p.wordRel !== null);
  if (!anchor) return { trimStart: fallbackTrim, aligned: false, requiredSeconds: null, actions: placed, note: placed.length ? 'no narrated action could be matched to a spoken word; using ui.trimStart' : null };
  let trimStart = anchor.clipSeconds - anchor.wordRel;
  let note = null;
  if (trimStart < 0) { note = `the clip has only ${anchor.clipSeconds.toFixed(2)}s before "${anchor.label}" but the word comes ${anchor.wordRel.toFixed(2)}s into the beat; the action will land late`; trimStart = 0; }
  trimStart = round(trimStart, 3);
  const rel = placed.filter((p) => p.clipSeconds !== null).map((p) => ({ ...p, programRel: round(p.clipSeconds - trimStart, 3) }));
  const last = Math.max(...rel.map((p) => p.programRel));
  return { trimStart, aligned: true, requiredSeconds: round(last + RESULT_HOLD_SECONDS, 3), actions: rel, note };
}

/** Receipt actions inside the clip window that the beat does not narrate: emitted as narrated:false in the cue plan. */
export function unnarratedActions(receiptActions, headTrim, windowStart, windowEnd, narratedLabels) {
  const labels = new Set(narratedLabels);
  const out = [];
  for (const a of receiptActions || []) {
    if (!ACTION_TYPES.has(a.type) || !a.label || labels.has(a.label) || out.includes(a.label)) continue;
    const t = a.t - headTrim;
    if (t >= windowStart - 0.5 && t <= windowEnd + 0.5) out.push(a.label);
  }
  return out;
}
