#!/usr/bin/env node
// Capture pre-flight: catch the mistakes that otherwise surface only after a long Playwright take. Static: scenes.mjs is
// never imported, its text is parsed, so no browser, no product and no network are touched. record-job.mjs runs this before
// it opens a browser (use --skip-preflight there to bypass, recorded as recordings.preflight = 'skipped').
//
// Usage: node validate-capture-preflight.mjs <jobRoot> [--out qa/capture-preflight.json] [--typing-ms 55] [--typing-overhead-s 0.85]
//
// Inputs (all under <jobRoot>; the product repository is never read):
//   capture/scenes.mjs             required. `export const order = [...]`, the `scenes` object (async S05( / S05: async / S05( /
//                                  'S05': (h) => {...} / shorthand), `covers`, and per scene the typeText(<locator>, <text>, {...})
//                                  calls and the `label:` of click / typeText / pointAt / hoverHold. Top-level helper functions a
//                                  scene calls are followed; top-level string constants resolve typeText text.
//   story/narration-timeline.json  required. Segment ids, scene ids (`scene`, else the id without its trailing letter), seconds.
//   story/storyboard.json          optional. Beats; screen beats = visualMode 'screen', or omitted on a product-screencast job.
//   story/capture-plan.json        optional. Scenes of kind 'interaction' need a scene function.
//   story/cue-plan.json            optional. Beat keys must be timeline ids; each narrated action and the result must find a
//                                  keyword in that line (sync-lib wordMatches, stem tolerant) or the action cannot be timed.
//   job.json                       optional (kind).
//
// Errors  order id without a scene function; capture-plan interaction scene without one; scene function not in the timeline
//         and not covered; cue-plan beat key not in the timeline; a cue-plan action or result none of whose keywords is in its
//         line; typing budget: sum over typeText calls of chars x delay + overhead per call exceeds the scene's narration seconds
//         (sum of its segments and its covers; calls labelled "(pre-roll)" are off the narration clock and not counted; a
//         per-call `delay:` option replaces --typing-ms).
// Warnings storyboard screen beat without a scene function; scene function with no label on any click / point / type; a labelled
//         action matching no cue-plan action label of its beat; a cue-plan keyword absent while another matches; typeText text
//         that is not a literal or a top-level string constant (not budgeted).
// Report qa/capture-preflight.json { ok, errors, warnings, inputs, thresholds, ids, typing }. Exit 1 on errors.
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const L = await import(pathToFileURL(libPath).href);

const USAGE = 'Usage: node validate-capture-preflight.mjs <jobRoot> [--out qa/capture-preflight.json] [--typing-ms 55] [--typing-overhead-s 0.85]';
const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const pos = argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--')));
if (!pos[0]) { console.error(USAGE); process.exit(1); }
const root = resolve(pos[0]);
const num = (name, d) => { const v = Number(flag(name, d)); if (!Number.isFinite(v) || v < 0) { console.error(`${name} must be a number >= 0\n${USAGE}`); process.exit(2); } return v; };
const TYPING_MS = num('--typing-ms', 55);
const TYPING_OVERHEAD_S = num('--typing-overhead-s', 0.85);
const outPath = resolve(root, flag('--out', 'qa/capture-preflight.json'));

const errors = [];
const warnings = [];
const inputs = {};
const readJson = (rel) => { const p = join(root, rel); return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8').replace(/^﻿/, '')) : null; };
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const bind = (key, rel) => { const p = join(root, rel); if (existsSync(p)) { inputs[key] = { path: rel, sha256: sha(p) }; return true; } return false; };
const round3 = (v) => Math.round(v * 1000) / 1000;
const uniq = (xs) => [...new Set(xs)];

// ------------------------------------------------------------------ source scanning

/**
 * Blank the comments and the contents of strings, template literals and regex literals, keeping every offset.
 * Returns { code, struct }: code = source with comments blanked (strings intact); struct = code with literal contents replaced by '_'
 * (quotes kept), so braces, parentheses and keywords can be found without being fooled by text in a label or a comment.
 */
function scan(src) {
  const n = src.length;
  const code = src.split('');
  const struct = src.split('');
  const blank = (a, b, arr) => { for (let k = a; k < b; k++) if (arr[k] !== '\n' && arr[k] !== '\r') arr[k] = ' '; };
  const mask = (a, b) => { for (let k = a; k < b; k++) if (struct[k] !== '\n' && struct[k] !== '\r') struct[k] = '_'; };
  const REGEX_AFTER_WORD = new Set(['return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'await', 'yield', 'void', 'delete', 'throw', 'new']);
  let prevSig = '', lastWord = '';
  let i = 0;
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '/' && d === '/') { let j = i; while (j < n && src[j] !== '\n') j++; blank(i, j, code); blank(i, j, struct); i = j; continue; }
    if (c === '/' && d === '*') { let j = src.indexOf('*/', i + 2); j = j < 0 ? n : j + 2; blank(i, j, code); blank(i, j, struct); i = j; continue; }
    if (c === '\'' || c === '"') {
      let j = i + 1;
      while (j < n && src[j] !== c && src[j] !== '\n') j += src[j] === '\\' ? 2 : 1;
      mask(i + 1, Math.min(j, n)); i = Math.min(j + 1, n); prevSig = '"'; lastWord = ''; continue;
    }
    if (c === '`') {
      let j = i + 1, depth = 0;
      while (j < n) {
        if (src[j] === '\\') { j += 2; continue; }
        if (depth === 0 && src[j] === '`') break;
        if (src[j] === '$' && src[j + 1] === '{') { depth++; j += 2; continue; }
        if (depth > 0 && src[j] === '{') depth++;
        if (depth > 0 && src[j] === '}') depth--;
        j++;
      }
      mask(i + 1, Math.min(j, n)); i = Math.min(j + 1, n); prevSig = '"'; lastWord = ''; continue;
    }
    if (c === '/' && (prevSig === '' || '(,=:[!&|?{};+-*%<>~^'.includes(prevSig) || (/[\w$]/.test(prevSig) && REGEX_AFTER_WORD.has(lastWord)))) {
      let j = i + 1, inClass = false;
      while (j < n && src[j] !== '\n') {
        if (src[j] === '\\') { j += 2; continue; }
        if (src[j] === '[') inClass = true; else if (src[j] === ']') inClass = false; else if (src[j] === '/' && !inClass) break;
        j++;
      }
      if (j < n && src[j] === '/') { mask(i + 1, j); i = j + 1; while (i < n && /[a-z]/i.test(src[i])) i++; prevSig = '"'; lastWord = ''; continue; }
    }
    if (!/\s/.test(c)) {
      prevSig = c;
      if (/[\w$]/.test(c)) { let j = i; while (j < n && /[\w$]/.test(src[j])) j++; lastWord = src.slice(i, j); i = j; continue; }
      lastWord = '';
    }
    i++;
  }
  return { code: code.join(''), struct: struct.join('') };
}

function matchClose(s, openIdx) {
  let depth = 0;
  for (let i = openIdx; i < s.length; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}
const depthMap = (s) => { const d = new Int32Array(s.length + 1); let cur = 0; for (let i = 0; i < s.length; i++) { d[i] = cur; const c = s[i]; if (c === '(' || c === '[' || c === '{') cur++; else if (c === ')' || c === ']' || c === '}') cur--; } return d; };

/** Top-level comma split of struct[a, b) -> [{ start, end }] trimmed. */
function splitTop(s, a, b) {
  const out = [];
  let depth = 0, from = a;
  for (let i = a; i < b; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) { out.push([from, i]); from = i + 1; }
  }
  out.push([from, b]);
  return out.map(([x, y]) => { while (x < y && /\s/.test(s[x])) x++; while (y > x && /\s/.test(s[y - 1])) y--; return { start: x, end: y }; }).filter((r) => r.end > r.start);
}

const unescape = (t) => t.replace(/\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)/g, (_, e) => (e[0] === 'u' || e[0] === 'x' ? String.fromCharCode(parseInt(e.slice(1), 16)) : ({ n: '\n', t: '\t', r: '\r' }[e] ?? e)));
/** The string literal that starts at code[i] (quote, apostrophe or template without ${}); { value, end } or null. */
function readString(code, i) {
  const q = code[i];
  if (q !== '\'' && q !== '"' && q !== '`') return null;
  let j = i + 1;
  while (j < code.length && code[j] !== q) { if (code[j] === '\\') j++; else if (q === '`' && code[j] === '$' && code[j + 1] === '{') return null; j++; }
  return j < code.length ? { value: unescape(code.slice(i + 1, j)), end: j + 1 } : null;
}
/** Concatenation of string literals and known string constants in code[a, b): the string, or null when anything else is in it. */
function evalString(code, struct, a, b, consts) {
  let i = a, out = '', expectTerm = true;
  while (i < b) {
    while (i < b && /\s/.test(code[i])) i++;
    if (i >= b) break;
    if (!expectTerm) { if (code[i] !== '+') return null; i++; expectTerm = true; continue; }
    const lit = readString(code, i);
    if (lit && lit.end <= b) { out += lit.value; i = lit.end; expectTerm = false; continue; }
    const id = /^[A-Za-z_$][\w$]*/.exec(struct.slice(i, b));
    if (id && consts.has(id[0])) { out += consts.get(id[0]); i += id[0].length; expectTerm = false; continue; }
    return null;
  }
  return expectTerm ? null : out;
}
const stringsIn = (code, a, b) => { const out = []; for (let i = a; i < b; i++) { const lit = readString(code, i); if (lit && lit.end <= b) { out.push(lit.value); i = lit.end - 1; } } return out; };

/** Top-level `const NAME = 'text'` (and concatenations of those) -> Map. Used for typeText text that is a named constant. */
function stringConstants(code, struct, range = null) {
  const consts = new Map();
  const a = range ? range[0] : 0, b = range ? range[1] : struct.length;
  const depth = range ? null : depthMap(struct);
  const re = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*/g;
  re.lastIndex = a;
  let m;
  while ((m = re.exec(struct)) && m.index < b) {
    if (depth && depth[m.index] !== 0) continue;
    const start = m.index + m[0].length;
    let end = start, d = 0;
    while (end < b) { const c = struct[end]; if (c === '(' || c === '[' || c === '{') d++; else if (c === ')' || c === ']' || c === '}') { if (d === 0) break; d--; } else if ((c === ';' || c === ',' || c === '\n') && d === 0) { if (c === '\n' && /^\s*\+/.test(struct.slice(end + 1, end + 40))) { end++; continue; } if (c === '\n' && /\+\s*$/.test(struct.slice(start, end).trimEnd())) { end++; continue; } break; } end++; }
    const v = evalString(code, struct, start, end, consts);
    if (v !== null) consts.set(m[1], v);
  }
  return consts;
}

// ------------------------------------------------------------------ scenes.mjs model

function parseScenes(source) {
  const { code, struct } = scan(source);
  const depth = depthMap(struct);
  const model = { order: [], scenes: [], covers: {}, helpers: new Map(), consts: stringConstants(code, struct), code, struct };

  const find = (re) => { const g = new RegExp(re.source, 'g'); let m; while ((m = g.exec(struct))) if (depth[m.index] === 0) return m; return null; };

  const orderM = find(/(?:export\s+)?const\s+order\s*=\s*\[/);
  if (orderM) { const open = orderM.index + orderM[0].length - 1; model.order = stringsIn(code, open + 1, matchClose(struct, open)); }

  const coversM = find(/(?:export\s+)?const\s+covers\s*=\s*\{/);
  if (coversM) {
    const open = coversM.index + coversM[0].length - 1, close = matchClose(struct, open);
    const re = /(?:([A-Za-z_$][\w$]*)|(['"])_*\2)\s*:\s*\[/g;
    re.lastIndex = open + 1;
    let m;
    while ((m = re.exec(struct)) && m.index < close) {
      const bracket = m.index + m[0].length - 1;
      const key = m[1] || code.slice(m.index + 1, m.index + m[0].indexOf(m[2], 1));
      model.covers[key] = stringsIn(code, bracket + 1, matchClose(struct, bracket));
      re.lastIndex = matchClose(struct, bracket) + 1;
    }
  }

  // Top-level helper functions a scene may call: `function f(`, `async function f(`, `const f = async (...) => {`, `const f = async function`.
  const fnRes = [/(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\(/g, /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:function\s*[\w$]*\s*)?\(/g, /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?[A-Za-z_$][\w$]*\s*=>/g];
  for (const base of fnRes) {
    const re = new RegExp(base.source, 'g');
    let m;
    while ((m = re.exec(struct))) {
      if (depth[m.index] !== 0) continue;
      const body = bodyAfter(struct, m.index + m[0].length - (m[0].endsWith('(') ? 1 : 0), m[0].endsWith('(') ? 'params' : 'arrow');
      if (body && !model.helpers.has(m[1])) model.helpers.set(m[1], body);
    }
  }

  const scenesM = find(/(?:export\s+)?const\s+scenes\s*=\s*\{/);
  if (scenesM) {
    const open = scenesM.index + scenesM[0].length - 1, close = matchClose(struct, open);
    let i = open + 1;
    const member = /(?:async\s+)?\*?\s*([A-Za-z_$][\w$]*|'_*'|"_*")\s*(?=[(:,}])/y;
    while (i < close) {
      while (i < close && /[\s,]/.test(struct[i])) i++;
      if (i >= close) break;
      if (struct.startsWith('...', i)) { i = skipMember(struct, i, close); continue; }
      member.lastIndex = i;
      const m = member.exec(struct);
      if (!m) { i = skipMember(struct, i, close); continue; }
      let name = m[1];
      if (name[0] === '\'' || name[0] === '"') name = code.slice(i + m[0].indexOf(name), i + m[0].indexOf(name) + name.length).slice(1, -1);
      let p = i + m[0].length;
      let body = null;
      if (struct[p] === '(') body = bodyAfter(struct, p, 'params');
      else if (struct[p] === ':') {
        let v = p + 1;
        while (/\s/.test(struct[v])) v++;
        const fnStart = /(?:async\s+)?function\s*\*?\s*[\w$]*\s*\(/y; fnStart.lastIndex = v;
        const arrowParen = /(?:async\s*)?\(/y; arrowParen.lastIndex = v;
        const arrowIdent = /(?:async\s+)?[A-Za-z_$][\w$]*\s*=>/y; arrowIdent.lastIndex = v;
        const ref = /[A-Za-z_$][\w$]*\s*(?=[,}])/y; ref.lastIndex = v;
        let f, a, id, r;
        if ((f = fnStart.exec(struct))) body = bodyAfter(struct, v + f[0].length - 1, 'params');
        else if ((a = arrowParen.exec(struct))) body = bodyAfter(struct, v + a[0].length - 1, 'params');
        else if ((id = arrowIdent.exec(struct))) body = bodyAfter(struct, v + id[0].length, 'arrow');
        else if ((r = ref.exec(struct))) body = { helperRef: r[0].trim() };
      } else body = { helperRef: name };       // shorthand member
      model.scenes.push({ name, body });
      i = skipMember(struct, p, close);
    }
  }
  return model;
}

/** Skip one object member starting inside it: to just after the next top-level comma (or the end). */
function skipMember(s, from, close) {
  let depth = 0;
  for (let i = from; i < close; i++) {
    const c = s[i];
    if (c === '(' || c === '[' || c === '{') depth++;
    else if (c === ')' || c === ']' || c === '}') depth--;
    else if (c === ',' && depth === 0) return i + 1;
  }
  return close;
}

/** Body range [start, end) of a function whose parameter list opens at s[at] ('params') or whose arrow `=>` precedes at s[at] ('arrow'). */
function bodyAfter(s, at, kind) {
  let q = at;
  if (kind === 'params') {
    const close = matchClose(s, at);
    if (close < 0) return null;
    q = close + 1;
  } else { const arrow = s.indexOf('=>', at); if (arrow < 0) return null; q = arrow; }
  while (q < s.length && /\s/.test(s[q])) q++;
  if (s.startsWith('=>', q)) { q += 2; while (q < s.length && /\s/.test(s[q])) q++; }
  if (s[q] === '{') { const end = matchClose(s, q); return end < 0 ? null : { start: q + 1, end }; }
  // Expression-bodied arrow: up to the next top-level comma or the closing of the enclosing literal.
  let depth = 0, e = q;
  while (e < s.length) { const c = s[e]; if (c === '(' || c === '[' || c === '{') depth++; else if (c === ')' || c === ']' || c === '}') { if (depth === 0) break; depth--; } else if ((c === ',' || c === ';') && depth === 0) break; e++; }
  return { start: q, end: e };
}

// ------------------------------------------------------------------ per-scene analysis

const CALL_RE = /(?<![\w$])(?:[A-Za-z_$][\w$]*\s*\.\s*)?(click|tap|pointAt|hoverHold|typeText)\s*\(/g;
const PRE_ROLL = /pre-?roll/i;

/** typeText calls and labelled actions in struct[start, end), following top-level helper functions the range calls. */
function analyse(model, range, visited = new Set()) {
  const { code, struct } = model;
  const out = { typeCalls: [], labels: [], labelled: false, onLabels: [] };
  const localConsts = new Map([...model.consts, ...stringConstants(code, struct, [range.start, range.end])]);
  const re = new RegExp(CALL_RE.source, 'g');
  re.lastIndex = range.start;
  let m;
  while ((m = re.exec(struct)) && m.index < range.end) {
    const kind = m[1];
    const open = m.index + m[0].length - 1;
    const close = matchClose(struct, open);
    if (close < 0) continue;
    const args = splitTop(struct, open + 1, close);
    if (!args.length) continue;                                         // locator.click(): not a helper call
    if (struct[args[0].start] === '{' && kind !== 'typeText') continue;  // locator.click({ force }): not a helper call
    const optsArg = kind === 'typeText' ? args[2] : args[1];
    let label = null, hasLabel = false, delayMs = null;
    if (optsArg && struct[optsArg.start] === '{') {
      const opts = code.slice(optsArg.start, optsArg.end);
      const lit = /\blabel\s*:\s*(['"`])((?:\\.|(?!\1).)*)\1/.exec(opts);
      if (lit) { label = unescape(lit[2]); hasLabel = true; } else if (/\blabel\s*(?=[:,}])/.test(opts)) hasLabel = true;
      const dm = /\bdelay\s*:\s*(\d+(?:\.\d+)?)/.exec(opts);
      if (dm) delayMs = Number(dm[1]);
    }
    if (hasLabel) { out.labelled = true; if (label) out.labels.push(label); }
    if (kind === 'typeText') {
      const expr = args[1];
      const text = expr ? evalString(code, struct, expr.start, expr.end, localConsts) : null;
      out.typeCalls.push({ chars: text === null ? null : text.length, delayMs, label, preRoll: !!label && PRE_ROLL.test(label), expr: expr ? code.slice(expr.start, expr.end).replace(/\s+/g, ' ').slice(0, 60) : '' });
    }
  }
  const onRe = /\.\s*on\s*\(\s*(['"])_*\1/g;
  onRe.lastIndex = range.start;
  while ((m = onRe.exec(struct)) && m.index < range.end) {
    const lit = readString(code, m.index + m[0].indexOf(m[1]));
    if (lit) out.onLabels.push(lit.value);
  }
  for (const [name, body] of model.helpers) {
    if (visited.has(name)) continue;
    const call = new RegExp(`(?<![\\w$.])${name.replace(/\$/g, '\\$')}\\s*\\(`, 'g');
    call.lastIndex = range.start;
    const hit = call.exec(struct);
    if (!hit || hit.index >= range.end) continue;
    visited.add(name);
    const inner = analyse(model, body, visited);
    out.typeCalls.push(...inner.typeCalls); out.labels.push(...inner.labels); out.onLabels.push(...inner.onLabels); out.labelled ||= inner.labelled;
  }
  return out;
}

// ------------------------------------------------------------------ run

const scenesRel = 'capture/scenes.mjs';
const timelineRel = 'story/narration-timeline.json';
let model = null;
if (bind('scenes', scenesRel)) model = parseScenes(readFileSync(join(root, scenesRel), 'utf8').replace(/^﻿/, ''));
else errors.push(`${scenesRel} is required: the pre-flight reads the scene functions from it`);
const timeline = bind('timeline', timelineRel) ? readJson(timelineRel) : null;
if (!timeline) errors.push(`${timelineRel} is required: lock and render the narration first (voice-first); scene ids, keywords and typing budgets are checked against it`);
const hasJob = bind('job', 'job.json');
const job = hasJob ? readJson('job.json') : null;
const storyboard = bind('storyboard', 'story/storyboard.json') ? readJson('story/storyboard.json') : null;
const capturePlan = bind('capturePlan', 'story/capture-plan.json') ? readJson('story/capture-plan.json') : null;
const cuePlan = bind('cuePlan', 'story/cue-plan.json') ? readJson('story/cue-plan.json') : null;

const segs = timeline?.segments || [];
const sceneOf = (seg) => seg.scene || String(seg.id).replace(/[a-z]$/, '');
const segIds = new Set(segs.map((s) => s.id));
const sceneIds = new Set(segs.map(sceneOf));
const inTimeline = (id) => segIds.has(id) || sceneIds.has(id);
const sbBeats = storyboard ? (storyboard.beats || storyboard.scenes || []) : [];
const cpScenes = capturePlan ? (capturePlan.scenes || []) : [];
const cueBeats = cuePlan?.beats && typeof cuePlan.beats === 'object' ? cuePlan.beats : {};
const productScreencast = job?.kind === 'product-screencast';

const sceneNames = model ? uniq(model.scenes.map((s) => s.name)) : [];
const covers = model?.covers || {};
const coveredBy = (id) => Object.entries(covers).some(([host, list]) => host !== id && list.includes(id));
const hasFn = (id) => sceneNames.includes(id) || sceneNames.includes(String(id).replace(/[a-z]$/, '')) || Object.entries(covers).some(([host, list]) => sceneNames.includes(host) && list.includes(id));

const screenBeats = sbBeats.filter((b) => b.visualMode === 'screen' || (b.visualMode === undefined && productScreencast)).map((b) => b.id).filter(Boolean);
const interactionScenes = cpScenes.filter((s) => s.kind === 'interaction').map((s) => s.sceneId).filter(Boolean);

if (model) {
  for (const id of model.order) if (!sceneNames.includes(id)) errors.push(`order lists ${id} but ${scenesRel} exports no scene function for it`);
  for (const id of interactionScenes) if (!hasFn(id)) errors.push(`capture-plan interaction scene ${id} has no scene function in ${scenesRel}`);
  if (timeline) {
    for (const name of sceneNames) {
      if (name.startsWith('_')) continue;
      const ok = inTimeline(name) || (covers[name] || []).some(inTimeline) || coveredBy(name);
      if (!ok) errors.push(`scene function ${name} has no narration segment in ${timelineRel} and is not listed in covers`);
    }
  }
  for (const id of screenBeats) if (!hasFn(id)) warnings.push(`storyboard screen beat ${id} has no scene function in ${scenesRel}`);
}

// Narration seconds per scene function: its own segments plus every segment its covers list.
const narrationSeconds = (name) => {
  const wanted = new Set([name, ...(covers[name] || [])]);
  return segs.filter((s) => wanted.has(s.id) || wanted.has(sceneOf(s))).reduce((n, s) => n + Number(s.durationSeconds || 0), 0);
};

// cue-plan against the timeline
const linesOf = (key) => segs.filter((s) => s.id === key || sceneOf(s) === key).map((s) => s.text || '').join(' ').trim();
const narrated = (a) => a && a.narrated !== false;
function checkKeywords(key, what, spec, line) {
  const kws = Array.isArray(spec.keywords) && spec.keywords.length ? spec.keywords : L.keywordsFromLabel(spec.label || spec.target || '');
  const keys = kws.flatMap((k) => L.textWords(k)).filter(L.isContentWord);
  if (!keys.length) return;
  const words = L.textWords(line);
  const missing = keys.filter((k) => !words.some((w) => L.wordMatches(w, k)));
  const shown = `cue-plan beat ${key} ${what} "${spec.label ?? ''}"`;
  if (missing.length === keys.length) errors.push(`${shown}: none of its keywords [${kws.join(', ')}] is in the narration "${line}"`);
  else for (const k of missing) warnings.push(`${shown}: keyword "${k}" is not in the narration "${line}"`);
}
if (timeline) {
  for (const [key, beat] of Object.entries(cueBeats)) {
    const line = linesOf(key);
    if (!line && !inTimeline(key)) { errors.push(`cue-plan beat ${key} is not a segment or scene in ${timelineRel}`); continue; }
    for (const a of Array.isArray(beat?.actions) ? beat.actions : []) if (narrated(a)) checkKeywords(key, 'action', a, line);
    if (beat?.result) checkKeywords(key, 'result', beat.result, line);
  }
}

// per scene: typing budget and labels
const typing = {};
const IGNORED_LABEL = /\bresult\b|pre-?roll|\btrace\b|^lead$/i;
if (model) {
  for (const sc of model.scenes) {
    let range = sc.body && sc.body.start !== undefined ? sc.body : null;
    if (!range && sc.body?.helperRef && model.helpers.has(sc.body.helperRef)) range = model.helpers.get(sc.body.helperRef);
    if (!range) continue;
    const a = analyse(model, range, new Set());
    if (!a.labelled && !a.onLabels.length) warnings.push(`${sc.name}: scene function has no label on any click, point or type`);
    const beatKeys = uniq([sc.name, ...(covers[sc.name] || [])]).filter((k) => cueBeats[k]);
    if (beatKeys.length) {
      const allowed = beatKeys.flatMap((k) => [...(cueBeats[k].actions || []).map((x) => x.label), cueBeats[k].result?.label]).filter(Boolean).map((x) => String(x).toLowerCase());
      for (const label of uniq([...a.labels, ...a.onLabels])) {
        const l = label.toLowerCase();
        if (IGNORED_LABEL.test(label) || allowed.some((x) => x === l || x.includes(l) || l.includes(x))) continue;
        warnings.push(`${sc.name}: label "${label}" matches no cue-plan action label for this beat`);
      }
    }
    if (!a.typeCalls.length) continue;
    const live = a.typeCalls.filter((c) => !c.preRoll && c.chars !== null);
    const preRollChars = a.typeCalls.filter((c) => c.preRoll && c.chars !== null).reduce((n, c) => n + c.chars, 0);
    for (const c of a.typeCalls) if (c.chars === null) warnings.push(`${sc.name}: typeText text is not a string literal or a top-level string constant (${c.expr}); its typing time is not budgeted`);
    const chars = live.reduce((n, c) => n + c.chars, 0);
    const seconds = round3(live.reduce((n, c) => n + (c.chars * (c.delayMs ?? TYPING_MS)) / 1000 + TYPING_OVERHEAD_S, 0));
    const budget = round3(narrationSeconds(sc.name));
    typing[sc.name] = { chars, seconds, budget, calls: live.length, ...(preRollChars ? { preRollChars } : {}), ...(a.typeCalls.some((c) => c.chars === null) ? { unresolved: a.typeCalls.filter((c) => c.chars === null).length } : {}) };
    if (timeline && live.length && budget > 0 && seconds > budget + 1e-9) {
      errors.push(`${sc.name}: typing takes ${seconds} s (${chars} chars at ${TYPING_MS} ms plus ${TYPING_OVERHEAD_S} s per call) but the scene's narration is ${budget} s`);
    }
  }
}

const ok = errors.length === 0;
const report = {
  generator: 'media-studio/validate-capture-preflight',
  schemaVersion: '1.0.0',
  ok,
  errors,
  warnings,
  inputs,
  thresholds: { typingMs: TYPING_MS, typingOverheadS: TYPING_OVERHEAD_S },
  ids: {
    order: model?.order || [],
    scenes: sceneNames,
    covers,
    timeline: uniq(segs.flatMap((s) => [s.id, sceneOf(s)])),
    storyboardScreen: screenBeats,
    capturePlanInteraction: interactionScenes,
    cuePlan: Object.keys(cueBeats),
  },
  typing,
};
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok, out: relative(root, outPath).replace(/\\/g, '/'), scenes: sceneNames.length, errors, warnings }));
if (!ok) process.exit(1);
