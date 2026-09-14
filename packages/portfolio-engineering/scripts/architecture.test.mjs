import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assessArchitecture } from './architecture.mjs';

const roster = { repos: ['one','two','three'].map(id => ({ id })) };
function fixture() { return { schemaVersion: 1, ownerCapability: 'portfolio-engineering', policyStatus: 'proposed', coverage: 'synthetic declarations', resources: [{
  id: 'mail', tier: 'T2', kind: 'application-service', status: 'verified', consumers: ['one','two'],
  owner: 'synthetic-owner', entity: 'synthetic-entity', dataBoundary: 'transit', isolationVerified: true,
  slo: 'synthetic target', apiVersion: 'v1', degradedMode: 'retain input', reversalPlan: 'change binding', evidence: ['one/README.md'],
}], sourceDependencies: [] }; }

test('existing two-consumer service is not rejected by new extraction threshold', () => {
  const result = assessArchitecture(fixture(), roster); assert.equal(result.status, 'passed'); assert.equal(result.runtimeVerified, false);
});
test('unknown and checked-failed isolation produce different dispositions', () => {
  const c = fixture(); c.resources[0].isolationVerified = null;
  assert.equal(assessArchitecture(c, roster).status, 'blocked');
  c.resources[0].isolationVerified = false; assert.equal(assessArchitecture(c, roster).status, 'failed');
});
test('new extraction and incomplete ownership cannot silently pass', () => {
  const c = fixture(); c.resources[0].status = 'proposed'; c.resources[0].owner = null;
  assert.equal(assessArchitecture(c, roster).findings.length, 2);
});
test('shared logical data, reverse dependencies and cycles fail', () => {
  const c = fixture(); c.resources[0].tier = 'T3'; c.sourceDependencies.push({from:'mail',to:'one'});
  const r = assessArchitecture(c, roster); assert.equal(r.status, 'failed');
  assert(r.findings.some(f => /cycle/.test(f.reason))); assert(r.findings.some(f => /logical/.test(f.reason)));
});
test('excluded and unknown consumers cannot enter the inventory', () => {
  const c = fixture(); c.resources[0].consumers.push('portfolio-records');
  assert.throws(() => assessArchitecture(c, roster), /consumers/);
});
test('T1 must be a stable pinned package; managed infrastructure needs no invented application API', () => {
  const c = fixture(); c.resources[0].tier = 'T1'; c.resources[0].kind = 'package'; c.resources[0].stableReleases = 1;
  assert.equal(assessArchitecture(c, roster).status, 'blocked');
  c.resources[0].tier = 'T2'; c.resources[0].kind = 'managed-infrastructure'; c.resources[0].apiVersion = null;
  assert.equal(assessArchitecture(c, roster).status, 'passed');
});

test('missing stability evidence and tier confusion cannot pass', () => {
  const c = fixture(); c.resources[0].tier = 'T1'; c.resources[0].kind = 'package';
  assert.equal(assessArchitecture(c, roster).status, 'blocked');
  c.resources[0].tier = 'T2'; assert.throws(() => assessArchitecture(c, roster), /disagree/);
});
test('missing or out-of-scope evidence is visible', () => {
  const c = fixture(); assert.equal(assessArchitecture(c, roster, () => false).status, 'blocked');
  c.resources[0].evidence = ['one/../portfolio-records/private.md'];
  assert.throws(() => assessArchitecture(c, roster), /outside/);
});

test('stable T1 requires an exact declared version for every consumer', () => {
  const c = fixture(); const r = c.resources[0]; r.tier = 'T1'; r.kind = 'package'; r.stableReleases = 2;
  assert.equal(assessArchitecture(c, roster).status, 'blocked');
  r.consumerVersions = {one:'1.0.0',two:'^1.0.0'};
  assert.equal(assessArchitecture(c, roster).status, 'blocked');
  r.consumerVersions.two = '1.0.0'; assert.equal(assessArchitecture(c, roster).status, 'passed');
  for (const invalid of ['2', 2.5, undefined]) {
    r.stableReleases = invalid; assert.equal(assessArchitecture(c, roster).status, 'blocked');
  }
});

test('resource identity cannot be omitted or coerced from another type', () => {
  for (const id of [undefined, null, 42, {}, ['mail']]) {
    const c = fixture(); c.resources[0].id = id;
    assert.throws(() => assessArchitecture(c, roster), /resource id/);
  }
});
