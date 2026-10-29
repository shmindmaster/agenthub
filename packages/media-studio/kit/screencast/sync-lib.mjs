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
  maxHoldSeconds: 6.5,      // a declared hold is a beat, not a pause: a still picture longer than this needs motion
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

/**
 * The clock offset between a clip's logged event times and the clip file itself, in seconds.
 * record-lib logs actions, marks and expectations on the raw recording clock ("recording-start"). Recast then trims
 * the blank lead-in off the head of the raw WebM (playwright-recast detectBlankLeadIn, up to 3 s), so a click logged
 * at t plays at t - recastHeadTrimSeconds in the clip. Returns { offset, source }; offset is null when the receipt
 * cannot say (a Recast render with no recorded trim), and callers must refuse to time events from it.
 */
export function clipClock(clipRec) {
  if (!clipRec) return { offset: null, source: 'no capture receipt' };
  if (clipRec.actionClock === 'clip') return { offset: 0, source: 'actions logged on the clip clock' };
  if (Number.isFinite(clipRec.recastHeadTrimSeconds)) return { offset: Number(clipRec.recastHeadTrimSeconds), source: `recastHeadTrimSeconds (${clipRec.recastHeadTrimMethod || 'recorded'})` };
  if (clipRec.recast === 'skipped' || clipRec.recast === 'fallback') return { offset: 0, source: `raw WebM copied (recast ${clipRec.recast})` };
  return { offset: null, source: `recast "${clipRec.recast ?? 'unknown'}" render with no recastHeadTrimSeconds: re-record with the current kit or run scripts/backfill-head-trim.mjs` };
}

/** Event time on the clip clock, or null when the clip clock is unknown or the event has no time. */
export function toClipTime(clipRec, rawSeconds) {
  const { offset } = clipClock(clipRec);
  const t = Number(rawSeconds);
  return offset === null || !Number.isFinite(t) ? null : round(Math.max(0, t - offset));
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

/** The forced aligner's raw clock, bound to exact inputs. Split punctuation/hyphen tokens share their true onset. */
// Cloud script alignment (kit/cloud/cloud-ai.mjs align): hosted ASR word times anchored to the locked script, on the
// same 80 ms grid and SHA-256 bindings. Words the ASR heard differently carry precisionLimited onsets; the clock is
// accepted only while the exact share and the longest precisionLimited run stay inside these limits, recomputed here
// from the report's own words rather than trusted from its summary.
export const CLOUD_ALIGN_SCHEMA = 'cloud-speech/script-alignment/1';
export const CLOUD_ALIGN_LIMITS = Object.freeze({ minExactRatio: 0.9, maxUnmatchedRun: 6 });

export function cloudAlignCoverage(words) {
  let run = 0, longest = 0, exact = 0;
  for (const w of words) {
    if (w.precisionLimited) longest = Math.max(longest, ++run);
    else { run = 0; exact++; }
  }
  return { exact, total: words.length, exactRatio: words.length ? exact / words.length : 0, longestUnmatchedRun: longest };
}

export function forcedWordOnsets(report, expected, { takeSha256, scriptSha256, allowAsrAnchored = false }) {
  if (report?.schema === CLOUD_ALIGN_SCHEMA && !allowAsrAnchored) throw new Error('cloud asr-anchored alignment is not forced alignment; it clocks the picture only where job.json sets clockPolicy.allowAsrAnchored: true');
  const forcedSchemas = ['local-ai/forced-alignment/1', CLOUD_ALIGN_SCHEMA];
  if (!forcedSchemas.includes(report?.schema) || report.units !== 'seconds' || report.gridSeconds !== 0.08) throw new Error('requires Local-AI forced alignment (or an opted-in cloud asr-anchored alignment) in seconds on the 80 ms grid');
  if (report.schema === CLOUD_ALIGN_SCHEMA && Array.isArray(report.words)) {
    const c = cloudAlignCoverage(report.words);
    if (c.exactRatio < CLOUD_ALIGN_LIMITS.minExactRatio || c.longestUnmatchedRun > CLOUD_ALIGN_LIMITS.maxUnmatchedRun) throw new Error(`cloud script alignment too loose for a picture clock: ${c.exact}/${c.total} exact onsets, longest precision-limited run ${c.longestUnmatchedRun}`);
  }
  if (!takeSha256 || report.take?.sha256 !== takeSha256 || !scriptSha256 || report.script?.sha256 !== scriptSha256) throw new Error('forced alignment input SHA-256 mismatch');
  if (!Number.isFinite(report.durationSeconds) || !(report.durationSeconds > 0) || !Array.isArray(report.words) || !report.words.length) throw new Error('empty forced alignment');
  let previous = 0;
  const raw = report.words.map((w) => {
    if (!norm(w.text) || !Number.isFinite(w.start) || !Number.isFinite(w.end) || w.start < previous || w.end < w.start || w.end > report.durationSeconds ||
      [w.start, w.end].some((v) => Math.abs(v / 0.08 - Math.round(v / 0.08)) > 1e-5)) throw new Error('invalid forced alignment word interval or grid');
    previous = w.end;
    return { ...w, key: norm(w.text) };
  });
  const keys = expected.map((w) => norm(w.w ?? w.word ?? w.text));
  if (keys.some((k) => !k) || keys.join('') !== raw.map((w) => w.key).join('')) throw new Error('forced alignment does not cover the complete locked script');
  let char = 0;
  const spans = raw.map((w) => { const from = char; char += w.key.length; return { ...w, from, until: char }; });
  char = 0;
  return expected.map((w, i) => {
    const from = char; char += keys[i].length;
    const hits = spans.filter((s) => s.from < char && s.until > from);
    return { w: w.w ?? w.word ?? w.text, start: hits[0].start, end: hits.at(-1).end };
  });
}

export function measureWordSync(report, cueWords, bindings, maxMs = SYNC_DEFAULTS.driftMaxMs) {
  if (!cueWords.length || cueWords.some((w, i) => !Number.isFinite(w.start) || w.start < 0 || (i && w.start < cueWords[i - 1].start) || (w.end !== undefined && (!Number.isFinite(w.end) || w.end < w.start)))) throw new Error('invalid cue word interval');
  const words = forcedWordOnsets(report, cueWords, bindings);
  const stats = offsetStats(words.map((w, i) => (w.start - cueWords[i].start) * 1000), cueWords.map((w) => w.start));
  const errors = [];
  if (!stats) errors.push('no cue words to measure');
  else {
    if (Math.abs(stats.offsetMs) > maxMs) errors.push(`encoded audio is ${stats.offsetMs} ms off the cue-sheet words (max +-${maxMs} ms; forced-aligner 80 ms grid).`);
    if (Math.abs(stats.driftMs) > maxMs) errors.push(`A/V drift ${stats.driftMs} ms from the start of the program to its end (max +-${maxMs} ms).`);
  }
  const method = report?.schema === CLOUD_ALIGN_SCHEMA ? 'asr-anchored-alignment-on-encoded' : 'forced-alignment-on-encoded';
  return { ok: !errors.length, errors, method, gridMs: 80, ...stats, words };
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

// ---------------------------------------------------------------- freezes against the cue sheet
// A freeze is a stalled picture while the cue sheet expects change. A picture that is meant to stay still (the result
// the viewer is reading, a card, a static read beat) is a declared hold and is not a freeze.

export const FREEZE_EDGE_SECONDS = 0.25; // tolerance around an expected change and around a hold edge

/**
 * Where the picture is declared to stay still in one mapped cue-sheet beat, or null when the sheet cannot place it.
 * From max(last transition action_time, transition result.visible_at) to slot_end; a beat with no transitions (a card, a proved read
 * beat) holds from its slot_start. Actions or a result without a program time declare nothing.
 */
// Recompute semantics from capture evidence, never a cue-plan declaration. Legacy
// observations without a saved visible target remain conservative change points.
export function receiptSemantics(beat, item, receipt, result = false) {
  // Encoded first-visible evidence declares a transition, never a static-state waiver.
  if (result && item?.physical_observation) return null;
  const clip = receipt?.clips?.[beat.screen?.clip];
  const index = result ? item?.receipt_expectation_index : item?.receipt_event_index;
  if (!clip || !Number.isInteger(index) || index < 0) return null;
  const event = (result ? clip.expectations : clip.actions)?.[index];
  if (!event) return null;
  const time = toClipTime(clip, result ? event.observedAt : event.tStart ?? event.t);
  if (!Number.isFinite(time) || !Number.isFinite(item.clip_time) || Math.abs(time - item.clip_time) > 0.0011) return null;
  const boxValid = (b) => b && [b.x, b.y, b.w, b.h].every(Number.isFinite) && b.w > 0 && b.h > 0;
  if (result) {
    if (event.observed === true && event.alreadyVisible === true && event.state === 'visible' && boxValid(event.targetBox)
      && typeof item.label === 'string' && item.label.length > 0 && String(event.label).toLowerCase().includes(item.label.toLowerCase())
      && event.observedAt >= event.at && !(clip.actions || []).some((a) => ['click', 'tap', 'type', 'upload', 'fill', 'wheel', 'goto'].includes(a.type) && a.t >= event.at && a.t <= event.observedAt)) return 'observation';
    return null;
  }
  if (event.type !== 'point' || item.kind !== 'point' || !event.label || event.target !== item.target) return null;
  const mark = (clip.beats || []).find((b) => b.label === event.label && Number.isFinite(b.approxStartSeconds) && Math.abs(b.approxStartSeconds - event.t) <= 0.1 && boxValid(b.box));
  const box = boxValid(event.targetBox) ? event.targetBox : mark?.box;
  const moves = (clip.actions || []).slice(0, index).filter((a) => a.type === 'move' && Number.isFinite(a.t) && a.t <= event.t && a.t >= event.t - 2);
  const last = moves.at(-1);
  if (!box || ![event.x, event.y].every(Number.isFinite) || !last || last.x !== event.x || last.y !== event.y
    || !moves.some((m) => Number.isFinite(m.x) && Number.isFinite(m.y) && (m.x !== last.x || m.y !== last.y))) return null;
  if (event.x < box.x || event.x > box.x + box.w || event.y < box.y || event.y > box.y + box.h) return null;
  return 'pointer-arrival';
}

export function declaredHold(beat, receipt = null) {
  const end = [beat.slot_end, beat.screen?.visible_until].find(Number.isFinite);
  const begin = [beat.slot_start, beat.screen?.visible_from].find(Number.isFinite);
  if (!Number.isFinite(end)) return null;
  const actions = (beat.actions || []).filter((a) => receiptSemantics(beat, a, receipt) !== 'pointer-arrival');
  const times = actions.map((a) => a.action_time).filter(Number.isFinite);
  const observation = receiptSemantics(beat, beat.result, receipt, true) === 'observation';
  const visible = observation ? null : beat.result?.visible_at;
  const resultTimed = Number.isFinite(visible);
  if (resultTimed) times.push(visible);
  if (times.length) { const from = Math.max(...times); return from < end ? { beat: beat.beat, from, until: end, kind: resultTimed ? 'after-result' : 'after-action' } : null; }
  if (!actions.length && (!beat.result || observation) && Number.isFinite(begin)) return { beat: beat.beat, from: begin, until: end, kind: 'static-beat' };
  return null;
}

/** Conservative transition times, excluding only receipt-proved pointer arrivals / existing-state observations. */
export function expectedChangePoints(beats, edl = null, receipt = null) {
  const pts = [];
  (beats || []).forEach((b, i) => {
    if (i > 0 && b.screen?.changes_from_previous && b.screen.kind !== 'hold' && Number.isFinite(b.screen.visible_from)) pts.push({ beat: b.beat, t: b.screen.visible_from, what: `screen "${b.beat}"` });
    for (const a of b.actions || []) if (Number.isFinite(a.action_time) && receiptSemantics(b, a, receipt) !== 'pointer-arrival') pts.push({ beat: b.beat, t: a.action_time, what: `${a.kind} "${a.label || a.target}"` });
    if (Number.isFinite(b.result?.visible_at) && receiptSemantics(b, b.result, receipt, true) !== 'observation') pts.push({ beat: b.beat, t: b.result.visible_at, what: `result "${b.result.label}"` });
  });
  for (const e of edl || []) {
    const t = Number(e.startSeconds);
    if (!Number.isFinite(t) || t <= 0.05 || pts.some((p) => Math.abs(p.t - t) < 0.05)) continue;
    const b = (beats || []).find((x) => t >= x.slot_start - 1e-6 && t < x.slot_end - 1e-6);
    pts.push({ beat: b?.beat ?? null, t, what: `clip "${e.clip ?? (e.segments || []).join('+')}"` });
  }
  return pts.sort((x, y) => x.t - y.t);
}

/**
 * Judge one exact-frame freeze ({ start, end, duration }) against the cue sheet.
 *   stalled        it covers (+/- FREEZE_EDGE_SECONDS) a point where change is expected, whatever its length
 *   ignore         at most maxFreezeSeconds
 *   declared-hold  wholly inside a declared hold of at most maxHoldSeconds
 *   overlong-hold  wholly inside a declared hold, but longer than maxHoldSeconds
 *   undeclared     longer than maxFreezeSeconds and outside every declared hold
 */
export function classifyFreeze(freeze, { beats, edl = null, receipt = null, maxFreezeSeconds = SYNC_DEFAULTS.maxFreezeSeconds, maxHoldSeconds = SYNC_DEFAULTS.maxHoldSeconds } = {}) {
  const e = FREEZE_EDGE_SECONDS;
  const stalled = expectedChangePoints(beats, edl, receipt).filter((p) => freeze.start <= p.t - e && freeze.end >= p.t + e);
  if (stalled.length) return { verdict: 'stalled', stalled, hold: null };
  if (!(freeze.duration > maxFreezeSeconds)) return { verdict: 'ignore', stalled, hold: null };
  const hold = (beats || []).map((b) => declaredHold(b, receipt)).filter(Boolean).find((h) => freeze.start >= h.from - e && freeze.end <= h.until + e) || null;
  if (!hold) return { verdict: 'undeclared', stalled, hold: null };
  return { verdict: freeze.duration > maxHoldSeconds ? 'overlong-hold' : 'declared-hold', stalled, hold };
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

// Native file selection is an action, not a pointer click or proof of successful import.
// Validate the recorder's success-only receipt before admitting it to either gate.
export function uploadEventProblems(event) {
  const problems = [];
  if (event?.type !== 'upload' || event.method !== 'locator.setInputFiles') problems.push('native upload method missing');
  if (![event?.tStart, event?.tEnd, event?.t].every((t) => Number.isFinite(t) && t >= 0)
      || event.tStart > event.tEnd || event.tEnd > event.t) problems.push('upload timestamps must be finite, nonnegative and ordered');
  if (typeof event?.target !== 'string' || !event.target.trim()) problems.push('upload target missing');
  const file = event?.file;
  if (typeof file?.name !== 'string' || !file.name.trim() || /[\\/]/.test(file.name)
      || !Number.isSafeInteger(file?.bytes) || file.bytes <= 0
      || !/^[a-f0-9]{64}$/.test(file?.sha256 || '')
      || typeof file?.mimeType !== 'string' || !file.mimeType.trim()) problems.push('upload file identity missing or malformed');
  if (['x', 'y', 'targetBox'].some((key) => event && Object.hasOwn(event, key))) problems.push('upload must not invent pointer geometry');
  return problems;
}

export function fillEventProblems(event) {
  const problems = [];
  if (event?.type !== 'fill' || event.method !== 'locator.fill') problems.push('native fill method missing');
  if (![event?.tStart, event?.tEnd, event?.t].every((t) => Number.isFinite(t) && t >= 0)
      || event.tStart > event.tEnd || event.tEnd > event.t) problems.push('fill timestamps must be finite, nonnegative and ordered');
  if (typeof event?.label !== 'string' || !event.label.trim() || typeof event?.target !== 'string' || !event.target.trim()) problems.push('fill label or target missing');
  if (!['text', 'search', 'email', 'url', 'tel', 'number', 'date', 'datetime-local', 'time', 'month', 'week', 'textarea'].includes(event?.inputType)
      || typeof event?.value !== 'string') problems.push('fill input type or readback value invalid');
  const box = event?.targetBox;
  if (!box || ![box.x, box.y, box.w, box.h].every(Number.isFinite) || box.w <= 0 || box.h <= 0) problems.push('fill target bounds missing or invalid');
  if (['x', 'y', 'chars'].some((key) => event && Object.hasOwn(event, key))) problems.push('fill must not claim a click or keystrokes');
  return problems;
}
