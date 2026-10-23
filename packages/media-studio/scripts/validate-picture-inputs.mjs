#!/usr/bin/env node
// Refuse a Remotion render whose clock, numbers, spotlight words, takes, or props are not the ones the film locked.
// Usage: node validate-picture-inputs.mjs <jobRoot> [--props kit/props.json]
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { anchorMisses, clockAccepted, factDrift, pictureScripts, roleProblems, takeProblems } from './picture-gates.mjs';

const argv = process.argv.slice(2);
const flag = (name) => { const index = argv.indexOf(name); return index >= 0 ? argv[index + 1] : null; };
const positional = argv.filter((arg, index) => !arg.startsWith('--') && !(index > 0 && argv[index - 1].startsWith('--')));
const jobRoot = positional[0];
if (!jobRoot) { console.error('Usage: node validate-picture-inputs.mjs <jobRoot> [--props <file>]'); process.exit(1); }
const root = resolve(jobRoot);
const errors = [];
const fail = (message) => errors.push(message);
const readJson = (rel) => JSON.parse(readFileSync(join(root, rel), 'utf8').replace(/^\uFEFF/, ''));

const lockPath = join(root, 'story', 'fact-lock.json');
if (!existsSync(lockPath)) fail('story/fact-lock.json is missing; lock the approved numbers before a fluff rewrite');
const narrationPath = ['story/locked-script.txt', 'story/narration.md', 'story/screenplay.json'].map((rel) => join(root, rel)).find(existsSync);
if (!narrationPath) fail('no narration to check against the fact lock');
if (existsSync(lockPath) && narrationPath) {
  const lock = readJson('story/fact-lock.json');
  const narration = narrationPath.endsWith('.json')
    ? (readJson(relative(root, narrationPath))?.scenes || []).map((scene) => scene.narration || scene.text || '').join('\n')
    : readFileSync(narrationPath, 'utf8');
  const drift = factDrift((lock.numbers || []).join(' '), narration);
  if (!drift.ok) fail(`narration numbers changed: missing ${drift.missing.join(', ') || 'none'}; added ${drift.added.join(', ') || 'none'}`);
}

const scripts = pictureScripts(root).flat();
const propsFlag = flag('--props');
if (scripts.length && !propsFlag) fail('a picture script requires --props, passed as one argument');
if (propsFlag) {
  const propsPath = resolve(root, propsFlag);
  if (!existsSync(propsPath) || statSync(propsPath).size === 0) fail(`Remotion props file is missing or empty: ${propsFlag}`);
  else { try { JSON.parse(readFileSync(propsPath, 'utf8')); } catch (error) { fail(`Remotion props file is not JSON: ${error.message}`); } }
}

if (scripts.length) {
  const timing = {};
  for (const line of scripts) {
    const rel = join('voice', 'align', `${line.id}.json`);
    const path = join(root, rel);
    if (!existsSync(path)) { fail(`${line.id} has no aligner report at voice/align/${line.id}.json`); continue; }
    const report = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
    const clock = clockAccepted(report);
    if (!clock.ok) { fail(`${line.id}: ${clock.reason}`); continue; }
    timing[line.id] = { s: Number(report.lineStart ?? 0), words: report.words || [] };
  }
  for (const miss of anchorMisses(scripts, timing)) fail(miss);
  const speakers = existsSync(join(root, 'story', 'speakers.json')) ? readJson('story/speakers.json') : {};
  for (const problem of roleProblems(scripts, speakers)) fail(problem);
}

function listed(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return listed(path);
    return [path];
  });
}
const voiceRoots = [join(root, 'voice')];
const films = join(root, 'films');
if (existsSync(films)) {
  for (const name of readdirSync(films)) {
    const voice = join(films, name, 'voice');
    if (existsSync(voice)) voiceRoots.push(voice);
  }
}
const takes = voiceRoots.flatMap(listed).filter((path) => /\.(wav|mp3)$/i.test(path)).map((path) => {
  const pass = existsSync(path.replace(/\.wav$/i, '.PASS.json')) || existsSync(join(path, '..', 'PASS.json'));
  return { name: path.slice(root.length + 1), pass };
});
for (const problem of takeProblems(takes)) fail(problem);

if (errors.length) {
  for (const message of errors) console.error(`[picture-inputs] ${message}`);
  process.exit(1);
}
console.log(JSON.stringify({ ok: true, lines: scripts.length }));
