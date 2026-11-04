// Validates everything the kit produces against ../../schemas, so the schemas
// cannot drift from the implementation.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createReceipt, type Receipt } from "../receipt.ts";
import { VECTORS_DIR, loadVectors, runApprovalCase } from "../vectors.ts";
// Plain ESM helper, shared with scripts/validate-demo-harness.mjs.
import { validate } from "../../../schema-subset.mjs";

const SCHEMAS = join(VECTORS_DIR, "..", "schemas");
const schema = (name: string) => JSON.parse(readFileSync(join(SCHEMAS, `${name}.schema.json`), "utf8"));

const approval = loadVectors("approval-cases.json");

test("schemas: every proposal, record and audit row in the vectors validates", () => {
  const proposalSchema = schema("approval-proposal");
  const recordSchema = schema("decision-record");
  const auditSchema = schema("audit-row");
  for (const testCase of approval.cases) {
    const run = runApprovalCase(approval, testCase);
    assert.deepEqual(validate(proposalSchema, run.proposal), [], testCase.name);
    assert.deepEqual(validate(auditSchema, run.result.audit), [], testCase.name);
    if ("record" in run.result) assert.deepEqual(validate(recordSchema, run.result.record), [], testCase.name);
  }
});

test("schemas: every receipt in the vectors validates", () => {
  const receiptSchema = schema("receipt");
  const chain: Receipt[] = [];
  for (const input of loadVectors("receipts.json").chain) chain.push(createReceipt(input, chain.at(-1) ?? null));
  for (const receipt of chain) assert.deepEqual(validate(receiptSchema, receipt), [], receipt.receiptId);
});

test("schemas: the validator rejects what the schemas forbid", () => {
  const receiptSchema = schema("receipt");
  const [first] = [createReceipt(loadVectors("receipts.json").chain[0])];
  assert.ok(validate(receiptSchema, { ...first, prompt: "secret" }).some((e) => e.includes("unexpected prompt")));
  assert.ok(validate(receiptSchema, { ...first, receiptHash: "abc" }).length > 0);
  assert.ok(validate(receiptSchema, { ...first, retrieval: { ...first.retrieval, documents: [{ id: "x", hash: first.input.hash, score: 0.5 }] } }).length > 0);
});
