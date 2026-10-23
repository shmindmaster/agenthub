// Pre-render checks for a kinetic film. Remotion burns word timing into the picture, so these run before the render.
// Whisper is a transcript check. The picture clock is an aligner report. A fluff rewrite must not change a number.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Package scripts sit beside kit/. The synced copies sit in briefing-kit/screencast and _shared/tools.
function findCaptionLib(start) {
  let dir = start;
  for (let depth = 0; depth < 6; depth += 1) {
    const direct = [join(dir, 'kit', 'marketing', 'lib', 'captions.mjs'), join(dir, 'marketing', 'lib', 'captions.mjs')].find((path) => existsSync(path));
    if (direct) return direct;
    if (existsSync(dir)) {
      for (const name of readdirSync(dir)) {
        const nested = join(dir, name, 'marketing', 'lib', 'captions.mjs');
        if (existsSync(nested)) return nested;
      }
    }
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

const captionLib = findCaptionLib(dirname(fileURLToPath(import.meta.url)));
if (!captionLib) throw new Error('marketing caption chunker not found beside picture-gates.mjs');
const { chunkWords } = await import(pathToFileURL(captionLib).href);

export const MOUNT_LEAD = 0.25;
export const SPOT_HOLD = 0.45;
export const DURATION_TOLERANCE = 1.5;

const ONES = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9,
  ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16,
  seventeen: 17, eighteen: 18, nineteen: 19,
};
const TENS = { twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90 };
const ENROLLED = new Set(['sarosh', 'ryan', 'vivian', 'aiden']);

export const normToken = (value) => String(value ?? '').toLowerCase().replace(/[^a-z0-9#]/g, '');

const round3 = (n) => Math.round(n * 1000) / 1000;

function parseUnder100(words, index) {
  const word = words[index];
  if (TENS[word] != null) {
    const next = words[index + 1];
    if (ONES[next] != null && ONES[next] < 10) return { value: TENS[word] + ONES[next], next: index + 2 };
    return { value: TENS[word], next: index + 1 };
  }
  if (ONES[word] != null) return { value: ONES[word], next: index + 1 };
  return null;
}

function parseNumberAt(words, index) {
  const word = words[index];
  if (/^\d+(?:\.\d+)?$/.test(word)) return { value: Number(word), next: index + 1 };
  if (ONES[word] != null && ONES[word] < 10 && words[index + 1] === 'hundred') {
    let value = ONES[word] * 100;
    let cursor = index + 2;
    if (words[cursor] === 'and') cursor += 1;
    const rest = parseUnder100(words, cursor);
    if (rest) { value += rest.value; cursor = rest.next; }
    return { value, next: cursor };
  }
  return parseUnder100(words, index);
}

const canonicalNumber = (value, percent) => {
  const text = Number.isInteger(value) ? String(value) : String(value);
  return percent ? `${text}%` : text;
};

/** Number tokens a narration commits to. "fifty nine percent" and "59%" are the same token. */
export function factNumbers(text) {
  const words = String(text ?? '').toLowerCase().replace(/%/g, ' percent').replace(/[^a-z0-9.\s]/g, ' ').split(/\s+/).filter(Boolean);
  const found = [];
  let index = 0;
  while (index < words.length) {
    const parsed = parseNumberAt(words, index);
    if (!parsed) { index += 1; continue; }
    let cursor = parsed.next;
    const percent = words[cursor] === 'percent';
    if (percent) cursor += 1;
    found.push(canonicalNumber(parsed.value, percent));
    index = cursor;
  }
  return found;
}

function bagDiff(left, right) {
  const bag = new Map();
  for (const token of right) bag.set(token, (bag.get(token) || 0) + 1);
  const missing = [];
  for (const token of left) {
    const count = bag.get(token) || 0;
    if (count === 0) missing.push(token);
    else bag.set(token, count - 1);
  }
  return missing;
}

/** Multiset equality. A changed percent is both a missing token and an added one. */
export function factDrift(lockedText, narrationText) {
  const locked = factNumbers(lockedText);
  const narration = factNumbers(narrationText);
  const missing = bagDiff(locked, narration);
  const added = bagDiff(narration, locked);
  return { ok: missing.length === 0 && added.length === 0, missing, added, locked, narration };
}

export function clockAccepted(report) {
  const method = String(report?.method || '');
  if (method === 'forced-alignment' || method === 'forced-alignment-on-encoded') return { ok: true, method };
  return { ok: false, method, reason: method ? `timing method ${method} cannot drive the picture; Whisper is a transcript check` : 'timing method is missing; the picture clock is ai.ps1 align' };
}

export function normalizeAlignWords(raw) {
  const words = Array.isArray(raw?.words) ? raw.words : [];
  return {
    words: words.map((word, index) => {
      const start = Number(word.start ?? word.s);
      const next = words[index + 1];
      const nextStart = next ? Number(next.start ?? next.s) : NaN;
      const end = Number.isFinite(word.end) ? Number(word.end) : Number.isFinite(word.e) ? Number(word.e) : (Number.isFinite(nextStart) ? nextStart : start + 0.2);
      return { w: word.w ?? word.word ?? word.text, start, end };
    }),
  };
}

function wordIndex(words, needle) {
  const token = normToken(needle);
  if (!token) return -1;
  for (let index = 0; index < words.length; index += 1) {
    const got = normToken(words[index].w ?? words[index].word ?? words[index].text);
    if (!got) continue;
    if (got === token) return index;
    if (token.length >= 4 && got.startsWith(token) && /^s(es)?$/.test(got.slice(token.length))) return index;
  }
  return -1;
}

export function collectAnchors(node, found = []) {
  if (Array.isArray(node)) {
    for (const item of node) collectAnchors(item, found);
  } else if (node && typeof node === 'object') {
    for (const [key, value] of Object.entries(node)) {
      if (key === 'w' && typeof value === 'string') found.push(value);
      else collectAnchors(value, found);
    }
  }
  return found;
}

function targetOf(lineId, raw) {
  if (!raw.includes(':')) return { id: lineId, needle: raw };
  const split = raw.indexOf(':');
  const left = raw.slice(0, split);
  return { id: `${lineId[0] || ''}${left.slice(1)}`, needle: raw.slice(split + 1) };
}

/**
 * Every spotlight token must be a spoken word, and tokens on one line must hit that line in spoken order.
 * Returns the misses. A render with any miss is refused.
 */
export function anchorMisses(script, timingById) {
  const misses = [];
  const lastIndex = new Map();
  for (const line of script || []) {
    if (!line?.v) continue;
    for (const raw of collectAnchors(line.v)) {
      const { id, needle } = targetOf(line.id, raw);
      const timing = timingById?.[id];
      if (!timing) { misses.push(`${line.id} missing line ${id}`); continue; }
      const index = wordIndex(timing.words || [], needle);
      if (index < 0) { misses.push(`${line.id} word ${raw}`); continue; }
      const previous = lastIndex.get(id);
      if (previous != null && index < previous) misses.push(`${line.id} word ${raw} is out of spoken order on ${id}`);
      lastIndex.set(id, index);
    }
  }
  return misses;
}

/** Card mount (line start − 0.25s) and the spotlight ramp (spoken word, word + 0.45s). */
export function designedCuts(script, timingById, offset = 0) {
  const cuts = new Set([0]);
  const misses = anchorMisses(script, timingById);
  for (const line of script || []) {
    const row = timingById?.[line.id];
    if (!row) continue;
    if (line.v) cuts.add(round3(Number(row.s) + offset - MOUNT_LEAD));
    for (const raw of collectAnchors(line.v)) {
      const { id, needle } = targetOf(line.id, raw);
      const timing = timingById?.[id];
      const index = timing ? wordIndex(timing.words || [], needle) : -1;
      if (!timing || index < 0) continue;
      const at = Number(timing.words[index].s ?? timing.words[index].start) + offset;
      cuts.add(round3(at));
      cuts.add(round3(at + SPOT_HOLD));
    }
  }
  return { cuts: [...cuts].sort((a, b) => a - b), misses };
}

export function pictureScripts(root) {
  const scripts = [];
  const one = join(root, 'story', 'picture-script.json');
  if (existsSync(one)) {
    const body = JSON.parse(readFileSync(one, 'utf8').replace(/^\uFEFF/, ''));
    scripts.push(Array.isArray(body) ? body : body.lines || []);
  }
  const films = join(root, 'kit', 'src', 'films');
  if (existsSync(films)) {
    for (const name of readdirSync(films).filter((file) => file.endsWith('.script.json')).sort()) {
      scripts.push(JSON.parse(readFileSync(join(films, name), 'utf8').replace(/^\uFEFF/, '')));
    }
  }
  return scripts;
}

export function propsArg(propsPath) {
  if (!propsPath || typeof propsPath !== 'string') throw new Error('Remotion props file is required');
  return `--props=${propsPath}`;
}

export function renderArgv({ cli, composition, propsPath, outFile, extra = [] }) {
  return [cli, 'render', 'src/index.ts', composition, outFile, propsArg(propsPath), ...extra];
}

export function durationAgrees(pictureSeconds, voiceSeconds, tolerance = DURATION_TOLERANCE) {
  return Number.isFinite(pictureSeconds) && Number.isFinite(voiceSeconds) && Math.abs(pictureSeconds - voiceSeconds) <= tolerance;
}

export function roleProblems(script, speakers) {
  const problems = [];
  const seen = new Set();
  const flat = JSON.stringify(script ?? []);
  for (const line of script || []) {
    const speaker = String(line?.speaker || 'sarosh');
    const id = speaker.toLowerCase();
    if (ENROLLED.has(id) || seen.has(id)) continue;
    seen.add(id);
    const spec = speakers?.[speaker] || speakers?.[id];
    if (!spec?.dramatization || typeof spec.card !== 'string' || !spec.card.trim()) {
      problems.push(`${line.id} speaker ${speaker} is a role voice and needs dramatization plus the card text that says so`);
      continue;
    }
    if (!flat.includes(spec.card)) problems.push(`${line.id} speaker ${speaker} card text is not in the picture script`);
  }
  return problems;
}

export function takeProblems(files) {
  const problems = [];
  for (const file of files || []) {
    const name = String(file.name || '');
    if (name.toLowerCase().endsWith('.mp3')) problems.push(`${name} is not a picture take; a failed reading cannot sit beside the wav`);
    if (name.toLowerCase().endsWith('.wav') && !file.pass) problems.push(`${name} has no PASS receipt`);
  }
  return problems;
}

function wrapLines(text, width = 42) {
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let current = '';
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length > width && current) { lines.push(current); current = word; }
    else current = next;
  }
  if (current) lines.push(current);
  if (lines.length <= 2) return lines;
  const mid = Math.ceil(words.length / 2);
  return [words.slice(0, mid).join(' '), words.slice(mid).join(' ')];
}

const stamp = (seconds) => {
  const ms = Math.max(0, Math.round(seconds * 1000));
  const pad = (n, width = 2) => String(n).padStart(width, '0');
  return `${pad(Math.floor(ms / 3600000))}:${pad(Math.floor(ms / 60000) % 60)}:${pad(Math.floor(ms / 1000) % 60)},${pad(ms % 1000, 3)}`;
};

/**
 * Captions from aligned words. A cue that is still faster than 20 characters a second, because the next
 * word starts immediately, stays whole and is marked rate-bound. It is not split down to an orphan line.
 */
export function captionCues(words) {
  const chunks = chunkWords(words || [], { maxCps: 20 });
  const rateBound = [];
  const cues = chunks.map((chunk, index) => {
    const duration = chunk.endSec - chunk.startSec;
    const fast = !(duration > 0) || chunk.text.length / duration > 20;
    if (fast) rateBound.push(index + 1);
    return { index: index + 1, lines: wrapLines(chunk.text), text: chunk.text, start: chunk.startSec, end: chunk.endSec, rateBound: fast };
  });
  return { cues, rateBound };
}

export function cuesToSrt(cues) {
  return cues.map((cue) => `${cue.index}\n${stamp(cue.start)} --> ${stamp(cue.end)}\n${cue.lines.join('\n')}\n`).join('\n');
}
