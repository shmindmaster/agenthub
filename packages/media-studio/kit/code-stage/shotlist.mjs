// Shot-list parser for the code-walkthrough stage (code + diagram shots). Pure: no I/O, no browser.
// Contract: kit/code-stage/README.md. A shot list names REAL files at a git ref; this module only validates and
// normalizes it into a per-shot timeline of stage events. build-stage.mjs reads the files and writes the receipt.
//
// Shot kinds:
//   code     { id, kind:'code', file, ref?, lines:[a,b], startLine? (first line in view before the reveal scroll), highlight:[[a,b],...], callout?:{line,text}, zoom?, pointer?,
//              holdSeconds?, crossRef?: {file, ref?, lines, highlight?, callout?, label?} | [...], cues?: [...] }
//   diagram  { id, kind:'diagram', title, kicker?, nodes:[{id,label,sub?}], edges?:[[from,to,label?]], lit?, holdSeconds?, cues?: [...] }
// Cues bind an event to the narration: { event, at } (seconds from shot start) or { event, word, occurrence?, lead? }
// resolved against the shot's word timings ([{ text|word, start, end }] from STT). Events:
//   code:    reveal | pointer:<k> | highlight:<i> | callout | crossref:<i> | crossref:<i>:highlight | crossref:<i>:callout
//   diagram: node:<id> | lit
// Events without a cue keep a default pace so a shot always plays end to end.

export const SCHEMA_VERSION = '1.0.0';
const ID = /^[A-Za-z][A-Za-z0-9_-]{0,31}$/;

export class ShotListError extends Error {
  constructor(errors) { super('invalid shot list:\n  - ' + errors.join('\n  - ')); this.errors = errors; }
}

const isInt = (n) => Number.isInteger(n) && n > 0;
const range = (r) => Array.isArray(r) && r.length === 2 && isInt(r[0]) && isInt(r[1]) && r[0] <= r[1];
const within = (r, outer) => r[0] >= outer[0] && r[1] <= outer[1];
const relPath = (p) => typeof p === 'string' && p.length > 0 && !/^[A-Za-z]:|^[\\/]|(^|[\\/])\.\.([\\/]|$)/.test(p);
const normPath = (p) => p.replace(/\\/g, '/');

function normWords(words) {
  if (!Array.isArray(words)) return [];
  return words
    .filter((w) => !w.type || w.type === 'word')
    .map((w) => ({ text: String(w.text ?? w.word ?? '').trim(), start: Number(w.start), end: Number(w.end ?? w.start) }))
    .filter((w) => w.text && Number.isFinite(w.start));
}
const bare = (t) => String(t).toLowerCase().replace(/[^a-z0-9]/g, '');

/** Seconds for a cue: explicit `at`, or the start of the n-th occurrence of `word` (one or more words) in the word timings. */
export function resolveCue(cue, words, where = 'cue') {
  if (typeof cue.at === 'number') { if (cue.at < 0) throw new Error(`${where}: at must be >= 0`); return cue.at; }
  if (typeof cue.word === 'string') {
    const target = cue.word.split(/\s+/).map(bare).filter(Boolean);
    const ws = normWords(words);
    let seen = 0;
    for (let i = 0; i + target.length <= ws.length; i++) {
      if (target.every((t, k) => bare(ws[i + k].text) === t)) {
        seen += 1;
        if (seen === (cue.occurrence || 1)) return Math.max(0, Math.round((ws[i].start + (cue.lead ?? 0)) * 1000) / 1000);
      }
    }
    throw new Error(`${where}: cue word "${cue.word}" (occurrence ${cue.occurrence || 1}) not found in the narration words`);
  }
  throw new Error(`${where}: cue needs "at" (seconds) or "word"`);
}

function checkCallout(c, lines, where, errors) {
  if (c == null) return null;
  if (typeof c !== 'object' || !isInt(c.line) || typeof c.text !== 'string' || !c.text.trim()) { errors.push(`${where}.callout needs {line, text}`); return null; }
  if (lines && (c.line < lines[0] || c.line > lines[1])) errors.push(`${where}.callout.line ${c.line} is outside lines ${lines[0]}-${lines[1]}`);
  if (c.text.length > 90) errors.push(`${where}.callout.text is ${c.text.length} chars; keep it under 90`);
  return { line: c.line, text: c.text.trim() };
}

function checkSpan(o, where, errors) {
  if (!relPath(o.file)) errors.push(`${where}.file must be a repo-relative path without ".." (got ${JSON.stringify(o.file)})`);
  if (!range(o.lines)) errors.push(`${where}.lines must be [start, end] 1-based with start <= end`);
  else if (o.lines[1] - o.lines[0] + 1 > 60) errors.push(`${where}.lines spans ${o.lines[1] - o.lines[0] + 1} lines; a walkthrough shot shows at most 60`);
  const hl = o.highlight ?? [];
  if (!Array.isArray(hl)) errors.push(`${where}.highlight must be an array of [start, end]`);
  const highlight = [];
  (Array.isArray(hl) ? hl : []).forEach((h, i) => {
    if (!range(h)) errors.push(`${where}.highlight[${i}] must be [start, end]`);
    else if (range(o.lines) && !within(h, o.lines)) errors.push(`${where}.highlight[${i}] ${h[0]}-${h[1]} is outside lines ${o.lines[0]}-${o.lines[1]}`);
    else highlight.push([h[0], h[1]]);
  });
  return highlight;
}

/**
 * Validate and normalize a shot list. `words` maps shot id -> word timings (optional).
 * Returns { schemaVersion, repo, ref, viewport, shots:[{..., events:[{t, event}], durationSeconds}] } or throws ShotListError.
 */
export function parseShotList(input, { words = {} } = {}) {
  const errors = [];
  const doc = typeof input === 'string' ? JSON.parse(input.replace(/^﻿/, '')) : input;
  if (!doc || typeof doc !== 'object') throw new ShotListError(['shot list must be a JSON object']);
  if (doc.schemaVersion && String(doc.schemaVersion).split('.')[0] !== SCHEMA_VERSION.split('.')[0]) errors.push(`schemaVersion ${doc.schemaVersion} is not compatible with ${SCHEMA_VERSION}`);
  const needsRepo = (doc.shots || []).some((s) => s && (s.kind || (s.nodes ? 'diagram' : 'code')) === 'code');
  if (needsRepo && (typeof doc.repo !== 'string' || !doc.repo)) errors.push('repo (absolute path to the git repository, read-only) is required for code shots');
  const ref = doc.ref || 'HEAD';
  const viewport = doc.viewport || { width: 1280, height: 800 };
  if (!isInt(viewport.width) || !isInt(viewport.height)) errors.push('viewport must be {width, height}');
  if (!Array.isArray(doc.shots) || !doc.shots.length) errors.push('shots must be a non-empty array');
  const seen = new Set();
  const shots = [];
  (Array.isArray(doc.shots) ? doc.shots : []).forEach((s, idx) => {
    const where = `shots[${idx}]${s && s.id ? ' (' + s.id + ')' : ''}`;
    if (!s || typeof s !== 'object') { errors.push(`${where} must be an object`); return; }
    if (!ID.test(String(s.id || ''))) errors.push(`${where}.id must match ${ID}`);
    else if (seen.has(s.id)) errors.push(`${where}.id is duplicated`);
    seen.add(s.id);
    const kind = s.kind || (s.nodes ? 'diagram' : 'code');
    const holdSeconds = s.holdSeconds ?? 1.5;
    if (typeof holdSeconds !== 'number' || holdSeconds < 0 || holdSeconds > 8) errors.push(`${where}.holdSeconds must be 0-8 (visual bible: no dead hold over 8 s)`);
    const shotWords = s.words || words[s.id] || [];
    const out = { id: s.id, kind, holdSeconds, targetSeconds: s.targetSeconds ?? null };
    const defaults = [];
    if (kind === 'code') {
      out.file = typeof s.file === 'string' ? normPath(s.file) : s.file;
      out.ref = s.ref || ref;
      out.lines = s.lines;
      out.startLine = s.startLine ?? null;
      if (out.startLine != null && !isInt(out.startLine)) errors.push(`${where}.startLine must be a 1-based line number`);
      out.highlight = checkSpan(s, where, errors);
      out.callout = checkCallout(s.callout, range(s.lines) ? s.lines : null, where, errors);
      out.zoom = s.zoom ?? 1.4;
      if (typeof out.zoom !== 'number' || out.zoom < 1 || out.zoom > 2.2) errors.push(`${where}.zoom must be 1.0-2.2`);
      out.pointer = Array.isArray(s.pointer) ? s.pointer.map((p) => ({ line: p && p.line, click: p && p.click !== false })) : null;
      const lo = Math.min(range(s.lines) ? s.lines[0] : 1, isInt(s.startLine) ? s.startLine : Infinity);
      if (out.pointer) out.pointer.forEach((p, i) => { if (!isInt(p.line) || (range(s.lines) && (p.line < lo || p.line > s.lines[1]))) errors.push(`${where}.pointer[${i}] needs a line between startLine/lines start and lines end`); });
      const xr = s.crossRef ?? s['cross-ref'];
      const xrs = xr == null ? [] : Array.isArray(xr) ? xr : [xr];
      out.crossRefs = xrs.map((x, i) => {
        const w = `${where}.crossRef[${i}]`;
        if (!x || typeof x !== 'object') { errors.push(`${w} must be an object`); return null; }
        const highlight = checkSpan(x, w, errors);
        return {
          file: typeof x.file === 'string' ? normPath(x.file) : x.file,
          ref: x.ref || out.ref,
          lines: x.lines,
          highlight: highlight.length ? highlight : (range(x.lines) ? [[x.lines[0], x.lines[1]]] : []),
          callout: checkCallout(x.callout, range(x.lines) ? x.lines : null, w, errors),
          label: x.label || null,
        };
      }).filter(Boolean);
      // Default pace: reveal, then each highlight, the callout, then each cross-ref with its highlight and callout.
      let t = 0.4;
      defaults.push(['reveal', t]); t += 1.6;
      (out.pointer || []).forEach((_, k) => { defaults.push([`pointer:${k}`, t]); t += 1.2; });
      out.highlight.forEach((_, i) => { defaults.push([`highlight:${i}`, t]); t += 2.5; });
      if (out.callout) { defaults.push(['callout', t]); t += 2.5; }
      out.crossRefs.forEach((x, i) => {
        defaults.push([`crossref:${i}`, t]); t += 2.2;
        defaults.push([`crossref:${i}:highlight`, t]); t += 1.8;
        if (x.callout) { defaults.push([`crossref:${i}:callout`, t]); t += 2.5; }
      });
    } else if (kind === 'diagram') {
      out.title = s.title || '';
      out.kicker = s.kicker || '';
      out.footer = s.footer || '';
      if (!Array.isArray(s.nodes) || s.nodes.length < 2 || s.nodes.length > 8) errors.push(`${where}.nodes must hold 2-8 nodes`);
      out.nodes = (Array.isArray(s.nodes) ? s.nodes : []).map((n, i) => {
        if (!n || !ID.test(String(n.id || ''))) errors.push(`${where}.nodes[${i}].id must match ${ID}`);
        if (!n || typeof n.label !== 'string' || !n.label.trim()) errors.push(`${where}.nodes[${i}].label is required`);
        else if (n.label.trim().split(/\s+/).length > 3) errors.push(`${where}.nodes[${i}].label "${n.label}" is over 3 words`);
        return { id: n && n.id, label: n && n.label, sub: (n && n.sub) || '' };
      });
      const ids = new Set(out.nodes.map((n) => n.id));
      out.edges = (s.edges || out.nodes.slice(1).map((n, i) => [out.nodes[i].id, n.id])).map((e, i) => {
        if (!Array.isArray(e) || !ids.has(e[0]) || !ids.has(e[1])) errors.push(`${where}.edges[${i}] must be [fromId, toId, label?] of known nodes`);
        return { from: e && e[0], to: e && e[1], label: (e && e[2]) || '' };
      });
      out.lit = s.lit ?? null;
      out.litChip = s.litChip || null;
      if (out.lit != null && !ids.has(out.lit)) errors.push(`${where}.lit "${out.lit}" is not a node id`);
      let t = 0.5;
      out.nodes.forEach((n) => { defaults.push([`node:${n.id}`, t]); t += 1.0; });
      if (out.lit) defaults.push(['lit', t + 0.4]);
    } else {
      errors.push(`${where}.kind must be "code" or "diagram"`);
      return;
    }
    const known = new Map(defaults);
    (Array.isArray(s.cues) ? s.cues : []).forEach((c, i) => {
      const w = `${where}.cues[${i}]`;
      if (!c || typeof c.event !== 'string') { errors.push(`${w}.event is required`); return; }
      if (!known.has(c.event)) { errors.push(`${w}.event "${c.event}" is not an event of this shot (${[...known.keys()].join(', ')})`); return; }
      try { known.set(c.event, resolveCue(c, shotWords, w)); } catch (e) { errors.push(e.message); }
    });
    out.events = [...known.entries()].map(([event, t]) => ({ event, t })).sort((a, b) => a.t - b.t);
    // A cross-ref highlight or callout cannot play before its file is opened; a diagram cannot light a node before it appears.
    for (const e of out.events) {
      const m = /^crossref:(\d+):(highlight|callout)$/.exec(e.event);
      if (m) { const open = out.events.find((x) => x.event === `crossref:${m[1]}`); if (open && open.t > e.t) errors.push(`${where}: ${e.event} at ${e.t}s precedes crossref:${m[1]} at ${open.t}s`); }
      if (e.event === 'lit') { const n = out.events.find((x) => x.event === `node:${out.lit}`); if (n && n.t > e.t) errors.push(`${where}: lit at ${e.t}s precedes node:${out.lit} at ${n.t}s`); }
    }
    const last = out.events.length ? out.events[out.events.length - 1].t : 0;
    out.durationSeconds = Math.round(Math.max(last + holdSeconds, out.targetSeconds || 0) * 100) / 100;
    shots.push(out);
  });
  if (errors.length) throw new ShotListError(errors);
  return { schemaVersion: SCHEMA_VERSION, repo: doc.repo || null, ref, refLabel: typeof doc.refLabel === 'string' ? doc.refLabel : null, viewport, title: doc.title || '', shots };
}

/** Files a parsed shot list needs read, deduplicated by ref + path. */
export function filesToRead(parsed) {
  const m = new Map();
  for (const s of parsed.shots) {
    if (s.kind !== 'code') continue;
    for (const f of [{ file: s.file, ref: s.ref }, ...s.crossRefs.map((x) => ({ file: x.file, ref: x.ref }))]) m.set(`${f.ref}\u0000${f.file}`, f);
  }
  return [...m.values()];
}
