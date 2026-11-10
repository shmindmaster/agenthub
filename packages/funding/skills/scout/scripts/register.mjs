#!/usr/bin/env node
// Funding register helper. Reads only; it never writes the register.
//   node register.mjs check <root>            validate the register's shape
//   node register.mjs seen  <root> <query>    has this program been decided already?
//   node register.mjs due   <root> [days]     rows not verified in the last N days (default 30)
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export const REGISTER = 'Funding Opportunity Register.csv';
export const COLUMNS = [
  'id', 'program', 'organizer', 'category', 'cash_or_noncash', 'amount', 'deadline',
  'deadline_status', 'best_product', 'runner_up', 'eligibility', 'fit_score',
  'priority_score', 'band', 'decision', 'decision_date', 'reopen_if', 'official_url', 'verified',
];
const BANDS = ['', 'P1', 'P2', 'P3', 'P4'];
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
// The shape alone admits 2026-02-30; a real date survives a round trip through Date.
const isDate = (value) => ISO_DATE.test(value || '') && !Number.isNaN(Date.parse(`${value}T00:00:00Z`))
  && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
// Decisions that close an opportunity. A closed row is recommended again only when reopen_if holds.
const CLOSED = /^(skip|rejected|declined|dropped|expired|not-eligible)/i;

export function parseCsv(text) {
  const rows = [];
  let row = [], field = '', quoted = false;
  const src = text.replace(/^﻿/, '');
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (quoted) {
      if (c === '"' && src[i + 1] === '"') { field += '"'; i++; }
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && src[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.some((v) => v !== '')) rows.push(row);
      row = [];
    } else field += c;
  }
  row.push(field);
  if (row.some((v) => v !== '')) rows.push(row);
  return rows;
}

export function loadRegister(root) {
  const path = join(root, REGISTER);
  if (!existsSync(path)) throw new Error(`Register not found: ${path}. Set FUNDING_RECORDS_ROOT or pass the records root; do not create a second register.`);
  const [header, ...body] = parseCsv(readFileSync(path, 'utf8'));
  return { path, header, rows: body.map((cells, i) => ({ line: i + 2, cells, ...Object.fromEntries(header.map((h, j) => [h, (cells[j] ?? '').trim()])) })) };
}

export function check(root) {
  const { header, rows } = loadRegister(root);
  const problems = [];
  if (header.join(',') !== COLUMNS.join(',')) problems.push(`header differs from the register columns: expected ${COLUMNS.join(',')}`);
  const ids = new Set();
  for (const r of rows) {
    const at = `line ${r.line} (${r.id || 'no id'})`;
    if (r.cells.length !== header.length) problems.push(`${at}: ${r.cells.length} cells, header has ${header.length}; quote any value that contains a comma`);
    if (!r.id) problems.push(`${at}: id is empty`);
    else if (ids.has(r.id.toLowerCase())) problems.push(`${at}: duplicate id`);
    ids.add((r.id || '').toLowerCase());
    for (const col of ['program', 'category', 'decision']) if (!r[col]) problems.push(`${at}: ${col} is empty`);
    if (!isDate(r.verified)) problems.push(`${at}: verified must be a real YYYY-MM-DD date`);
    if (r.decision_date && !isDate(r.decision_date)) problems.push(`${at}: decision_date must be a real YYYY-MM-DD date`);
    if (r.official_url && !/^https:\/\//.test(r.official_url)) problems.push(`${at}: official_url must be an https URL`);
    if (!BANDS.includes(r.band || '')) problems.push(`${at}: band must be P1 to P4 or empty`);
    for (const col of ['fit_score', 'priority_score']) {
      if (r[col] && !(Number.isInteger(Number(r[col])) && Number(r[col]) >= 0 && Number(r[col]) <= 100)) problems.push(`${at}: ${col} must be a whole number 0 to 100 or empty`);
    }
  }
  return { rows: rows.length, problems };
}

const norm = (s) => (s || '').toLowerCase().replace(/^https?:\/\/(www\.)?/, '').replace(/[^a-z0-9]+/g, ' ').trim();

export function seen(root, query) {
  const q = norm(query);
  if (q.length < 3) throw new Error('Give a program name, id or URL of at least three characters.');
  const { rows } = loadRegister(root);
  const hit = (v) => { const n = norm(v); return n.length >= 3 && (n.includes(q) || q.includes(n)); };
  const register = rows.filter((r) => hit(r.id) || hit(r.program) || hit(r.official_url)).map((r) => ({
    id: r.id, program: r.program, decision: r.decision, decision_date: r.decision_date,
    reopen_if: r.reopen_if, verified: r.verified, closed: CLOSED.test(r.decision),
  }));
  // The narrative files hold rejected lists the register does not repeat row by row.
  const notes = [];
  for (const file of readdirSync(root).filter((f) => f.toLowerCase().endsWith('.md'))) {
    readFileSync(join(root, file), 'utf8').split(/\r?\n/).forEach((text, i) => {
      if (norm(text).includes(q)) notes.push({ file, line: i + 1, text: text.trim().slice(0, 240) });
    });
  }
  return { query, register, notes: notes.slice(0, 40), notesTruncated: notes.length > 40 };
}

export function due(root, days = 30, today = new Date()) {
  if (!Number.isFinite(days) || days < 0) throw new Error('days must be a number that is zero or greater, for example: due <root> 30');
  const cutoff = new Date(today.getTime() - days * 86400000).toISOString().slice(0, 10);
  return loadRegister(root).rows
    .filter((r) => !CLOSED.test(r.decision) && (r.verified || '') < cutoff)
    .map((r) => ({ id: r.id, program: r.program, deadline: r.deadline, verified: r.verified, official_url: r.official_url }));
}

function main([command, root = process.env.FUNDING_RECORDS_ROOT, arg]) {
  if (!command || !root) {
    console.error('Usage: node register.mjs check|seen|due <records root> [query|days]');
    return 2;
  }
  if (command === 'check') {
    const result = check(root);
    console.log(JSON.stringify(result, null, 2));
    return result.problems.length ? 1 : 0;
  }
  if (command === 'seen') { console.log(JSON.stringify(seen(root, arg), null, 2)); return 0; }
  if (command === 'due') { console.log(JSON.stringify(due(root, arg ? Number(arg) : 30), null, 2)); return 0; }
  console.error(`Unknown command: ${command}`);
  return 2;
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop())) {
  try { process.exitCode = main(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 2; }
}
