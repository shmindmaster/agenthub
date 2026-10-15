// Narration-to-visual sync primitives shared by build-cue-sheet.mjs, compose-screencast.mjs and validate-sync.mjs.
// Contract: VIDEO-SYNC-DIRECTIVE (2026-10-15) and skills/media-studio/references/product-picture.md.
// Pure functions only (no ffmpeg, no filesystem), so the timing rules are unit-tested on their own and the three
// tools cannot drift apart on what "the action lands on the word" means.

export const SYNC_DEFAULTS = Object.freeze({
  actionToleranceMs: 300,   // click/point vs the spoken verb or object
  screenToleranceMs: 40,    // screen-on may trail the first content word by at most one frame
  resultHoldMinSeconds: 1.5,
  driftMaxMs: 40,           // A/V drift on the encoded file
  onsetOffsetMaxMs: 120,    // constant offset allowed when only an energy-onset estimate is available
  screenLeadSeconds: 0.3,   // new screen appears this long before the first content word
  headHoldMaxSeconds: 1.5,  // freeze on a clip's first frame so a too-early action lands on its word
  minCursorLeadSeconds: 0.8,// footage kept before an action when pulling it earlier (pointer travel + settle)
  clickLeadSeconds: 0,      // click target relative to the keyword start (negative = click first)
  maxFreezeSeconds: 4,
  maxDroppedFrames: 3,
  sceneThreshold: 0.4,
});

const STOPWORDS = new Set(('a an the and or but so if then than of to in on at by for from with without into onto over under up down out off as is are was were be been being am do does did done have has had having it its it\'s this that these those there here i we you he she they them our your their my me us him her his hers theirs not no yes can could will would shall should may might must just also very too more most some any each every all both either neither one two now next first then when while where which who whom whose what how why about after before again once only own same such').split(/\s+/));

export const norm = (w) => String(w ?? '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');
export const isContentWord = (w) => { const n = norm(w); return n.length > 1 && !STOPWORDS.has(n); };
export const textWords = (text) => String(text ?? '').split(/\s+/).map((w) => w.trim()).filter((w) => norm(w));
export const round = (v, places = 3) => (Number.isFinite(v) ? Math.round(v * 10 ** places) / 10 ** places : v);
export const median = (xs) => { const a = xs.filter(Number.isFinite).sort((x, y) => x - y); if (!a.length) return null; const m = a.length >> 1; return a.length % 2 ? a[m] : (a[m - 1] + a[m]) / 2; };
export const percentile = (xs, p) => { const a = xs.filter(Number.isFinite).sort((x, y) => x - y); if (!a.length) return null; return a[Math.min(a.length - 1, Math.max(0, Math.ceil((p / 100) * a.length) - 1))]; };

/** Stem-tolerant word equality: approve/approved/approving, send/sending. */
export function wordMatches(a, b) {
  const x = norm(a), y = norm(b);
  if (!x || !y) return false;
  if (x === y) return true;
  const min = Math.min(x.length, y.length);
  if (min < 4) return false;
  let cp = 0; while (cp < min && x[cp] === y[cp]) cp++;
  return cp >= Math.max(4, min - 2);
}

/** Spread authored words across [start, end] in proportion to word length (degraded: no real timestamps). */
export function spreadWords(text, start, end) {
  const ws = textWords(text);
  const weight = ws.map((w) => norm(w).length + 1);
  const total = weight.reduce((a, b) => a + b, 0) || 1;
  let t = start;
  return ws.map((w, i) => { const d = ((end - start) * weight[i]) / total; const row = { w, start: round(t), end: round(t + d) }; t += d; return row; });
}

/**
 * Words from one local-ASR payload. Accepts the faster-whisper payload `ai.ps1 transcribe --engine whisper --json-out`
 * writes ({ segments:[{ start, end, text, words:[{ start, end, word }] }] }), a flat { words:[{ word|w|text, start, end }] },
 * or a bare array of either. `offset` shifts per-segment audio onto the program timeline.
 * precision: 'word' (real word timestamps) | 'segment' (segment times only; words spread inside each segment) | 'none'.
 */
export function parseAsrWords(payload, { offset = 0 } = {}) {
  const p = Array.isArray(payload) ? { words: payload } : (payload || {});
  const out = [];
  const pushWord = (o) => { const w = String(o.word ?? o.w ?? o.text ?? '').trim(); if (norm(w) && Number.isFinite(o.start) && Number.isFinite(o.end)) out.push({ w, start: round(o.start + offset), end: round(o.end + offset) }); };
  if (Array.isArray(p.words) && p.words.length) { p.words.forEach(pushWord); if (out.length) return { words: out, precision: 'word' }; }
  const segs = Array.isArray(p.segments) ? p.segments : [];
  if (segs.some((s) => Array.isArray(s.words) && s.words.length)) {
    for (const s of segs) for (const w of s.words || []) pushWord(w);
    if (out.length) return { words: out, precision: 'word' };
  }
  const spread = [];
  for (const s of segs) if (Number.isFinite(s.start) && Number.isFinite(s.end) && textWords(s.text).length) spread.push(...spreadWords(s.text, s.start + offset, s.end + offset));
  return spread.length ? { words: spread, precision: 'segment' } : { words: [], precision: 'none' };
}

/** First (or, for a result that is named at the end of the line, last) narration word matching any keyword. */
export function findKeywordWord(words, keywords, { last = false } = {}) {
  const keys = (keywords || []).flatMap((k) => textWords(k)).filter(isContentWord);
  if (!keys.length) return null;
  const order = words.map((_, i) => i);
  if (last) order.reverse();
  for (const i of order) {
    const hit = keys.find((k) => wordMatches(words[i].w, k));
    if (hit) return { index: i, w: words[i].w, start: words[i].start, end: words[i].end, keyword: hit };
  }
  return null;
}

export const keywordsFromLabel = (label) => textWords(label).filter(isContentWord).map(norm);

export function firstContentWord(words) {
  const i = words.findIndex((x) => isContentWord(x.w));
  const k = i >= 0 ? i : 0;
  return words[k] ? { index: k, w: words[k].w, start: words[k].start, end: words[k].end } : null;
}

// ---------------------------------------------------------------- edit decision list (clip time <-> picture time)

/** Kept source ranges of a clip edit, in order: [[a,b],...]. edit = { trimStart, trimEnd, skip, srcSeconds }. */
export function keptRanges(edit) {
  const t0 = Number(edit.trimStart || 0);
  const t1 = Number(edit.trimEnd || edit.srcSeconds || 0);
  const keep = [];
  let cur = t0;
  for (const [a, b] of (edit.skip || []).slice().sort((x, y) => x[0] - y[0])) { if (a > cur) keep.push([cur, Math.min(a, t1)]); cur = Math.max(cur, b); }
  if (cur < t1) keep.push([cur, t1]);
  return keep;
}

/** Seconds into the slot at which source time `ts` plays, or null when the edit drops it. */
export function clipToSlot(edit, ts) {
  const sp = Number(edit.speed || 1);
  let acc = 0;
  for (const [a, b] of keptRanges(edit)) {
    if (ts >= a - 1e-9 && ts <= b + 1e-9) return round(Number(edit.headHold || 0) + (acc + (ts - a)) / sp);
    acc += b - a;
  }
  return null;
}

/**
 * Voice-first alignment of one action inside one slot. `targetSlotSeconds` is where the action must land (keyword
 * start minus slot start). Too early: freeze the clip's first frame (headHold) up to headHoldMaxSeconds. Too late:
 * trim the head, keeping at least minCursorLeadSeconds of footage before the action so the pointer travel stays on
 * camera. Anything else is a recapture, never a squeezed voice.
 */
export function planAlignment({ edit, actionClipTime, targetSlotSeconds, label = 'action', opts = {} }) {
  const o = { ...SYNC_DEFAULTS, ...opts };
  const natural = clipToSlot(edit, actionClipTime);
  if (natural === null) return { error: `voice-first: ${label} at clip ${actionClipTime}s falls inside a skipped range; keep the action footage.` };
  const delta = round(targetSlotSeconds - natural);
  if (Math.abs(delta) <= 0.02) return { edit: { ...edit }, deltaSeconds: 0, naturalSlotSeconds: natural };
  const sp = Number(edit.speed || 1);
  if (delta > 0) {
    const headHold = round(Number(edit.headHold || 0) + delta);
    if (headHold > o.headHoldMaxSeconds) return { error: `voice-first: ${label} lands ${delta.toFixed(2)}s before its spoken word and the clip may freeze its first frame for at most ${o.headHoldMaxSeconds}s. Recapture the beat with a longer lead-in (slower pointer approach or a pause before the click); do not squeeze the voice.` };
    return { edit: { ...edit, headHold }, deltaSeconds: delta, naturalSlotSeconds: natural };
  }
  const trimStart = round(Number(edit.trimStart || 0) + -delta * sp);
  if (trimStart > actionClipTime - o.minCursorLeadSeconds) return { error: `voice-first: ${label} at clip ${actionClipTime}s lands ${(-delta).toFixed(2)}s after its spoken word; pulling it earlier would cut the pointer approach (needs ${o.minCursorLeadSeconds}s of lead-in). Recapture the beat with the click sooner.` };
  return { edit: { ...edit, trimStart }, deltaSeconds: delta, naturalSlotSeconds: natural };
}

/**
 * Voice-first picture window start for a beat. The new screen is up `lead` seconds before the first content word,
 * never before the previous line has finished, and never later than the segment's own start.
 */
export function slotStartFor({ segmentStart, firstWordStart, prevSpeechEnd, lead = SYNC_DEFAULTS.screenLeadSeconds }) {
  if (!Number.isFinite(firstWordStart)) return round(segmentStart);
  const wanted = Math.min(segmentStart, firstWordStart - lead);
  return round(Math.max(Number.isFinite(prevSpeechEnd) ? prevSpeechEnd + 0.05 : 0, wanted));
}

// ---------------------------------------------------------------- measurements on the encoded candidate

/** In-order alignment of cue words to encoded-ASR words (LCS on normalised tokens). Returns matched index pairs. */
export function alignWords(cueWords, asrWords) {
  const a = cueWords.map((x) => norm(x.w)), b = asrWords.map((x) => norm(x.w));
  const n = a.length, m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] && a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const pairs = [];
  let i = 0, j = 0;
  while (i < n && j < m) { if (a[i] && a[i] === b[j]) { pairs.push([i, j]); i++; j++; } else if (dp[i + 1][j] >= dp[i][j + 1]) i++; else j++; }
  return pairs;
}

/** A/V offset and drift (ms) from matched words: offset = median delta, drift = last-third median minus first-third median. */
export function offsetStats(deltasMs, times) {
  if (!deltasMs.length) return null;
  const order = deltasMs.map((d, i) => ({ d, t: times[i] })).sort((x, y) => x.t - y.t);
  const k = Math.max(1, Math.floor(order.length / 3));
  const first = median(order.slice(0, k).map((x) => x.d)), last = median(order.slice(-k).map((x) => x.d));
  return { count: order.length, offsetMs: round(median(order.map((x) => x.d)), 1), driftMs: round(last - first, 1), p95AbsMs: round(percentile(order.map((x) => Math.abs(x.d)), 95), 1) };
}

/** silence_end markers from ffmpeg silencedetect stderr = speech onsets, seconds. */
export function parseSilenceEnds(stderr) {
  return [...String(stderr).matchAll(/silence_end:\s*(-?[\d.]+)/g)].map((m) => Number(m[1]));
}

/** showinfo lines of a select='gt(scene,x)' pass -> cut times, seconds. */
export function parseSceneCuts(stderr) {
  return [...String(stderr).matchAll(/Parsed_showinfo[^\n]*?pts_time:\s*(-?[\d.]+)/g)].map((m) => Number(m[1]));
}

/** freezedetect stderr -> [{ start, end, duration }]. An interval still open at end of file closes at `endOfFile`. */
export function parseFreezes(stderr, endOfFile = null) {
  const out = [];
  let open = null, recorded = false;
  for (const line of String(stderr).split(/\r?\n/)) {
    const s = /freeze_start:\s*([\d.]+)/.exec(line), d = /freeze_duration:\s*([\d.]+)/.exec(line), e = /freeze_end:\s*([\d.]+)/.exec(line);
    if (s) { open = Number(s[1]); recorded = false; }
    if (d && open !== null && !recorded) { const dur = Number(d[1]); out.push({ start: open, end: round(open + dur), duration: dur }); recorded = true; }
    if (e && open !== null) { if (!recorded) out.push({ start: open, end: Number(e[1]), duration: round(Number(e[1]) - open) }); open = null; recorded = false; }
  }
  if (open !== null && Number.isFinite(endOfFile)) out.push({ start: open, end: endOfFile, duration: round(endOfFile - open) });
  return out;
}

/** Frame-interval gaps in decode-order-independent packet pts -> estimated dropped frames. */
export function droppedFrames(ptsTimes, fps) {
  const t = ptsTimes.filter(Number.isFinite).sort((a, b) => a - b);
  const step = 1 / fps;
  let dropped = 0; const gaps = [];
  for (let i = 1; i < t.length; i++) { const g = t[i] - t[i - 1]; if (g > step * 1.75) { const miss = Math.round(g / step) - 1; dropped += miss; gaps.push({ at: round(t[i - 1]), missing: miss }); } }
  return { dropped, gaps };
}

/** Tesseract TSV -> words whose boxes touch the frame edge (text clipped by the frame). */
export function clippedWords(tsv, width, height, { edge = 3, minConf = 60 } = {}) {
  const out = [];
  const lines = String(tsv).split(/\r?\n/);
  const head = (lines.shift() || '').split('\t');
  const ix = (n) => head.indexOf(n);
  const [L, T, W, H, C, X] = ['left', 'top', 'width', 'height', 'conf', 'text'].map(ix);
  if ([L, T, W, H, C, X].some((i) => i < 0)) return out;
  for (const line of lines) {
    const c = line.split('\t');
    const text = (c[X] || '').trim();
    if (!text || norm(text).length < 3 || Number(c[C]) < minConf) continue;
    const left = Number(c[L]), top = Number(c[T]), right = left + Number(c[W]), bottom = top + Number(c[H]);
    if (left <= edge || top <= edge || right >= width - edge || bottom >= height - edge) out.push({ text, left, top, right, bottom });
  }
  return out;
}
