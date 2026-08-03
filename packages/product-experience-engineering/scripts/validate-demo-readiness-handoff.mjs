#!/usr/bin/env node

import { readFileSync } from 'node:fs';

const usage = 'Usage: validate-demo-readiness-handoff.mjs <path-to-demo-readiness.json> [--current-revision <revision>] [--expected-handoff-path <path>]';
const options = {
  currentRevision: undefined,
  expectedHandoffPath: undefined,
};
let manifestPath;

for (let index = 2; index < process.argv.length; index++) {
  const argument = process.argv[index];
  if (argument === '--current-revision' || argument === '--expected-handoff-path') {
    const value = process.argv[++index];
    if (!value || value.startsWith('--')) {
      console.error(`${argument} requires a value.\n${usage}`);
      process.exit(2);
    }
    const option = argument === '--current-revision' ? 'currentRevision' : 'expectedHandoffPath';
    if (options[option] !== undefined) {
      console.error(`${argument} may be supplied only once.\n${usage}`);
      process.exit(2);
    }
    options[option] = value;
  } else if (argument.startsWith('-')) {
    console.error(`Unknown option: ${argument}\n${usage}`);
    process.exit(2);
  } else if (manifestPath) {
    console.error(`Unexpected positional argument: ${argument}\n${usage}`);
    process.exit(2);
  } else {
    manifestPath = argument;
  }
}

if (!manifestPath) {
  console.error(usage);
  process.exit(2);
}

const CRITERIA = [
  'single-clear-outcome',
  'fast-to-value',
  'clean-believable-states',
  'visual-stability',
  'legibility',
  'bounded-feedback-rich-waits',
  'discoverable-primary-action',
  'deterministic-resettable',
  'visible-guardrail',
  'hero-moment-exists',
  'polish-baseline',
];
const VIDEO_VERDICTS = new Set(['PASS', 'CONDITIONAL', 'FAIL']);
const EXPERIENCE_VERDICTS = new Set(['DEMO-READY', 'REMEDIABLE', 'DEFERRED']);
const DECISIONS = new Set(['PROCEED', 'PROCEED-WITH-CAPTURE-TREATMENT', 'DO-NOT-RECORD']);
const CLASSIFICATIONS = new Set(['capture-fixable', 'product-fix-required']);

const parsed = JSON.parse(readFileSync(manifestPath, 'utf8'));
const workflows = Array.isArray(parsed) ? parsed : (parsed.episodes ?? [parsed]);
let errors = 0;

function present(value) {
  return typeof value === 'string' ? value.trim().length > 0 : value !== undefined && value !== null;
}

for (const [index, workflow] of workflows.entries()) {
  const label = workflow.episodeId ?? `#${index}`;
  const fail = (message) => {
    console.error(`[error] ${label}: ${message}`);
    errors++;
  };

  for (const field of [
    'episodeId', 'workflow', 'assessedEnvironment', 'assessedRevision',
    'persona', 'heroMoment', 'handoffPath', 'assessmentOwner',
    'beforeVerdict', 'afterVerdict', 'verdict', 'handoffDecision',
  ]) {
    if (!present(workflow[field])) fail(`missing required field "${field}".`);
  }
  if (workflow.assessmentOwner !== 'product-experience-engineering') {
    fail('assessmentOwner must be "product-experience-engineering".');
  }
  if (options.currentRevision !== undefined && workflow.assessedRevision !== options.currentRevision) {
    fail(`assessedRevision must match current revision "${options.currentRevision}".`);
  }
  if (options.expectedHandoffPath !== undefined && workflow.handoffPath !== options.expectedHandoffPath) {
    fail(`handoffPath must match expected path "${options.expectedHandoffPath}".`);
  }
  if (!EXPERIENCE_VERDICTS.has(workflow.beforeVerdict)) fail('beforeVerdict is invalid.');
  if (!EXPERIENCE_VERDICTS.has(workflow.afterVerdict)) fail('afterVerdict is invalid.');
  if (!VIDEO_VERDICTS.has(workflow.verdict)) fail('verdict must be PASS, CONDITIONAL, or FAIL.');
  if (!DECISIONS.has(workflow.handoffDecision)) fail('handoffDecision is invalid.');
  if (!Array.isArray(workflow.permissions) || workflow.permissions.length === 0 || workflow.permissions.some((value) => !present(value))) {
    fail('permissions must contain at least one explicit permission or role.');
  }
  for (const field of ['fixture', 'seedCommand', 'resetCommand']) {
    if (!present(workflow.seedProfile?.[field])) fail(`seedProfile missing "${field}".`);
  }

  if (!Array.isArray(workflow.criteria)) {
    fail('criteria must contain all eleven demo-worthiness criteria.');
    continue;
  }
  const byId = new Map();
  for (const criterion of workflow.criteria) {
    if (!present(criterion?.id)) {
      fail('criterion missing id.');
      continue;
    }
    if (byId.has(criterion.id)) fail(`duplicate criterion "${criterion.id}".`);
    byId.set(criterion.id, criterion);
    if (typeof criterion.passed !== 'boolean') fail(`${criterion.id}: passed must be boolean.`);
    if (!Array.isArray(criterion.evidence) || criterion.evidence.length === 0 || criterion.evidence.some((value) => !present(value))) {
      fail(`${criterion.id}: include at least one evidence reference.`);
    }
    if (criterion.passed === false && !CLASSIFICATIONS.has(criterion.classification)) {
      fail(`${criterion.id}: failure needs capture-fixable or product-fix-required classification.`);
    }
    if (criterion.passed === true && criterion.classification) {
      fail(`${criterion.id}: passing criteria cannot carry a failure classification.`);
    }
  }
  for (const id of CRITERIA) if (!byId.has(id)) fail(`missing rubric criterion "${id}".`);
  for (const id of byId.keys()) if (!CRITERIA.includes(id)) fail(`unknown rubric criterion "${id}".`);

  const failed = [...byId.values()].filter((criterion) => criterion.passed === false);
  const captureFailures = failed.filter((criterion) => criterion.classification === 'capture-fixable');
  const productFailures = failed.filter((criterion) => criterion.classification === 'product-fix-required');
  const allCriteriaPassed = CRITERIA.every((id) => byId.get(id)?.passed === true);

  if (workflow.verdict === 'PASS' && failed.length > 0) fail('PASS cannot contain failed criteria.');
  if (workflow.verdict === 'CONDITIONAL' && (captureFailures.length === 0 || productFailures.length > 0)) {
    fail('CONDITIONAL requires capture-fixable failures and no product-fix-required failures.');
  }
  if (workflow.verdict === 'FAIL' && failed.length === 0) fail('FAIL requires at least one failed criterion.');
  if (workflow.handoffDecision === 'PROCEED' && workflow.verdict !== 'PASS') fail('PROCEED requires PASS.');
  if (workflow.handoffDecision === 'PROCEED-WITH-CAPTURE-TREATMENT' && workflow.verdict !== 'CONDITIONAL') {
    fail('PROCEED-WITH-CAPTURE-TREATMENT requires CONDITIONAL.');
  }
  if (workflow.handoffDecision === 'DO-NOT-RECORD' && workflow.verdict !== 'FAIL') fail('DO-NOT-RECORD requires FAIL.');
  if (workflow.afterVerdict === 'DEMO-READY') {
    if (!allCriteriaPassed) fail('DEMO-READY requires all eleven criteria to pass.');
    if (workflow.verdict !== 'PASS') fail('DEMO-READY must map to PASS.');
    if (workflow.handoffDecision !== 'PROCEED') fail('DEMO-READY must map to PROCEED.');
  }
  if (workflow.afterVerdict === 'REMEDIABLE') {
    if (failed.length === 0) fail('REMEDIABLE requires at least one failed criterion.');
    if (workflow.verdict !== 'FAIL') fail('REMEDIABLE must map to FAIL and cannot enter video production.');
    if (workflow.handoffDecision !== 'DO-NOT-RECORD') fail('REMEDIABLE must map to DO-NOT-RECORD.');
  }
  if (workflow.afterVerdict === 'DEFERRED') {
    if (workflow.verdict !== 'FAIL') fail('DEFERRED must map to FAIL.');
    if (workflow.handoffDecision !== 'DO-NOT-RECORD') fail('DEFERRED must map to DO-NOT-RECORD.');
  }

  if (captureFailures.length > 0 && (!Array.isArray(workflow.captureFixes) || workflow.captureFixes.length === 0)) {
    fail('capture-fixable failures require explicit captureFixes.');
  }
  if (productFailures.length > 0 && (!Array.isArray(workflow.productFixes) || workflow.productFixes.length === 0)) {
    fail('product-fix-required failures require productFixes.');
  }
  if (workflow.verdict === 'FAIL' && !present(workflow.shortestPathToReady)) {
    fail('FAIL requires shortestPathToReady.');
  }
}

console.log(`\n${workflows.length} pre-video handoff(s) checked: ${errors} error(s).`);
process.exit(errors > 0 ? 1 : 0);
