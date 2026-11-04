// execution-controls kit: executes the shared vectors in ../vectors/.
// The Python implementation has the same runner, so both languages are held to
// one set of expected answers.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createProposal,
  decide,
  type DecideResult,
  type DecisionRecord,
  type Proposal,
  type ProposalInput,
} from "./approval-capsule.ts";

export const VECTORS_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "vectors");

export function loadVectors<T = any>(name: string): T {
  return JSON.parse(readFileSync(join(VECTORS_DIR, name), "utf8"));
}

type Json = any;

/** Objects merge recursively, arrays and scalars replace, null deletes. */
export function merge(base: Json, patch: Json): Json {
  if (patch === undefined) return base;
  if (patch === null || typeof patch !== "object" || Array.isArray(patch)) return patch;
  const out: Record<string, Json> = base && typeof base === "object" && !Array.isArray(base) ? { ...base } : {};
  for (const [key, value] of Object.entries(patch)) {
    if (value === null) delete out[key];
    else out[key] = merge(out[key], value);
  }
  return out;
}

function substitute(value: Json, proposalHash: string): Json {
  if (value === "$proposalHash") return proposalHash;
  if (Array.isArray(value)) return value.map((item) => substitute(item, proposalHash));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, substitute(item, proposalHash)]));
  }
  return value;
}

export interface CaseRun {
  name: string;
  expect: Json;
  result: DecideResult;
  proposal: Proposal;
}

export function runApprovalCase(vectors: Json, testCase: Json): CaseRun {
  const base = vectors.base;
  const proposal = createProposal(merge(base.proposalInput, testCase.proposalInput) as ProposalInput);
  const stored = merge(proposal, testCase.storedProposalPatch) as Proposal;
  const policy = merge(base.policy, testCase.policy);
  const currentRevision = testCase.currentRevision ?? base.currentRevision;
  const now = testCase.now ?? base.now;
  const principalFor = (patch: Json) => merge(merge(base.principal, testCase.principal), patch);
  const requestFor = (patch: Json) =>
    substitute(merge(merge(base.request, testCase.request), patch), proposal.proposalHash);

  const priorDecisions: DecisionRecord[] = [];
  for (const prior of testCase.priorRequests ?? []) {
    const earlier = decide({
      proposal,
      request: substitute(merge(base.request, prior.request), proposal.proposalHash),
      principal: merge(base.principal, prior.principal),
      currentRevision: base.currentRevision,
      priorDecisions: [...priorDecisions],
      policy,
      now: base.now,
    });
    if (earlier.outcome === "apply" || earlier.outcome === "reject") priorDecisions.push(earlier.record);
    else throw new Error(`prior request in ${testCase.name} did not produce a record (${earlier.outcome})`);
  }

  const result = decide({
    proposal: stored,
    request: requestFor(undefined),
    principal: principalFor(undefined),
    currentRevision,
    priorDecisions,
    policy,
    now,
  });
  return { name: testCase.name, expect: testCase.expect, result, proposal };
}
