#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const typeIndex = args.indexOf('--type');
const type = typeIndex >= 0 ? args[typeIndex + 1] : null;
const file = args.find((value, index) => index !== typeIndex && index !== typeIndex + 1 && !value.startsWith('--'));

const contracts = {
  discovery: ['users and roles', 'outcomes', 'surface inventory', 'workflows', 'architecture', 'constraints', 'evidence', 'unknowns'],
  audit: ['executive summary', 'scope and evidence', 'surface coverage', 'findings', 'priorities', 'risks and unknowns', 'decision'],
  design: ['outcome', 'actors', 'target flow', 'states', 'information architecture', 'acceptance signals'],
  specification: ['scope', 'behavior', 'ui states', 'accessibility', 'tests', 'rollout'],
  validation: ['environment', 'scenarios', 'functional results', 'accessibility', 'defects', 'verdict'],
  measurement: ['questions', 'metrics', 'baselines', 'instrumentation', 'decision thresholds', 'review cadence'],
  'demo-handoff': ['metadata', 'workflow verdicts before and after', 'demo-readiness criteria', 'remediation evidence', 'seed and reset', 'persona and permissions', 'hero moments', 'remaining rough edges', 'limitations and confidence', 'video handoff decision'],
};

if (!type || !file || !(type in contracts)) {
  console.error('Usage: validate-product-experience-artifact.mjs --type <discovery|audit|design|specification|validation|measurement|demo-handoff> <file>');
  process.exit(2);
}

const resolved = path.resolve(file);
if (!fs.existsSync(resolved)) {
  console.error(`Artifact not found: ${resolved}`);
  process.exit(2);
}

const text = fs.readFileSync(resolved, 'utf8');
const headings = [...text.matchAll(/^#{1,6}\s+(.+)$/gm)].map((match) => match[1].trim().toLowerCase());
const missing = contracts[type].filter((required) => !headings.some((heading) => heading.includes(required)));
const unresolved = [...text.matchAll(/\b(TODO|TBD|FIXME)\b/g)].map((match) => match[0]);

if (missing.length || unresolved.length) {
  if (missing.length) console.error(`Missing required sections: ${missing.join(', ')}`);
  if (unresolved.length) console.error(`Unresolved placeholders: ${[...new Set(unresolved)].join(', ')}`);
  process.exit(1);
}

console.log(`PASS: ${type} artifact satisfies the required section contract.`);
