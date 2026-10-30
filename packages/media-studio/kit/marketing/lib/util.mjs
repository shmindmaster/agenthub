// Small shared helpers for the marketing video generator (mvg). No third-party dependencies.
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { dirname } from 'node:path';

export const sha256 = (data) => createHash('sha256').update(data).digest('hex');
export const fileSha = (path) => sha256(readFileSync(path));

/** Deterministic JSON: object keys sorted recursively, undefined dropped. The basis of every cache key. */
export function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value === undefined ? null : value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  const keys = Object.keys(value).filter((k) => value[k] !== undefined).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
}
export const hashOf = (value) => sha256(canonical(value));

export function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8').replace(/^﻿/, ''));
}
export function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  renameSync(tmp, path);
}
export const ensureDir = (dir) => { mkdirSync(dir, { recursive: true }); return dir; };
export const exists = existsSync;
export const round = (n, d = 3) => Math.round(n * 10 ** d) / 10 ** d;
export const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
export const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');

/** Local AI is off (owner direction 2026-10-29): no code path starts a local model, TTS or ASR runtime. */
export const LOCAL_AI_OFF = 'Local AI is off; use the hosted route (kit/cloud/cloud-ai.mjs align, Azure TTS/STT)';
/** Default for an injectable local-provider seam: refuses with the hosted route instead of starting anything. */
export const localAiOff = (what) => async () => { throw new Error(`${what}: ${LOCAL_AI_OFF}`); };

/** Mask a secret to its last four characters for any log line. */
export const mask = (secret) => (secret ? `…${String(secret).slice(-4)}` : '(unset)');

export function words(text) {
  return String(text || '').match(/[A-Za-z0-9$%][A-Za-z0-9$%'’.\-]*/g) || [];
}
export function sentences(text) {
  return String(text || '').split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
}
