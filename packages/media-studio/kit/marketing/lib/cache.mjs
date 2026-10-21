// Content-hash stage cache. A stage's key is the hash of everything that can change its output (inputs, provider
// settings, stage version); its manifest lists the output files with their SHA-256. A rerun with the same key and
// intact outputs is skipped, so unchanged work never costs again.
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileSha, hashOf, readJson, writeJson } from './util.mjs';

export const STAGE_VERSIONS = { lint: 1, voice: 1, timing: 1, assets: 1, capture: 1, compose: 1, qa: 1, deliver: 1 };

export function stageKey(stage, inputs) {
  return hashOf({ stage, version: STAGE_VERSIONS[stage] ?? 1, inputs });
}

export function stageManifestPath(jobDir, stage, unit = 'all') {
  return join(jobDir, 'stages', stage, `${unit}.json`);
}

/** @returns {{hit:boolean, manifest?:object, reason?:string}} */
export function checkStage(jobDir, stage, unit, key) {
  const path = stageManifestPath(jobDir, stage, unit);
  if (!existsSync(path)) return { hit: false, reason: 'no previous run' };
  let manifest;
  try { manifest = readJson(path); } catch { return { hit: false, reason: 'unreadable manifest' }; }
  if (manifest.key !== key) return { hit: false, reason: 'inputs changed' };
  for (const out of manifest.outputs || []) {
    const abs = join(jobDir, out.path);
    if (!existsSync(abs)) return { hit: false, reason: `missing output ${out.path}` };
    if (out.sha256 && fileSha(abs) !== out.sha256) return { hit: false, reason: `output changed ${out.path}` };
  }
  return { hit: true, manifest };
}

export function writeStage(jobDir, stage, unit, key, data) {
  const outputs = (data.outputs || []).map((p) => ({ path: p, sha256: fileSha(join(jobDir, p)) }));
  const manifest = { stage, unit, key, version: STAGE_VERSIONS[stage] ?? 1, at: new Date().toISOString(), ...data, outputs };
  writeJson(stageManifestPath(jobDir, stage, unit), manifest);
  return manifest;
}
