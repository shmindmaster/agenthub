import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { loadManifest } from './portfolio.mjs';

// Declaration validation only. No provider calls, source-content scanning, or writes.
export function assessArchitecture(catalog, roster, evidenceExists) {
  if (catalog.schemaVersion !== 1 || catalog.ownerCapability !== 'portfolio-engineering' ||
      !['proposed', 'approved'].includes(catalog.policyStatus) ||
      !Array.isArray(catalog.resources) || !Array.isArray(catalog.sourceDependencies)) {
    throw new Error('Invalid architecture declaration contract');
  }
  const products = new Set(roster.repos.map(r => r.id));
  const resourceIds = new Set();
  const findings = [];
  const add = (id, status, reason) => findings.push({ id, status, reason });
  for (const r of catalog.resources) {
    if (typeof r.id !== 'string' || !/^[a-z0-9-]+$/.test(r.id) || resourceIds.has(r.id) || products.has(r.id)) {
      throw new Error('Duplicate or invalid resource id');
    }
    resourceIds.add(r.id);
    if (!['T1', 'T2', 'T3'].includes(r.tier) ||
        !['managed-infrastructure', 'application-service', 'package', 'shared-data'].includes(r.kind) ||
        !['existing-unverified', 'proposed', 'verified'].includes(r.status) ||
        !Array.isArray(r.consumers) || !r.consumers.length ||
        new Set(r.consumers).size !== r.consumers.length || r.consumers.some(c => !products.has(c)) ||
        (r.repository && !products.has(r.repository))) throw new Error('Invalid resource classification or consumers');
    if (!['owner', 'entity', 'dataBoundary', 'isolationVerified', 'slo', 'apiVersion', 'degradedMode', 'reversalPlan'].every(k => Object.hasOwn(r, k)) ||
        !['owner', 'entity', 'dataBoundary', 'slo', 'apiVersion', 'degradedMode', 'reversalPlan'].every(k => r[k] === null || (typeof r[k] === 'string' && r[k].trim().length > 0)) ||
        ![null, true, false].includes(r.isolationVerified) || !Array.isArray(r.evidence) || !r.evidence.length) {
      throw new Error('Missing evidence or explicit unknowns');
    }
    if ((r.tier === 'T1' && r.kind !== 'package') ||
        (r.tier === 'T2' && !['managed-infrastructure', 'application-service'].includes(r.kind))) {
      throw new Error('Tier and kind disagree');
    }
    for (const path of r.evidence) {
      if (typeof path !== 'string' || path.includes('\\') || path.includes(':') ||
          path.split('/').some(p => !p || p === '.' || p === '..') || !products.has(path.split('/')[0])) {
        throw new Error('Evidence path is outside the product roster');
      }
      if (evidenceExists && !evidenceExists(path)) add(r.id, 'blocked', `Evidence file unavailable: ${path}`);
    }
    if (r.tier === 'T3' || r.kind === 'shared-data') add(r.id, 'failed', 'Shared logical product data is prohibited');
    if (!r.owner || !r.entity) add(r.id, 'blocked', 'Named operational owner and legal entity require confirmation');
    if (!r.reversalPlan) add(r.id, 'blocked', 'Reversal plan required');
    if (r.status === 'proposed' && r.consumers.length < 3) add(r.id, 'blocked', 'New extraction requires three real consumers');
    const exactVersion = /^(?:\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?|[a-f0-9]{40})$/;
    if (r.tier === 'T1' && (!r.apiVersion || !Number.isInteger(r.stableReleases) || r.stableReleases < 2 ||
        !r.consumerVersions || r.consumers.some(c => typeof r.consumerVersions[c] !== 'string' || !exactVersion.test(r.consumerVersions[c])))) {
      add(r.id, 'blocked', 'T1 requires a versioned package and two stable releases');
    }
    if (r.tier === 'T2') {
      if (!r.slo || !r.degradedMode || (r.kind === 'application-service' && !r.apiVersion)) {
        add(r.id, 'blocked', 'T2 service target, down mode or versioned application interface incomplete');
      }
      if (r.isolationVerified !== true) add(r.id, r.isolationVerified === false ? 'failed' : 'blocked',
        r.isolationVerified === false ? 'Isolation checked and failed' : 'Runtime isolation not established');
    }
  }
  const nodes = new Set([...products, ...resourceIds]);
  const adjacency = new Map([...nodes].map(n => [n, []]));
  const edges = [
    ...catalog.resources.flatMap(r => r.consumers.map(from => ({ from, to: r.id }))),
    // Only source/build dependencies belong here. Authorized API integrations
    // and callbacks are assessed in their ADR, not mislabeled as source imports.
    ...catalog.sourceDependencies,
  ];
  for (const { from, to } of edges) {
    if (!nodes.has(from) || !nodes.has(to)) throw new Error('Unknown dependency node');
    adjacency.get(from).push(to);
    if (products.has(to)) add(`${from}->${to}`, 'failed', 'Product internals cannot be a shared dependency');
  }
  const active = new Set(); const visited = new Set();
  function visit(node) {
    if (active.has(node)) { add(node, 'failed', 'Dependency cycle'); return; }
    if (visited.has(node)) return;
    active.add(node);
    for (const next of adjacency.get(node)) visit(next);
    active.delete(node); visited.add(node);
  }
  for (const node of nodes) visit(node);
  return { policyStatus: catalog.policyStatus, scope: catalog.coverage,
    resources: catalog.resources.length, runtimeVerified: false,
    status: findings.some(f => f.status === 'failed') ? 'failed' : findings.length ? 'blocked' : 'passed', findings };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const strict = process.argv.slice(2);
    if (strict.some(a => a !== '--strict') || strict.length > 1) throw new Error('Usage: architecture.mjs [--strict]');
    const catalog = JSON.parse(readFileSync(new URL('../architecture.json', import.meta.url), 'utf8'));
    const roster = loadManifest();
    const result = assessArchitecture(catalog, roster, path => existsSync(join(roster.fleetRoot, path)));
    console.log(JSON.stringify(result, null, 2));
    if (strict.length && result.status !== 'passed') process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
