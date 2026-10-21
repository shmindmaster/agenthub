// Kinetic caption chunking: 5-7 word chunks timed to the spoken words, never split mid-phrase when a clause break
// is available. Also writes SRT for platforms that take a caption file (LinkedIn).
import { round } from './util.mjs';

const END = /[.!?]["')\]]*$/;
const BREAK_BEFORE = new Set(['and', 'but', 'so', 'with', 'to', 'in', 'on', 'of', 'for', 'from', 'that', 'which', 'then', 'before', 'after']);
const norm = (w) => String(w).toLowerCase().replace(/[^a-z0-9']/g, '');
const CLAUSE = /[,;:–—]["')\]]*$/;

export function chunkWords(words, { minWords = 4, maxWords = 7, lead = 0.05, hold = 0.35, minSeconds = 1.0, maxCps = 18 } = {}) {
  if (!words.length) return [];
  // 1) sentences
  const sentenceList = [];
  let cur = [];
  for (const w of words) { cur.push(w); if (END.test(w.word)) { sentenceList.push(cur); cur = []; } }
  if (cur.length) sentenceList.push(cur);
  // 2) merge a short sentence into its neighbor when the result still fits
  const merged = [];
  for (const s of sentenceList) {
    const prev = merged[merged.length - 1];
    if (prev && (s.length < minWords || prev.length < minWords) && prev.length + s.length <= maxWords) prev.push(...s);
    else merged.push([...s]);
  }
  // 3) split long sentences at clause breaks, then before a conjunction or preposition, never leaving a stub
  const chunks = [];
  const split = (rest) => {
    while (rest.length > maxWords) {
      const lo = Math.min(minWords, rest.length - 1);
      const hi = Math.min(maxWords, Math.max(lo, rest.length - minWords));
      const ideal = rest.length / Math.ceil(rest.length / maxWords);
      let best = hi;
      let bestScore = Infinity;
      for (let c = lo; c <= hi; c++) {
        const ends = CLAUSE.test(rest[c - 1].word) ? 0 : BREAK_BEFORE.has(norm(rest[c].word)) ? 1 : 3;
        const score = ends + Math.abs(c - ideal) * 0.5;
        if (score < bestScore) { bestScore = score; best = c; }
      }
      chunks.push(rest.slice(0, best));
      rest = rest.slice(best);
    }
    if (rest.length) chunks.push(rest);
  };
  for (const s of merged) split(s);
  const out = chunks.map((c) => ({ words: c, text: c.map((w) => w.word).join(' '), startSec: round(Math.max(0, c[0].start - lead)), endSec: round(c[c.length - 1].end + hold) }));
  for (let i = 0; i < out.length; i++) {
    const next = out[i + 1];
    if (next && out[i].endSec > next.startSec) out[i].endSec = round(next.startSec - 0.02);
  }
  // Reading speed: a cue shows at most `maxCps` characters per second (the release gate fails above 20). A cue that is
  // too fast is held longer into the gap after it, then started earlier into the gap before it, never over a neighbor.
  for (let i = 0; i < out.length; i++) {
    const c = out[i];
    const need = Math.max(minSeconds, c.text.length / maxCps);
    const prevEnd = i > 0 ? out[i - 1].endSec + 0.02 : 0;
    const nextStart = i + 1 < out.length ? out[i + 1].startSec - 0.02 : Infinity;
    if (c.endSec - c.startSec >= need) continue;
    c.endSec = round(Math.min(nextStart, c.startSec + need));
    if (c.endSec - c.startSec < need) c.startSec = round(Math.max(prevEnd, c.endSec - need));
    if (c.endSec - c.startSec < need && i > 0) {
      // take the previous cue's hold: it only needs to outlast its last word
      const p = out[i - 1];
      const floor = p.words[p.words.length - 1].end + 0.05;
      c.startSec = round(Math.max(floor + 0.02, c.endSec - need));
      p.endSec = round(Math.min(p.endSec, c.startSec - 0.02));
    }
    if (c.endSec - c.startSec < need && i + 1 < out.length) {
      // last resort: the next cue appears exactly when its first word is spoken, and this one holds up to that moment
      const n = out[i + 1];
      const room = Math.min(n.words[0].start - 0.02, c.startSec + need);
      if (room > c.endSec) { c.endSec = round(room); n.startSec = round(Math.max(n.startSec, c.endSec + 0.02)); }
    }
  }
  return out;
}

const stamp = (s) => {
  const ms = Math.round(s * 1000);
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${p(Math.floor(ms / 3600000))}:${p(Math.floor(ms / 60000) % 60)}:${p(Math.floor(ms / 1000) % 60)},${p(ms % 1000, 3)}`;
}

/** Wrap a cue to at most two lines of `max` characters, breaking at the space nearest the middle. */
export function wrapCue(text, max = 42) {
  if (text.length <= max) return text;
  const spaces = [...text.matchAll(/ /g)].map((m) => m.index);
  const mid = text.length / 2;
  const at = spaces.sort((a, b) => Math.abs(a - mid) - Math.abs(b - mid))[0];
  return at === undefined ? text : `${text.slice(0, at)}\n${text.slice(at + 1)}`;
}

export function toSrt(chunks) {
  return `${chunks.map((c, i) => `${i + 1}\n${stamp(c.startSec)} --> ${stamp(c.endSec)}\n${wrapCue(c.text)}\n`).join('\n')}`;
}

const lexLess = (a, b) => { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] < b[i]; return false; };

export const CAPTION_CHAR_EM = 0.58; // Space Grotesk 600: average advance per character in em, with a little margin
export const CAPTION_GAP_EM = 0.4;

/**
 * Explicit line breaks for one caption chunk: word counts per line. Lines are balanced (the widest is as narrow as
 * possible), each is at most `maxWidthPx`, and none holds a single word (>= 2 words per line) unless the chunk is too short
 * to split. Computed here, not by CSS, so a render cannot orphan a word; the composition also sets text-wrap: balance as a
 * second line of defence. Chunks are at most 7 words, so every split is enumerated.
 */
export function lineBreaks(words, { maxWidthPx, fontSize, minWordsPerLine = 2, charEm = CAPTION_CHAR_EM, gapEm = CAPTION_GAP_EM }) {
  const n = words.length;
  const wpx = words.map((w) => String(w.word).length * charEm * fontSize);
  const span = (i, j) => { let s = 0; for (let k = i; k < j; k++) s += wpx[k]; return s + (j - i - 1) * gapEm * fontSize; };
  if (n === 0) return [];
  if (span(0, n) <= maxWidthPx || n < 2 * minWordsPerLine) return [n];
  let best = null;
  const walk = (start, acc) => {
    if (start === n) {
      const widths = acc.map((c, idx) => span(acc.slice(0, idx).reduce((a, b) => a + b, 0), acc.slice(0, idx + 1).reduce((a, b) => a + b, 0)));
      const fits = widths.every((w) => w <= maxWidthPx);
      let at = 0;
      const clause = acc.slice(0, -1).every((c) => { at += c; return /[,;:.!?]$/.test(String(words[at - 1].word)); }) ? 0 : 1;
      const score = [fits ? 0 : 1, acc.length, Math.max(...widths), clause];
      if (!best || lexLess(score, best.score)) best = { acc: [...acc], score };
      return;
    }
    for (let take = minWordsPerLine; take <= n - start; take++) {
      if (n - start - take !== 0 && n - start - take < minWordsPerLine) continue;
      walk(start + take, [...acc, take]);
    }
  };
  walk(0, []);
  return best.acc;
}
