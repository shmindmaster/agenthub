// Kinetic caption chunking: 5-7 word chunks timed to the spoken words, never split mid-phrase when a clause break
// is available. Also writes SRT for platforms that take a caption file (LinkedIn).
import { round } from './util.mjs';

const END = /[.!?]["')\]]*$/;
const CLAUSE = /[,;:–—]["')\]]*$/;

export function chunkWords(words, { minWords = 4, maxWords = 7, lead = 0.05, hold = 0.35, minSeconds = 1.0 } = {}) {
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
  // 3) balanced chunks, preferring a clause break near the middle
  const chunks = [];
  for (const s of merged) {
    if (s.length <= maxWords) { chunks.push(s); continue; }
    const k = Math.ceil(s.length / maxWords);
    let rest = s;
    for (let part = k; part > 1; part--) {
      const ideal = Math.round(rest.length / part);
      let cut = ideal;
      for (let d = 0; d <= 2; d++) {
        const a = ideal - d;
        const b = ideal + d;
        if (a >= minWords - 1 && CLAUSE.test(rest[a - 1]?.word || '')) { cut = a; break; }
        if (b <= maxWords && b < rest.length && CLAUSE.test(rest[b - 1]?.word || '')) { cut = b; break; }
      }
      cut = Math.min(maxWords, Math.max(1, cut));
      chunks.push(rest.slice(0, cut));
      rest = rest.slice(cut);
    }
    chunks.push(rest);
  }
  const out = chunks.map((c) => ({ words: c, text: c.map((w) => w.word).join(' '), startSec: round(Math.max(0, c[0].start - lead)), endSec: round(c[c.length - 1].end + hold) }));
  for (let i = 0; i < out.length; i++) {
    const next = out[i + 1];
    if (next && out[i].endSec > next.startSec) out[i].endSec = round(next.startSec - 0.02);
    if (out[i].endSec - out[i].startSec < minSeconds) out[i].endSec = round(Math.min(next ? next.startSec - 0.02 : Infinity, out[i].startSec + minSeconds));
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
