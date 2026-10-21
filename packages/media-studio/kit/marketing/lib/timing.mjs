// Word timing and the voice-first timeline. Scene length is the narration span (voice first): a beat lasts as long as
// its spoken line plus a short lead-in (the screen is up before the first content word) and tail (the result holds).
import { LEAD_SECONDS, TAIL_SECONDS } from './lint.mjs';
import { round } from './util.mjs';

const ONES = { zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90, hundred: 100 };
/** Normalized match key: lower case, no punctuation, number words as digits ("twelve" and "12" match). */
const norm = (w) => {
  const n = String(w).toLowerCase().replace(/[’']/g, '').replace(/[^a-z0-9$%]+/g, '');
  return n in ONES ? String(ONES[n]) : n;
};

/** Normalize an ASR payload (OpenAI verbose_json `words`, or local whisper `segments[].words[]`) to [{word,start,end}]. */
export function parseAsrWords(payload) {
  const raw = Array.isArray(payload?.words) && payload.words.length
    ? payload.words
    : (payload?.segments || []).flatMap((s) => s.words || []);
  return raw
    .map((w) => ({ word: String(w.word ?? w.text ?? '').trim(), start: Number(w.start), end: Number(w.end) }))
    .filter((w) => w.word && Number.isFinite(w.start) && Number.isFinite(w.end));
}

/**
 * Give every word of the authored script a time, using the ASR words as the clock. Matching is a forward greedy walk
 * with a small lookahead; script words the ASR missed are interpolated between their neighbors. The authored text is
 * what captions show, so ASR spelling errors never reach the screen.
 */
export function alignScriptToAsr(script, asrWords, durationSeconds) {
  const scriptWords = Array.isArray(script) ? script : String(script).split(/\s+/).filter(Boolean);
  if (!scriptWords.length) return [];
  const asr = asrWords || [];
  const out = scriptWords.map((w) => ({ word: w, start: null, end: null, matched: false }));
  let j = 0;
  for (let i = 0; i < out.length; i++) {
    const n = norm(out[i].word);
    for (let look = 0; look <= 4 && j + look < asr.length; look++) {
      const a = norm(asr[j + look].word);
      if (a && n && (a === n || (a.length > 3 && n.length > 3 && (a.startsWith(n) || n.startsWith(a))))) {
        out[i].start = asr[j + look].start; out[i].end = asr[j + look].end; out[i].matched = true; j += look + 1; break;
      }
      // One authored word the ASR split in two ("ABACare" heard as "ABA care"), or the reverse.
      const next = asr[j + look + 1];
      if (next && n && a && `${a}${norm(next.word)}` === n) {
        out[i].start = asr[j + look].start; out[i].end = next.end; out[i].matched = true; j += look + 2; break;
      }
    }
  }
  const matched = out.filter((w) => w.matched).length;
  if (!matched) {
    const total = durationSeconds || (asr.length ? asr[asr.length - 1].end : scriptWords.length / 2.55);
    out.forEach((w, i) => { w.start = round((i / out.length) * total); w.end = round(((i + 1) / out.length) * total); });
    return out.map(({ word, start, end }) => ({ word, start, end, estimated: true }));
  }
  // interpolate runs of unmatched words between matched neighbors
  for (let i = 0; i < out.length; i++) {
    if (out[i].matched) continue;
    let a = i - 1;
    while (a >= 0 && !out[a].matched) a--;
    let b = i + 1;
    while (b < out.length && !out[b].matched) b++;
    const t0 = a >= 0 ? out[a].end : Math.max(0, out[b].start - 0.25 * (b - i));
    const t1 = b < out.length ? out[b].start : (durationSeconds || out[a].end + 0.3 * (i - a));
    const run = (b < out.length ? b : out.length) - (a + 1);
    const idx = i - (a + 1);
    out[i].start = round(t0 + ((t1 - t0) * idx) / run);
    out[i].end = round(t0 + ((t1 - t0) * (idx + 1)) / run);
  }
  return out.map(({ word, start, end, matched: m }) => ({ word, start: round(start), end: round(end), ...(m ? {} : { estimated: true }) }));
}

/**
 * Voice-first timeline.
 * @param {Array<{beat:object, audio?:{durationSeconds:number, words:Array}}>} lines in cut order
 * @returns {{durationSeconds:number, segments:Array}} compatible with story/narration-timeline.json
 */
export function buildTimeline(lines, { lead = LEAD_SECONDS, tail = TAIL_SECONDS, cardSeconds = 2.2 } = {}) {
  let t = 0;
  const segments = [];
  for (const { beat, audio } of lines) {
    let duration;
    let speech = 0;
    let lineStart = null;
    let wordsAbs = [];
    if (audio) {
      lineStart = t + lead;
      speech = audio.durationSeconds;
      duration = Math.max(lead + speech + tail, Number(beat.minSeconds || 0));
      wordsAbs = audio.words.map((w) => ({ ...w, start: round(w.start + lineStart), end: round(w.end + lineStart) }));
    } else duration = Number(beat.minSeconds || (beat.kind === 'card' || beat.kind === 'title' ? cardSeconds : 2));
    segments.push({
      id: beat.id, scene: beat.id, kind: beat.kind, text: beat.narration || '', startSeconds: round(t), durationSeconds: round(duration),
      speechSeconds: round(speech), lineStartSeconds: lineStart === null ? null : round(lineStart), words: wordsAbs,
    });
    t += duration;
  }
  return { durationSeconds: round(t), segments };
}

/** The music bed's beat grid (`edit.beatGrid`): bed time 0 is program time 0, so beats fall at offsetSeconds + n * 60/bpm (any integer n: the offset is the phase). */
export function beatGridOf(grid) {
  const bpm = Number(grid?.bpm);
  const offsetSeconds = Number(grid?.offsetSeconds ?? 0);
  if (!(bpm >= 40 && bpm <= 220)) throw new Error(`edit.beatGrid.bpm must be between 40 and 220 (got ${grid?.bpm})`);
  if (!(offsetSeconds >= 0 && offsetSeconds <= 10)) throw new Error(`edit.beatGrid.offsetSeconds must be between 0 and 10 seconds (got ${grid?.offsetSeconds})`);
  return { bpm, offsetSeconds, periodSeconds: 60 / bpm };
}

const GRID_TOLERANCE = 0.0005; // a boundary within half a millisecond of a beat is on it

/**
 * Cuts on the beat. Every segment boundary except the program start lands on the next grid point at or after the segment's
 * natural end, by lengthening only the segment's tail hold (never shortening it, never moving narration inside it); a boundary
 * already on the grid is left alone, so each extension is under one beat period. Later segments shift by what came before:
 * startSeconds, lineStartSeconds and every word time move together, speechSeconds is untouched, and the total grows.
 * Pure: the input timeline is not modified. Times are whole milliseconds, so a boundary is within 0.5 ms of its grid point.
 * @returns {object} the timeline with `beatGrid { bpm, offsetSeconds, periodSeconds, snapped, addedSeconds }` and, per segment, `snapExtendSeconds`
 */
export function snapToBeatGrid(timeline, grid) {
  const { bpm, offsetSeconds, periodSeconds } = beatGridOf(grid);
  if (!timeline.segments.length) return { ...timeline, beatGrid: { bpm, offsetSeconds, periodSeconds: round(periodSeconds, 6), snapped: 0, addedSeconds: 0 } };
  let start = timeline.segments[0].startSeconds; // the program start is not snapped
  let snapped = 0;
  const segments = timeline.segments.map((seg) => {
    const shift = round(start - seg.startSeconds);
    const natural = round(start + seg.durationSeconds);
    // n may be negative: the offset is the bed's phase, so beats continue backwards from it to program time 0
    const n = Math.ceil((natural - offsetSeconds - GRID_TOLERANCE) / periodSeconds);
    const boundary = Math.max(natural, round(offsetSeconds + n * periodSeconds));
    const extend = round(boundary - natural);
    if (extend > 0) snapped++;
    const out = {
      ...seg, startSeconds: start, durationSeconds: round(boundary - start), snapExtendSeconds: extend,
      lineStartSeconds: seg.lineStartSeconds === null ? null : round(seg.lineStartSeconds + shift),
      words: seg.words.map((w) => ({ ...w, start: round(w.start + shift), end: round(w.end + shift) })),
    };
    start = boundary;
    return out;
  });
  const durationSeconds = start;
  return { ...timeline, durationSeconds, segments, beatGrid: { bpm, offsetSeconds, periodSeconds: round(periodSeconds, 6), snapped, addedSeconds: round(durationSeconds - timeline.durationSeconds) } };
}
