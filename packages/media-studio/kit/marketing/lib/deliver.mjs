// Delivery: copy the gated ads to the canonical library as `NN - Title (ratio).mp4` + .srt, update that folder's
// README (Marketing / sales films table and a per-film section), hash every delivered file, delete reproducible
// intermediates. The film number is computed at deliver time from what exists; it is never hardcoded.
import { copyFileSync, existsSync, openSync, closeSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileSha } from './util.mjs';

const NUMBER = /^(\d{2,3}) - /;

/** Numbers already used by files, README table rows / headings, and the brand's reserved list. */
export function usedNumbers({ files = [], readme = '', reserved = [] }) {
  const used = new Set(reserved.map(Number));
  for (const f of files) { const m = NUMBER.exec(f); if (m) used.add(Number(m[1])); }
  for (const line of readme.split(/\r?\n/)) {
    const m = /^\|\s*(\d{2,3}) - /.exec(line) || /^#{2,3}\s*(\d{2,3}) - /.exec(line);
    if (m) used.add(Number(m[1]));
  }
  return used;
}

/** Next free number: above every number ever used, so a retired number is never reused for a different film. */
export function nextFreeNumber(used) {
  let max = 0;
  for (const n of used) if (n > max) max = n;
  return max + 1;
}

export const pad2 = (n) => String(n).padStart(2, '0');
export const safeTitle = (t) => String(t).replace(/[\\/:*?"<>|]/g, '').replace(/\s+/g, ' ').trim();
export const deliveredName = (nn, title, ratio, ext) => `${pad2(nn)} - ${safeTitle(title)} (${ratio}).${ext}`;

export function mmss(seconds) {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/**
 * Insert/replace this ad's row in the Marketing / sales films table and its per-film section. Idempotent per number.
 * @param {string} text README contents
 * @param {{nn:number,title:string,lengths:string,audience:string,pitch:string,section:string}} e
 */
export function updateReadme(text, e) {
  const row = `| ${pad2(e.nn)} - ${safeTitle(e.title)} | ${e.lengths} | ${e.audience} | ${e.pitch} |`;
  const lines = text.split(/\r?\n/);
  const rowRe = new RegExp(`^\\|\\s*${pad2(e.nn)} - `);
  const existing = lines.findIndex((l) => rowRe.test(l));
  if (existing >= 0) lines[existing] = row;
  else {
    const head = lines.findIndex((l) => /^\|\s*Film\s*\|\s*Length\s*\|\s*For\s*\|/.test(l));
    if (head < 0) throw new Error('README has no "Marketing / sales films" table (| Film | Length | For | One-line pitch |)');
    let end = head + 1;
    while (end + 1 < lines.length && /^\|/.test(lines[end + 1])) end++;
    lines.splice(end + 1, 0, row);
  }
  let out = lines.join('\n');
  const headingRe = new RegExp(`^##\\s*${pad2(e.nn)} - [^\\n]*\\n[\\s\\S]*?(?=^## |(?![\\s\\S]))`, 'm');
  const section = `${e.section.trimEnd()}\n`;
  if (headingRe.test(out)) out = out.replace(headingRe, `${section}\n`);
  else out = `${out.trimEnd()}\n\n${section}`;
  return out.endsWith('\n') ? out : `${out}\n`;
}

/**
 * Deliver every ratio's gated mp4 + srt. Returns the delivery manifest.
 * @param {object} o { dir, readmePath, reserved, title, files:[{ratio, mp4, srt, seconds}], readmeEntry({nn,lengths}) -> entry, dryRun }
 */
export function deliverFiles(o) {
  const existingFiles = existsSync(o.dir) ? readdirSync(o.dir) : [];
  const readme = existsSync(o.readmePath) ? readFileSync(o.readmePath, 'utf8') : '';
  let nn = nextFreeNumber(usedNumbers({ files: existingFiles, readme, reserved: o.reserved || [] }));
  // Claim the number with an exclusive create so two concurrent deliveries cannot share it.
  for (;;) {
    const claim = join(o.dir, deliveredName(nn, o.title, o.files[0].ratio, 'mp4'));
    try { closeSync(openSync(claim, 'wx')); break; } catch (e) { if (e.code === 'EEXIST') { nn++; continue; } throw e; }
  }
  const delivered = [];
  for (const f of o.files) {
    const mp4 = join(o.dir, deliveredName(nn, o.title, f.ratio, 'mp4'));
    const srt = join(o.dir, deliveredName(nn, o.title, f.ratio, 'srt'));
    copyFileSync(f.mp4, mp4);
    if (f.srt && existsSync(f.srt)) copyFileSync(f.srt, srt);
    const row = { ratio: f.ratio, mp4, mp4Sha256: fileSha(mp4), mp4Bytes: statSync(mp4).size, srt: existsSync(srt) ? srt : null, srtSha256: existsSync(srt) ? fileSha(srt) : null, seconds: f.seconds };
    if (fileSha(f.mp4) !== row.mp4Sha256) throw new Error(`delivered copy of ${f.ratio} does not match the gated candidate`);
    delivered.push(row);
  }
  const lengths = o.files.map((f) => `${mmss(f.seconds)} (${f.ratio})`).join(' / ');
  const entry = o.readmeEntry({ nn, lengths, delivered });
  writeFileSync(o.readmePath, updateReadme(readme, { ...entry, nn, title: o.title, lengths }), 'utf8');
  return { nn, delivered, readme: o.readmePath };
}

export function deleteIntermediates(paths) {
  const removed = [];
  for (const p of paths) if (existsSync(p)) { rmSync(p, { recursive: true, force: true }); removed.push(p); }
  return removed;
}
