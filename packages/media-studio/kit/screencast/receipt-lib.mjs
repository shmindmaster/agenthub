// The capture receipt: one writer contract and one reader contract, shared by the recorder, the backfill tools and the gates.
// The seal (contentSha256 over the canonical JSON of everything else) is tamper evidence, not a signature: it shows that a
// job script changed the receipt after the recorder wrote it. A timing need belongs in capture/manifest.json (videoLead).
export const RECEIPT_SCHEMA = '1.1.0';
export const UNSEALED_SCHEMA = '1.0.0';

import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const canonical = (v) => {
  if (Array.isArray(v)) return `[${v.map((x) => canonical(x === undefined ? null : x)).join(',')}]`;
  if (v && typeof v === 'object') return `{${Object.keys(v).filter((k) => v[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(',')}}`;
  return JSON.stringify(v);
};
const contentHash = ({ contentSha256, ...rest }) => createHash('sha256').update(canonical(rest)).digest('hex');

export function sealReceipt(receipt) {
  const body = JSON.parse(JSON.stringify({ ...receipt, schemaVersion: RECEIPT_SCHEMA }));
  return { ...body, contentSha256: contentHash(body) };
}

/** { state: 'sealed' | 'unsealed' | 'edited' | 'unknown-schema', message } */
export function receiptIntegrity(receipt) {
  const v = receipt?.schemaVersion;
  if (v !== RECEIPT_SCHEMA && v !== UNSEALED_SCHEMA) return { state: 'unknown-schema', message: `unknown receipt schemaVersion ${JSON.stringify(v ?? null)}; expected ${RECEIPT_SCHEMA}` };
  if (v === UNSEALED_SCHEMA && receipt.contentSha256 === undefined) return { state: 'unsealed', message: `capture/receipt.json is not sealed (schema ${UNSEALED_SCHEMA}): re-record with the current kit` };
  if (receipt.contentSha256 !== contentHash(receipt)) return { state: 'edited', message: 'capture/receipt.json was edited after it was written: re-record the changed takes (timing corrections go in capture/manifest.json videoLead)' };
  return { state: 'sealed', message: null };
}

export const readReceipt = (path) => JSON.parse(readFileSync(path, 'utf8').replace(/^﻿/, ''));

/** For every tool that adds to a receipt: an edited or unknown receipt is never extended, or the next seal would hide the edit. */
export function openReceipt(path, fresh) {
  if (!existsSync(path)) return fresh;
  const receipt = readReceipt(path);
  const { state, message } = receiptIntegrity(receipt);
  if (state === 'edited' || state === 'unknown-schema') throw new Error(message);
  return receipt;
}
/** Backfill tools keep an unsealed receipt unsealed (they did not record it) and reseal a sealed one. */
export const saveReceipt = (path, receipt, { seal = receipt.contentSha256 !== undefined } = {}) =>
  writeFileSync(path, JSON.stringify(seal ? sealReceipt(receipt) : receipt, null, 2));

/** Gates that only read action times: refuse an edited receipt, and an unknown schema that claims to be one of ours. */
export function editedReceiptProblem(receipt) {
  if (!receipt || (receipt.schemaVersion === undefined && receipt.contentSha256 === undefined)) return null;
  const { state, message } = receiptIntegrity(receipt);
  return state === 'edited' || state === 'unknown-schema' ? message : null;
}

export const isViewerFacing = (job) => job?.intent !== 'draft' && (job?.kind === 'product-screencast' || job?.viewerFacing === true);

export const PROVENANCE_FIELDS = ['persona', 'scenarioId', 'sourceRevision', 'servedRevision', 'baseUrl', 'kitVersion'];
/** What the scenario proof says must have been recorded. A field the proof does not name is not compared. */
export const provenIdentity = (proof) => ({
  persona: proof?.personaId, scenarioId: proof?.scenarioId, sourceRevision: proof?.sourceRevision, servedRevision: proof?.servedRevision, baseUrl: proof?.baseUrl,
});
export function provenanceProblems(clipId, provenance, proof) {
  const problems = [];
  const expected = provenIdentity(proof);
  for (const field of PROVENANCE_FIELDS) {
    const value = provenance?.[field];
    if (typeof value !== 'string' || !value.trim()) problems.push(`clip ${clipId}: the take records no ${field}`);
    else if (expected[field] !== undefined && value !== expected[field]) problems.push(`clip ${clipId}: ${field} ${JSON.stringify(value)} is not the proven ${JSON.stringify(expected[field])}`);
  }
  return problems;
}

// ---- capture/manifest.json clips[].videoLead: [{ label, seconds, reason }]
// The encoded video can show a press slightly before the recorder logged it. The correction names the action, its size and why.
export const VIDEO_LEAD_MAX = 0.5;
export function videoLeadProblems(clipId, videoLead, actions = []) {
  if (videoLead === undefined) return [];
  if (!Array.isArray(videoLead)) return [`clip ${clipId}: videoLead must be a list of { label, seconds, reason }`];
  const problems = [];
  const seen = new Set();
  for (const lead of videoLead) {
    if (!(Number.isFinite(lead?.seconds) && lead.seconds > 0 && lead.seconds <= VIDEO_LEAD_MAX)) problems.push(`clip ${clipId}: videoLead seconds must be above 0 and at most ${VIDEO_LEAD_MAX}`);
    if (typeof lead?.reason !== 'string' || !lead.reason.trim()) problems.push(`clip ${clipId}: videoLead needs a reason`);
    if (!actions.some((a) => a.label && a.label === lead?.label)) problems.push(`clip ${clipId}: videoLead label ${JSON.stringify(lead?.label ?? null)} is not a recorded action`);
    if (seen.has(lead?.label)) problems.push(`clip ${clipId}: videoLead names ${JSON.stringify(lead.label)} twice`);
    seen.add(lead?.label);
  }
  return problems;
}
export function leadSeconds(videoLead, action) {
  if (!Array.isArray(videoLead) || !action?.label) return 0;
  return Number(videoLead.find((l) => l?.label === action.label)?.seconds) || 0;
}
