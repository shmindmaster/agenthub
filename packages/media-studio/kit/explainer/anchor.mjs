/**
 * The word clock: one implementation of "@word" anchors, shared by the
 * briefing builder and the explainer builder.
 *
 * Both builders must place a reveal at the same second for the same anchor, or
 * two renders of one script drift apart. `build-picture.mjs` re-exports these
 * names so its public API and tests are unchanged.
 */

const LEAD_IN_SECONDS = 0.08;
const LEAD_OUT_SECONDS = 0.1;
const FLOOR_SECONDS = 0.3;

export const norm = (word) => (word || '').toLowerCase().replace(/[^a-z0-9']/g, '');

/**
 * `@word`, `@word#2` (third occurrence), `@word+0.3`, `@word-0.2`.
 * Returns null for anything that is not an anchor.
 */
export const parseAnchor = (spec) => {
  const m = /^@([^#+\-\s][^#+]*?)(?:#(\d+))?(?:([+-]\d+(?:\.\d+)?))?$/.exec(String(spec).trim());
  if (!m) return null;
  return { word: m[1], nth: m[2] ? Number(m[2]) : 0, offset: m[3] ? Number(m[3]) : 0 };
};

/**
 * Scene edges from cue ends plus their gaps. The last edge is the program
 * length, so a picture built from these edges is exactly as long as the voice.
 */
export const sceneEdges = (cueSheet) => {
  const edges = [0];
  cueSheet.cues.forEach((cue, index) =>
    edges.push(index === cueSheet.cues.length - 1 ? cueSheet.totalSeconds : cue.end + (cue.gapAfter ?? 0)),
  );
  return edges;
};

/** Word boundaries from a synthesizer receipt, in the order they were spoken. */
export const wordsOf = (receipt) => {
  const list = Array.isArray(receipt) ? receipt : receipt?.word_boundaries ?? [];
  return list.filter(
    (entry) => String(entry.boundary_type).includes('Word') && String(entry.text).trim(),
  );
};

/**
 * A synthesizer can merge words ("November 19"); the first word of a merged
 * boundary matches. A percent number matches its numeric anchor ("@37").
 */
export const findWord = (words, spec) => {
  const anchor = parseAnchor(spec);
  if (!anchor) throw new Error(`bad anchor "${spec}"`);
  const wanted = norm(anchor.word);
  const hits = words.filter(
    (entry) =>
      norm(entry.text) === wanted ||
      norm(entry.text).startsWith(`${wanted}percent`) ||
      norm(String(entry.text).trim().split(/\s+/)[0]) === wanted,
  );
  if (!hits[anchor.nth]) throw new Error(`word "${anchor.word}" #${anchor.nth} is not spoken`);
  return hits[anchor.nth];
};

/**
 * Seconds from the scene start at which the anchored word is spoken.
 * `sceneStart` is the scene's edge snapped to the frame grid, so the result is
 * frame-addressable rather than floating between frames.
 */
export const anchorSeconds = ({ spec, cueStart, words, sceneStart, fps = 30, snap = false }) => {
  const anchor = parseAnchor(spec);
  if (!anchor) throw new Error(`bad anchor "${spec}"`);
  if (!words.length) throw new Error(`no word boundaries for anchor "${spec}"`);
  const hit = findWord(words, spec);
  const leadIn = Math.max(0, words[0].start_seconds - LEAD_IN_SECONDS);
  const raw = cueStart + (hit.start_seconds - leadIn) - sceneStart + anchor.offset;
  const timed = snap ? Math.round(raw * fps) / fps : raw;
  return Math.max(FLOOR_SECONDS, +(timed - LEAD_OUT_SECONDS).toFixed(2));
};

/**
 * Resolve every `at` string inside a visual tree. Numbers pass through; a
 * missing word is a hard error, never a guessed time.
 *
 * A timeline event prints its `at` as the date, so an event carries its time in
 * `beat` instead.
 */
const inEvent = (path) => /\.events\[\d+\]$/.test(path);

/** The field that carries time at this place in a visual tree. */
export const timeKeyAt = (path) => (inEvent(path) ? 'beat' : 'at');

export const resolveAnchors = (node, resolveOne, errors, path = 'visual') => {
  if (Array.isArray(node)) return node.map((item, index) => resolveAnchors(item, resolveOne, errors, `${path}[${index}]`));
  if (node && typeof node === 'object') {
    const out = {};
    for (const [key, value] of Object.entries(node)) {
      if (key === timeKeyAt(path) && typeof value === 'string') {
        try {
          out[key] = resolveOne(value);
        } catch (error) {
          errors.push(`${path}.${key}: ${error.message}`);
          out[key] = FLOOR_SECONDS;
        }
      } else {
        out[key] = resolveAnchors(value, resolveOne, errors, `${path}.${key}`);
      }
    }
    return out;
  }
  return node;
};
