import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import {
  cancelTrainingImage, getTrainingImage, prepareTrainingImage, purgeExpiredTrainingImage,
  resumeTrainingImage, reviewTrainingImage, submitTrainingImage,
} from '../kit/cloud/runware-image.mjs';

const API = 'https://api.runware.ai/v1';
const IMAGE_ID = '11111111-1111-4111-8111-111111111111';
const IMAGE_ID_2 = '22222222-2222-4222-8222-222222222222';
const TEST_KEY = 'synthetic-runware-key-never-log';
const PRIVATE_URL = 'https://im.runware.ai/image/example.png?sig=private-test-token';
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const kind = Buffer.from(type, 'ascii');
  const length = Buffer.alloc(4);
  const checksum = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  checksum.writeUInt32BE(crc32(Buffer.concat([kind, data])));
  return Buffer.concat([length, kind, data, checksum]);
}

function png(width = 128, height = 128, value = 0) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const rowSize = width * 4 + 1;
  const pixels = Buffer.alloc(rowSize * height, value);
  for (let row = 0; row < height; row++) pixels[row * rowSize] = 0;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(pixels)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
}

async function fixture(t, changes = {}) {
  const workspace = mkdtempSync(join(tmpdir(), 'media-runware-test-'));
  t.after(() => rmSync(workspace, { recursive: true, force: true }));
  const sourceBytes = Buffer.from('Synthetic SOP: check the valve before the next step.');
  const sourceFile = join(workspace, 'synthetic-source.txt');
  writeFileSync(sourceFile, sourceBytes);
  const scope = { tenant: 'synthetic-tenant', project: 'training-demo' };
  const source = {
    id: 'sop-1', version: 'v1', sha256: sha256(sourceBytes),
    objective: 'valve-check', rights: 'synthetic', file: sourceFile,
  };
  const spec = {
    provider: 'runware', model: 'runware:z-image@0', region: 'provider-managed', scope, source,
    prompt: 'A synthetic training illustration of a valve check.',
    width: 128, height: 128, steps: 20, numberResults: 1, ttlSeconds: 300,
    revision: 'r1', retainUntil: '2031-01-01T00:00:00.000Z',
    estimate: { usd: 0.02, basis: 'synthetic test estimate, not a quote' },
    ...changes,
  };
  const job = await prepareTrainingImage({ workspace, spec, now: new Date('2026-01-01T00:00:00Z') });
  const currentSource = { version: source.version, sha256: source.sha256 };
  return { workspace, scope, source, spec, job, currentSource, options: { workspace, id: job.id, scope } };
}

function queued(taskUUID) {
  return { data: [{ taskType: 'imageInference', taskUUID, status: 'processing' }] };
}

function imageRow(taskUUID, imageUUID = IMAGE_ID, extra = {}) {
  return {
    taskType: 'imageInference', taskUUID, imageUUID, imageURL: PRIVATE_URL,
    NSFWContent: false, cost: 0.012, ...extra,
  };
}

function mockProvider(taskUUID, rows, { bytes = png(), imageStatus = 200, errors = [] } = {}) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (url === API) {
      const task = JSON.parse(init.body)[0];
      if (task.taskType === 'imageInference') return jsonResponse(queued(task.taskUUID));
      assert.equal(task.taskType, 'getResponse');
      assert.equal(task.taskUUID, taskUUID);
      return jsonResponse({ data: rows, errors });
    }
    return new Response(imageStatus === 200 ? bytes : null, { status: imageStatus, headers: { 'content-type': 'image/png' } });
  };
  return { calls, fetchImpl };
}

const checklist = { sequence: true, ppe: true, hazards: true, accessibility: true, contentSafe: true };

test('preparation verifies the synthetic source and deduplicates the exact request', async (t) => {
  const f = await fixture(t);
  const same = await prepareTrainingImage({ workspace: f.workspace, spec: f.spec, now: new Date('2026-01-01T00:00:00Z') });
  assert.equal(same.id, f.job.id);
  assert.equal(same.taskUUID, f.job.taskUUID);
  assert.equal(same.status, 'prepared');
  assert.equal(same.selected, true);
  assert.throws(() => getTrainingImage({ ...f.options, scope: { ...f.scope, tenant: 'other' } }), /scope/);
  writeFileSync(f.source.file, 'different source');
  await assert.rejects(prepareTrainingImage({ workspace: f.workspace, spec: f.spec, now: new Date('2026-01-01T00:00:00Z') }), /does not match/);
  await assert.rejects(prepareTrainingImage({ workspace: f.workspace, spec: { ...f.spec, model: 'auto' }, now: new Date('2026-01-01T00:00:00Z') }), /supports only/);
});

test('job content is protected from inherited workspace access', async (t) => {
  const f = await fixture(t);
  const jobDir = join(f.workspace, 'jobs', 'runware', f.job.id);
  if (process.platform !== 'win32') {
    assert.equal(statSync(jobDir).mode & 0o077, 0);
    return;
  }
  const command = "$ErrorActionPreference='Stop'; $a=[System.IO.Directory]::GetAccessControl($env:RUNWARE_TEST_JOB); $me=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; "
    + "$bad=@($a.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]) | Where-Object { $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin @($me,'S-1-5-18') }); "
    + 'if (-not $a.AreAccessRulesProtected -or $bad.Count -ne 0) { exit 1 }';
  const check = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], {
    env: { ...process.env, RUNWARE_TEST_JOB: jobDir }, windowsHide: true, timeout: 10000,
  });
  assert.equal(check.status, 0, 'job ACL must be protected and limited to the owner and SYSTEM');
  const inheritedDir = join(f.workspace, 'inherited-acl-probe');
  mkdirSync(inheritedDir);
  const negative = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], {
    env: { ...process.env, RUNWARE_TEST_JOB: inheritedDir }, windowsHide: true, timeout: 10000,
  });
  assert.equal(negative.status, 1, 'ACL check must reject a directory that still inherits permissions');
});

test('missing credentials and unapproved estimates fail before submission', async (t) => {
  const f = await fixture(t);
  let calls = 0;
  const fetchImpl = async () => { calls++; throw new Error('must not call'); };
  await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.01, key: TEST_KEY, fetchImpl }), /estimate ceiling/);
  await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: '', fetchImpl }), /RUNWARE_API_KEY/);
  assert.equal(calls, 0);
  assert.equal(getTrainingImage(f.options).status, 'prepared');
});

test('corrupt stored requests fail without exposing their contents', async (t) => {
  const f = await fixture(t);
  const marker = 'synthetic-private-prompt-marker';
  writeFileSync(join(f.workspace, 'jobs', 'runware', f.job.id, 'request.json'), `{"prompt":"${marker}",broken}`);
  const fetchImpl = async () => { throw new Error('must not call provider'); };
  await assert.rejects(
    submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl }),
    (error) => error.code === 'invalid-stored-json' && !error.message.includes(marker),
  );
  assert.equal(getTrainingImage(f.options).status, 'prepared');
});

test('ambiguous submission resumes the same task and never submits a second paid request', async (t) => {
  const f = await fixture(t);
  let submissions = 0;
  const lostResponse = async () => { submissions++; throw new Error(`timeout ${TEST_KEY} ${PRIVATE_URL}`); };
  await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: lostResponse }), /recover the existing task/);
  assert.equal(getTrainingImage(f.options).status, 'ambiguous-submit');
  await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: lostResponse }), /resume it/);
  assert.equal(submissions, 1);
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)]);
  const resumed = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  assert.equal(resumed.status, 'available-for-review');
  assert.equal(resumed.outputs[0].sha256, sha256(png()));
  assert.equal(resumed.cost.reportedOutputCostSumUsd, 0.012);
  const serialized = JSON.stringify(resumed);
  assert.ok(!serialized.includes(TEST_KEY));
  assert.ok(!serialized.includes('private-test-token'));
  assert.ok(!serialized.includes(f.spec.prompt));
  assert.equal(JSON.parse(provider.calls[0].init.body)[0].taskType, 'getResponse');
  assert.equal(provider.calls[0].init.headers.Authorization, `Bearer ${TEST_KEY}`);
  assert.equal(provider.calls[1].init.headers, undefined, 'provider credentials never accompany image downloads');
});

test('a UUID-only async acknowledgment starts polling without accepting malformed poll results', async (t) => {
  const f = await fixture(t);
  const ack = { data: [{ taskType: 'imageInference', taskUUID: f.job.taskUUID }] };
  const fetchImpl = async () => jsonResponse(ack);
  const submitted = await submitTrainingImage({
    ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl,
  });
  assert.equal(submitted.status, 'queued');
  await assert.rejects(resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl }), /valid task state/);
});

test('queued and downloading progress is visible while the same job continues', async (t) => {
  const f = await fixture(t);
  let releaseDownload;
  let signalDownload;
  const held = new Promise((resolve) => { releaseDownload = resolve; });
  const started = new Promise((resolve) => { signalDownload = resolve; });
  const fetchImpl = async (url, init) => {
    if (url === API) {
      const task = JSON.parse(init.body)[0];
      return task.taskType === 'imageInference'
        ? jsonResponse({ data: [{ taskType: 'imageInference', taskUUID: task.taskUUID, status: 'queued' }] })
        : jsonResponse({ data: [imageRow(task.taskUUID)] });
    }
    signalDownload();
    await held;
    return new Response(png(), { status: 200 });
  };
  const queuedJob = await submitTrainingImage({
    ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl,
  });
  assert.equal(queuedJob.status, 'queued');
  const pending = resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl });
  await Promise.race([started, pending.then(() => { throw new Error('job finished before downloading'); })]);
  try {
    assert.equal(getTrainingImage(f.options).status, 'downloading');
  } finally {
    releaseDownload();
  }
  assert.equal((await pending).status, 'available-for-review');
});

test('partial results retain cost and require a human review of the downloaded hash', async (t) => {
  const f = await fixture(t, { numberResults: 2 });
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)], {
    errors: [{ taskUUID: f.job.taskUUID, code: 'timeoutProvider', message: `${TEST_KEY} ${PRIVATE_URL}` }],
  });
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const partial = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  assert.equal(partial.status, 'partial');
  assert.equal(partial.cost.reportedOutputCostSumUsd, 0.012);
  assert.equal(partial.cost.allOutputCostsReported, false);
  assert.deepEqual(partial.errors, ['timeoutProvider']);
  const imageSha256 = partial.outputs[0].sha256;
  const review = { ...f.options, source: f.currentSource, imageSha256, reviewer: 'synthetic-reviewer', decision: 'accept', altText: 'A valve being checked', textEquivalent: 'Check the valve before the next step.', checklist };
  await assert.rejects(reviewTrainingImage({ ...review, source: { ...f.currentSource, version: 'v2' } }), /source revision changed/);
  await assert.rejects(reviewTrainingImage(review), /all requested outputs/);
  const completedProvider = mockProvider(f.job.taskUUID, [
    imageRow(f.job.taskUUID),
    imageRow(f.job.taskUUID, IMAGE_ID_2, { imageURL: 'https://im.runware.ai/image/second.png', cost: null }),
  ], { bytes: png(128, 128, 1) });
  const completed = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: completedProvider.fetchImpl });
  assert.equal(completed.outputs.length, 2);
  assert.equal(completed.cost.allOutputCostsReported, false);
  await assert.rejects(reviewTrainingImage({ ...review, checklist: { ...checklist, ppe: false } }), /must be reviewed/);
  const accepted = await reviewTrainingImage(review);
  assert.equal(accepted.status, 'accepted');
  assert.equal(accepted.outputs[0].review.sha256, imageSha256);
  const later = mockProvider(f.job.taskUUID, [
    imageRow(f.job.taskUUID),
    imageRow(f.job.taskUUID, IMAGE_ID_2, { imageURL: 'https://im.runware.ai/image/second.png', cost: 0.018 }),
  ], { bytes: png(128, 128, 1) });
  const reconciled = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: later.fetchImpl });
  assert.equal(reconciled.status, 'accepted');
  assert.equal(reconciled.outputs[1].status, 'available-for-review');
  assert.equal(reconciled.cost.reportedOutputCostSumUsd, 0.03);
  assert.equal(reconciled.cost.allOutputCostsReported, true);
});

test('a newer selection and changed source make old approvals unavailable', async (t) => {
  const f = await fixture(t);
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)]);
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const ready = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  await prepareTrainingImage({ workspace: f.workspace, spec: { ...f.spec, revision: 'r2' }, now: new Date('2026-01-01T00:00:00Z') });
  assert.equal(getTrainingImage(f.options).selected, false);
  assert.equal(getTrainingImage(f.options).effectiveStatus, 'stale');
  await assert.rejects(reviewTrainingImage({
    ...f.options, source: f.currentSource, imageSha256: ready.outputs[0].sha256, reviewer: 'reviewer', decision: 'accept',
    altText: 'Valve check', textEquivalent: 'Check the valve.', checklist,
  }), /newer job/);
});

test('a later model mismatch invalidates an accepted output', async (t) => {
  const f = await fixture(t);
  const initial = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID, IMAGE_ID, { cost: null })]);
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: initial.fetchImpl });
  const ready = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: initial.fetchImpl });
  await reviewTrainingImage({
    ...f.options, source: f.currentSource, imageSha256: ready.outputs[0].sha256, reviewer: 'reviewer', decision: 'accept',
    altText: 'Valve check', textEquivalent: 'Check the valve.', checklist,
  });
  const mismatch = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID, IMAGE_ID, { model: 'other:model@1' })]);
  const result = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: mismatch.fetchImpl });
  assert.equal(result.status, 'failed');
  assert.equal(result.outputs[0].status, 'failed');
});

test('unsafe, wrong-sized and expired outputs cannot become reviewed assets', async (t) => {
  for (const scenario of ['unsafe', 'wrong-size', 'expired']) {
    await t.test(scenario, async (subtest) => {
      const f = await fixture(subtest);
      const row = imageRow(f.job.taskUUID, IMAGE_ID, scenario === 'unsafe' ? { NSFWContent: true } : {});
      const provider = mockProvider(f.job.taskUUID, [row], {
        bytes: scenario === 'wrong-size' ? png(144, 128) : png(),
        imageStatus: scenario === 'expired' ? 404 : 200,
      });
      await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
      const result = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
      assert.equal(result.status, scenario === 'expired' ? 'expired' : 'failed');
      assert.equal(result.outputs[0].sha256, undefined);
      assert.equal(result.cost.reportedOutputCostSumUsd, 0.012, 'unsuitable successful outputs still carry their cost');
      if (scenario === 'unsafe') assert.equal(provider.calls.filter((call) => call.url !== API).length, 0);
      await assert.rejects(reviewTrainingImage({
        ...f.options, source: f.currentSource, imageSha256: '0'.repeat(64), reviewer: 'reviewer', decision: 'accept',
        altText: 'Valve check', textEquivalent: 'Check the valve.', checklist,
      }), /only a downloaded image/);
    });
  }
});

test('untrusted image hosts, modified files and provider error text fail closed without leaking data', async (t) => {
  const f = await fixture(t);
  const badHost = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID, IMAGE_ID, { imageURL: 'https://example.com/image.png' })], {
    errors: [{ taskUUID: f.job.taskUUID, code: TEST_KEY, message: PRIVATE_URL }],
  });
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: badHost.fetchImpl });
  const failed = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: badHost.fetchImpl });
  assert.equal(failed.status, 'failed');
  assert.deepEqual(failed.errors, ['provider-error']);
  assert.equal(badHost.calls.filter((call) => call.url !== API).length, 0);
  assert.ok(!JSON.stringify(failed).includes(TEST_KEY));
  assert.ok(!JSON.stringify(failed).includes(PRIVATE_URL));

  const recoveredProvider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)]);
  const recovered = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: recoveredProvider.fetchImpl });
  const hash = recovered.outputs[0].sha256;
  writeFileSync(join(f.workspace, ...recovered.outputs[0].storageObject.split('/')), 'modified');
  await assert.rejects(reviewTrainingImage({
    ...f.options, source: f.currentSource, imageSha256: hash, reviewer: 'reviewer', decision: 'accept',
    altText: 'Valve check', textEquivalent: 'Check the valve.', checklist,
  }), /hash no longer matches/);
});

test('a pre-existing hard link is not treated as a privately ingested asset', async (t) => {
  const f = await fixture(t);
  const bytes = png();
  const external = join(f.workspace, 'outside-asset.png');
  const assetDir = join(f.workspace, 'jobs', 'runware', f.job.id, 'assets');
  writeFileSync(external, bytes);
  mkdirSync(assetDir);
  linkSync(external, join(assetDir, `${sha256(bytes)}.png`));
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)], { bytes });
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const result = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  assert.equal(result.status, 'failed');
  assert.match(result.outputs[0].error, /expected owned file/);
  assert.equal(result.outputs[0].sha256, undefined);
  assert.equal(existsSync(external), true);
});

test('HTTP failures preserve one task, and local cancellation prevents late publication', async (t) => {
  for (const status of [401, 429]) {
    await t.test(`HTTP ${status}`, async (subtest) => {
      const f = await fixture(subtest);
      let calls = 0;
      const fetchImpl = async () => { calls++; return jsonResponse({ message: `${TEST_KEY} ${PRIVATE_URL}` }, status); };
      await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl }), new RegExp(`HTTP ${status}`));
      assert.equal(getTrainingImage(f.options).status, status === 401 ? 'denied' : 'ambiguous-submit');
      await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl }), /resume it/);
      assert.equal(calls, 1);
      await cancelTrainingImage(f.options);
      await assert.rejects(resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl }), /canceled locally/);
      assert.equal(calls, 1);
      assert.ok(!JSON.stringify(getTrainingImage(f.options)).includes(TEST_KEY));
    });
  }
});

test('concurrent callers cannot submit the same job twice', async (t) => {
  const f = await fixture(t);
  let release;
  const wait = new Promise((resolve) => { release = resolve; });
  let calls = 0;
  const fetchImpl = async (_url, init) => {
    calls++;
    const task = JSON.parse(init.body)[0];
    await wait;
    return jsonResponse(queued(task.taskUUID));
  };
  const options = { ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl };
  const first = submitTrainingImage(options);
  await assert.rejects(submitTrainingImage(options), /another process owns the job/);
  const newer = { ...f.spec, revision: 'r2' };
  await assert.rejects(prepareTrainingImage({ workspace: f.workspace, spec: newer, now: new Date('2026-01-01T00:00:00Z') }), /another process owns the job/);
  release();
  await first;
  assert.equal(calls, 1);
  await prepareTrainingImage({ workspace: f.workspace, spec: newer, now: new Date('2026-01-01T00:00:00Z') });
  assert.equal(getTrainingImage(f.options).effectiveStatus, 'stale');
});

test('expired retention blocks submission, polling and effective publication', async (t) => {
  const f = await fixture(t);
  let calls = 0;
  const fetchImpl = async (_url, init) => {
    calls++;
    return jsonResponse(queued(JSON.parse(init.body)[0].taskUUID));
  };
  const expired = new Date('2032-01-01T00:00:00Z');
  const submit = { ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl };
  await assert.rejects(submitTrainingImage({ ...submit, now: expired }), /retention period has expired/);
  assert.equal(getTrainingImage({ ...f.options, now: expired }).effectiveStatus, 'retention-expired');
  assert.equal(calls, 0);
  await submitTrainingImage(submit);
  await assert.rejects(resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl, now: expired }), /retention period has expired/);
  assert.equal(calls, 1);
});

test('explicit expiry cleanup removes only recorded owned content and cannot resume', async (t) => {
  const f = await fixture(t);
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)]);
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const ready = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const asset = join(f.workspace, ...ready.outputs[0].storageObject.split('/'));
  await assert.rejects(purgeExpiredTrainingImage({ ...f.options, confirmExpiredDeletion: true, now: new Date('2030-01-01T00:00:00Z') }), /has not expired/);
  await assert.rejects(purgeExpiredTrainingImage({ ...f.options, now: new Date('2032-01-01T00:00:00Z') }), /explicit confirmation/);
  await assert.rejects(purgeExpiredTrainingImage({ ...f.options, confirmExpiredDeletion: true, now: new Date('invalid') }), /valid current date/);
  const manifest = join(f.workspace, 'jobs', 'runware', f.job.id, 'job.json');
  const job = JSON.parse(readFileSync(manifest, 'utf8'));
  job.retention.retainUntil = 'invalid';
  writeFileSync(manifest, JSON.stringify(job));
  await assert.rejects(purgeExpiredTrainingImage({ ...f.options, confirmExpiredDeletion: true, now: new Date('2032-01-01T00:00:00Z') }), /retention date is invalid/);
  assert.equal(existsSync(asset), true);
  job.retention.retainUntil = f.spec.retainUntil;
  writeFileSync(manifest, JSON.stringify(job));
  const purged = await purgeExpiredTrainingImage({ ...f.options, confirmExpiredDeletion: true, now: new Date('2032-01-01T00:00:00Z') });
  assert.equal(purged.status, 'expired-and-purged');
  assert.equal(existsSync(asset), false);
  assert.equal(existsSync(f.source.file), true, 'the original input outside the job is not deleted');
  assert.equal(existsSync(join(f.workspace, 'jobs', 'runware', f.job.id, 'request.json')), false);
  await assert.rejects(resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl }), /retention policy/);
});

test('cloud-ai CLI accepts only the server environment key and never echoes private inputs', async (t) => {
  const f = await fixture(t);
  const inputFile = join(f.workspace, 'cli-input.json');
  const cli = fileURLToPath(new URL('../kit/cloud/cloud-ai.mjs', import.meta.url));
  const env = { ...process.env, MEDIA_STUDIO_ROOT: f.workspace, RUNWARE_API_KEY: '' };
  writeFileSync(inputFile, JSON.stringify(f.spec));
  const prepared = spawnSync(process.execPath, [cli, 'illustration', '--provider', 'runware', '--action', 'prepare', '--input', inputFile], {
    env, encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  assert.equal(prepared.status, 0, prepared.stderr);
  assert.equal(JSON.parse(prepared.stdout).id, f.job.id);
  assert.ok(!prepared.stdout.includes(f.spec.prompt));
  writeFileSync(inputFile, JSON.stringify({ ...f.options, source: f.currentSource, maxEstimatedUsd: 1, key: TEST_KEY }));
  const denied = spawnSync(process.execPath, [cli, 'illustration', '--provider', 'runware', '--action', 'submit', '--input', inputFile], {
    env, encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  assert.equal(denied.status, 2);
  assert.match(denied.stderr, /RUNWARE_API_KEY is not set/);
  assert.ok(!denied.stderr.includes(TEST_KEY));
  assert.equal(getTrainingImage(f.options).status, 'prepared');
  const provider = mockProvider(f.job.taskUUID, [imageRow(f.job.taskUUID)]);
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 0.02, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const ready = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  await reviewTrainingImage({
    ...f.options, source: f.currentSource, imageSha256: ready.outputs[0].sha256, reviewer: 'reviewer',
    decision: 'accept', altText: 'synthetic-private-alt', textEquivalent: 'synthetic-private-equivalent', checklist,
  });
  writeFileSync(inputFile, JSON.stringify(f.options));
  const status = spawnSync(process.execPath, [cli, 'illustration', '--provider', 'runware', '--action', 'status', '--input', inputFile], {
    env, encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  assert.equal(status.status, 0, status.stderr);
  assert.equal(JSON.parse(status.stdout).outputs[0].review.decision, 'accept');
  assert.ok(!status.stdout.includes('synthetic-private-alt'));
  assert.ok(!status.stdout.includes('synthetic-private-equivalent'));
  const inventory = spawnSync(process.execPath, [cli, 'illustration', '--provider', 'runware', '--action', 'inventory', '--input', inputFile], {
    env, encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  assert.equal(inventory.status, 0, inventory.stderr);
  assert.equal(JSON.parse(inventory.stdout).approved[0].sha256, ready.outputs[0].sha256);
  assert.ok(!inventory.stdout.includes('synthetic-private-alt'));
});

test('spend is bounded per job before any provider call', async (t) => {
  const f = await fixture(t);
  const fetchImpl = async () => { throw new Error('must not call provider'); };
  await assert.rejects(submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 1.01, key: TEST_KEY, fetchImpl }), /per-job bound/);
  await assert.rejects(prepareTrainingImage({
    workspace: f.workspace, spec: { ...f.spec, revision: 'r2', estimate: { usd: 2, basis: 'too high' } }, now: new Date('2026-01-01T00:00:00Z'),
  }), /per-job bound/);
  assert.equal(getTrainingImage(f.options).status, 'prepared');
});

test('the output inventory hashes every result and lists only approved, selected assets', async (t) => {
  const f = await fixture(t, { numberResults: 2 });
  const inventoryFile = join(f.workspace, 'jobs', 'runware', f.job.id, 'inventory.json');
  const prepared = JSON.parse(readFileSync(inventoryFile, 'utf8'));
  assert.equal(prepared.schema, 'media-studio/runware-output-inventory/1');
  assert.equal(prepared.complete, false);
  assert.deepEqual(prepared.approved, []);
  const provider = mockProvider(f.job.taskUUID, [
    imageRow(f.job.taskUUID, IMAGE_ID, { cost: 0.5 }),
    imageRow(f.job.taskUUID, IMAGE_ID_2, { imageURL: 'https://im.runware.ai/image/second.png', cost: 0.6 }),
  ], { bytes: png(128, 128, 1) });
  await submitTrainingImage({ ...f.options, source: f.currentSource, maxEstimatedUsd: 1, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  const ready = await resumeTrainingImage({ ...f.options, key: TEST_KEY, fetchImpl: provider.fetchImpl });
  assert.equal(ready.cost.reportedExceedsCeiling, true);
  await reviewTrainingImage({
    ...f.options, source: f.currentSource, imageSha256: ready.outputs[0].sha256, reviewer: 'sme', decision: 'accept',
    altText: 'Valve check', textEquivalent: 'Check the valve.', checklist,
  });
  const stored = JSON.parse(readFileSync(inventoryFile, 'utf8'));
  assert.equal(stored.complete, true);
  assert.equal(stored.outputs.length, 2);
  for (const output of stored.outputs) {
    const bytes = readFileSync(join(f.workspace, ...output.storageObject.split('/')));
    assert.equal(sha256(bytes), output.sha256);
    assert.equal(bytes.length, output.bytes);
  }
  assert.equal(stored.approved.length, 1);
  assert.equal(stored.approved[0].sha256, ready.outputs[0].sha256);
  assert.equal(stored.approved[0].altText, 'Valve check');
  assert.equal(stored.cost.reportedExceedsCeiling, true);
  await prepareTrainingImage({ workspace: f.workspace, spec: { ...f.spec, revision: 'r2' }, now: new Date('2026-01-01T00:00:00Z') });
  const superseded = JSON.parse(readFileSync(inventoryFile, 'utf8'));
  assert.equal(superseded.job.selected, false);
  assert.deepEqual(superseded.approved, []);
});
