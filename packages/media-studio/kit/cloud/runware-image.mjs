// One-model, synthetic training illustration jobs. Runtime data stays in the media workspace.
import { createHash, randomUUID } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
  chmodSync, closeSync, existsSync, lstatSync, mkdirSync, openSync, readFileSync, readdirSync, realpathSync,
  statSync, unlinkSync, writeFileSync,
} from 'node:fs';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { inflateSync } from 'node:zlib';
import { hashOf, readJson, writeJson } from '../marketing/lib/util.mjs';

const MODEL = 'runware:z-image@0';
const API = 'https://api.runware.ai/v1';
const MAX_IMAGE_BYTES = 25 * 1024 * 1024;
// Hard per-job spend bound; larger work needs a separate, reviewed change.
export const MAX_JOB_CEILING_USD = 1;
export const INVENTORY_SCHEMA = 'media-studio/runware-output-inventory/1';
const SHA = /^[a-f0-9]{64}$/;
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

export class RunwareImageError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'RunwareImageError';
    this.code = code;
  }
}

function fail(code, message) {
  throw new RunwareImageError(code, message);
}

function storedJson(path, label) {
  try {
    return readJson(path);
  } catch (error) {
    if (error instanceof SyntaxError) fail('invalid-stored-json', `${label} is invalid; inspect it privately`);
    throw error;
  }
}

function text(value, name, max = 256) {
  if (typeof value !== 'string' || !value.trim() || value.length > max) {
    fail('invalid-input', `${name} is required and must be at most ${max} characters`);
  }
  return value.trim();
}

function sha(value, name) {
  if (typeof value !== 'string' || !SHA.test(value)) fail('invalid-input', `${name} must be a lowercase SHA-256`);
  return value;
}

function dimension(value, name) {
  if (!Number.isInteger(value) || value < 128 || value > 2048 || value % 16 !== 0) {
    fail('invalid-input', `${name} must be 128–2048 pixels and divisible by 16`);
  }
  return value;
}

function dateMillis(value) {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
    fail('invalid-input', 'a valid current date is required');
  }
  return value.getTime();
}

function retentionExpiry(job) {
  const expiry = Date.parse(job.retention?.retainUntil);
  if (!Number.isFinite(expiry)) fail('retention-invalid', 'the recorded retention date is invalid; inspect the job');
  return expiry;
}

function requireActiveRetention(job, now = new Date()) {
  if (retentionExpiry(job) <= dateMillis(now)) {
    fail('retention-expired', 'the retention period has expired; remove owned content or create a new job');
  }
}

function scopeOf(value) {
  if (!value || typeof value !== 'object') fail('invalid-input', 'tenant and project scope are required');
  return { tenant: text(value.tenant, 'tenant'), project: text(value.project, 'project') };
}

function sourceOf(value) {
  if (!value || typeof value !== 'object') fail('invalid-input', 'source lineage is required');
  if (value.rights !== 'synthetic') fail('rights-not-verified', 'only synthetic source material is enabled');
  return {
    id: text(value.id, 'source id'),
    version: text(value.version, 'source version'),
    sha256: sha(value.sha256, 'source hash'),
    objective: text(value.objective, 'objective'),
    rights: value.rights,
  };
}

function prepareRequest(spec, now) {
  if (!spec || typeof spec !== 'object' || spec.provider !== 'runware') {
    fail('invalid-input', 'provider must explicitly be runware');
  }
  if (spec.model !== MODEL) fail('unsupported-model', `the training image adapter supports only ${MODEL}`);
  if (spec.region !== 'provider-managed') fail('unsupported-region', 'explicitly select the provider-managed region; no residency guarantee is established');
  const prompt = text(spec.prompt, 'prompt', 10000);
  if (prompt.length < 2) fail('invalid-input', 'prompt must contain at least two characters');
  const width = dimension(spec.width, 'width');
  const height = dimension(spec.height, 'height');
  if (!Number.isInteger(spec.steps) || spec.steps < 1 || spec.steps > 50) {
    fail('invalid-input', 'steps must be an integer from 1 to 50');
  }
  if (!Number.isInteger(spec.numberResults) || spec.numberResults < 1 || spec.numberResults > 4) {
    fail('invalid-input', 'numberResults must be an integer from 1 to 4');
  }
  if (!Number.isInteger(spec.ttlSeconds) || spec.ttlSeconds < 60) {
    fail('invalid-input', 'provider output TTL must be at least 60 seconds');
  }
  const expires = Date.parse(spec.retainUntil);
  if (!Number.isFinite(expires) || expires <= dateMillis(now)) {
    fail('invalid-input', 'retainUntil must be a future date');
  }
  if (!Number.isFinite(spec.estimate?.usd) || spec.estimate.usd < 0) {
    fail('invalid-input', 'a nonnegative USD estimate is required');
  }
  if (spec.estimate.usd > MAX_JOB_CEILING_USD) {
    fail('estimate-over-bound', `the estimate exceeds the $${MAX_JOB_CEILING_USD} per-job bound`);
  }
  const estimate = {
    usd: spec.estimate.usd,
    basis: text(spec.estimate.basis, 'estimate basis', 500),
  };
  const request = {
    provider: 'runware',
    scope: scopeOf(spec.scope),
    source: sourceOf(spec.source),
    model: MODEL,
    region: spec.region,
    prompt,
    width,
    height,
    steps: spec.steps,
    numberResults: spec.numberResults,
    ttlSeconds: spec.ttlSeconds,
    revision: text(spec.revision, 'request revision'),
  };
  return { request, estimate, retainUntil: new Date(expires).toISOString() };
}

function rootOf(workspace) {
  if (typeof workspace !== 'string' || !workspace.trim()) fail('invalid-input', 'media workspace is required');
  const root = resolve(workspace);
  mkdirSync(root, { recursive: true, mode: 0o700 });
  return realpathSync(root);
}

function workspaceFile(root, name, limit) {
  if (typeof name !== 'string' || !name.trim()) fail('invalid-input', 'a workspace file is required');
  let file;
  try {
    file = realpathSync(resolve(name));
  } catch {
    fail('invalid-input', 'workspace file was not found');
  }
  const rel = relative(root, file);
  if (!rel || rel === '..' || rel.startsWith(`..${sep}`) || isAbsolute(rel)) {
    fail('scope-denied', 'file must be inside the media workspace');
  }
  const stat = statSync(file);
  if (!stat.isFile() || stat.size === 0 || stat.size > limit) fail('invalid-input', 'workspace file is empty or too large');
  return file;
}

function directory(root, ...parts) {
  let current = root;
  for (const part of parts) {
    current = join(current, part);
    if (!existsSync(current)) mkdirSync(current, { mode: 0o700 });
    const stat = lstatSync(current);
    if (!stat.isDirectory() || stat.isSymbolicLink()) fail('unsafe-path', 'media workspace contains an unsafe path');
    const rel = relative(root, realpathSync(current));
    if (rel.startsWith('..') || resolve(root, rel) !== realpathSync(current)) {
      fail('unsafe-path', 'media job must remain inside the workspace');
    }
  }
  return current;
}

function secureNewJobDirectory(jobDir) {
  if (process.platform !== 'win32') {
    chmodSync(jobDir, 0o700);
    return;
  }
  const systemRoot = process.env.SystemRoot;
  if (!systemRoot || !isAbsolute(systemRoot)) fail('storage-not-private', 'could not resolve the Windows system directory');
  const systemDir = join(systemRoot, 'System32');
  const identity = spawnSync(join(systemDir, 'whoami.exe'), ['/user', '/fo', 'csv', '/nh'], {
    encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  const sid = identity.status === 0 && identity.stdout.match(/\bS-\d-\d+(?:-\d+)+\b/)?.[0];
  if (!sid) fail('storage-not-private', 'could not resolve the local workspace owner');
  const acl = spawnSync(join(systemDir, 'icacls.exe'), [
    jobDir, '/grant:r', `*${sid}:(OI)(CI)F`, '/grant:r', '*S-1-5-18:(OI)(CI)F', '/inheritance:r',
  ], { encoding: 'utf8', windowsHide: true, timeout: 10000 });
  if (acl.status !== 0) fail('storage-not-private', 'could not restrict the job directory to the local owner and SYSTEM');
}

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    if (error.code === 'ESRCH') return false;
    return true;
  }
}

function acquireLock(file) {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const fd = openSync(file, 'wx', 0o600);
      try {
        writeFileSync(fd, JSON.stringify({ pid: process.pid }));
      } finally {
        closeSync(fd);
      }
      return () => unlinkSync(file);
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let owner;
      try {
        owner = JSON.parse(readFileSync(file, 'utf8'));
      } catch {
        fail('job-locked', 'job lock is unreadable; inspect it before recovery');
      }
      if (!Number.isInteger(owner.pid) || owner.pid <= 0 || isProcessAlive(owner.pid)) {
        fail('job-locked', 'another process owns the job; retry after it finishes');
      }
      const recoveryFile = `${file}.recovery`;
      let recoveryFd;
      try {
        recoveryFd = openSync(recoveryFile, 'wx', 0o600);
      } catch (recoveryError) {
        if (recoveryError.code === 'EEXIST') fail('job-locked', 'another process is recovering the job lock');
        throw recoveryError;
      }
      try {
        if (existsSync(file)) {
          let current;
          try {
            current = JSON.parse(readFileSync(file, 'utf8'));
          } catch {
            fail('job-locked', 'job lock is unreadable; inspect it before recovery');
          }
          if (!Number.isInteger(current.pid) || current.pid <= 0 || isProcessAlive(current.pid)) {
            fail('job-locked', 'another process owns the job; retry after it finishes');
          }
          unlinkSync(file);
        }
      } finally {
        closeSync(recoveryFd);
        unlinkSync(recoveryFile);
      }
    }
  }
  fail('job-locked', 'could not safely acquire the job lock');
}

async function withLock(file, operation) {
  const release = acquireLock(file);
  try {
    return await operation();
  } finally {
    release();
  }
}

function selectionKey(request) {
  return hashOf({ scope: request.scope, sourceId: request.source.id, objective: request.source.objective });
}

function jobPaths(root, id) {
  sha(id, 'job id');
  const jobs = directory(root, 'jobs', 'runware');
  const jobDir = join(jobs, id);
  if (!existsSync(jobDir) || !lstatSync(jobDir).isDirectory() || lstatSync(jobDir).isSymbolicLink()) {
    fail('job-not-found', 'training image job was not found');
  }
  return { jobDir, jobFile: join(jobDir, 'job.json'), requestFile: join(jobDir, 'request.json') };
}

function loadJob(root, id, scope) {
  const paths = jobPaths(root, id);
  const job = storedJson(paths.jobFile, 'job manifest');
  const expected = scopeOf(scope);
  if (job.id !== id || job.scope?.tenant !== expected.tenant || job.scope?.project !== expected.project) {
    fail('scope-denied', 'job is not available in the requested tenant and project scope');
  }
  return { ...paths, job };
}

function selected(root, job) {
  const selections = directory(root, 'jobs', 'runware-selections');
  const path = join(selections, `${job.selectionKey}.json`);
  return existsSync(path) && storedJson(path, 'selection manifest').jobId === job.id;
}

function currentSource(job, current) {
  if (!current || current.version !== job.source.version || current.sha256 !== job.source.sha256) {
    fail('stale-source', 'the source revision changed; create a new job and review it');
  }
}

function checkSourceSnapshot(root, job) {
  sha(job.source?.sha256, 'source hash');
  const sourceDir = directory(root, 'jobs', 'runware', job.id, 'source');
  const file = join(sourceDir, `${job.source.sha256}.source`);
  if (!existsSync(file)) fail('source-missing', 'the synthetic source snapshot is missing');
  const stat = lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > 1024 * 1024) {
    fail('source-missing', 'the synthetic source snapshot is invalid');
  }
  const hash = createHash('sha256').update(readFileSync(file)).digest('hex');
  if (hash !== job.source.sha256) fail('source-changed', 'the synthetic source snapshot no longer matches its hash');
}

function publicJob(root, job, now = new Date()) {
  const isSelected = selected(root, job);
  const expired = retentionExpiry(job) <= dateMillis(now);
  const status = expired && !['purging', 'expired-and-purged'].includes(job.status) ? 'retention-expired' : job.status;
  return { ...job, selected: isSelected, effectiveStatus: isSelected ? status : 'stale' };
}

function inventoryOf(root, job, now = new Date()) {
  const view = publicJob(root, job, now);
  const pending = job.outputs.some((item) => item.status === 'downloading');
  const usable = view.selected && retentionExpiry(job) > dateMillis(now)
    && !['locally-canceled', 'purging', 'expired-and-purged', 'failed'].includes(job.status);
  const outputs = job.outputs.map((item, index) => ({
    index,
    imageUUID: item.imageUUID,
    status: item.status,
    sha256: item.sha256 ?? null,
    bytes: item.bytes ?? null,
    mediaType: item.sha256 ? 'image/png' : null,
    width: job.width,
    height: job.height,
    storageObject: item.storageObject ?? null,
    costUsd: item.costUsd,
    providerSafety: item.providerSafety ?? null,
    error: item.error ?? null,
    review: item.review ? {
      decision: item.review.decision, reviewer: item.review.reviewer, at: item.review.at, sha256: item.review.sha256,
      ...(item.review.checklist ? { checklist: item.review.checklist } : {}),
      ...(item.review.altText ? { altText: item.review.altText, textEquivalent: item.review.textEquivalent } : {}),
    } : null,
  }));
  return {
    schema: INVENTORY_SCHEMA,
    generatedAt: new Date().toISOString(),
    workspaceRelative: true,
    job: {
      id: job.id, taskUUID: job.taskUUID, status: job.status, effectiveStatus: view.effectiveStatus, selected: view.selected,
      scope: job.scope, provider: job.provider, requestedModel: job.requestedModel, actualModel: job.actualModel,
      region: job.region, promptSha256: job.promptSha256, configSha256: job.configSha256,
      numberResults: job.numberResults, retainUntil: job.retention.retainUntil,
      createdAt: job.createdAt, submittedAt: job.submittedAt ?? null,
    },
    source: job.source,
    cost: {
      estimatedUsd: job.cost.estimate.usd,
      authorizedEstimateCeilingUsd: job.cost.authorizedEstimateCeilingUsd ?? null,
      reportedOutputCostSumUsd: job.cost.reportedOutputCostSumUsd,
      allOutputCostsReported: job.cost.allOutputCostsReported,
      reportedExceedsCeiling: job.cost.reportedExceedsCeiling === true,
    },
    complete: job.outputs.length === job.numberResults && !pending,
    outputs,
    approved: usable ? outputs.filter((item) => item.status === 'accepted').map((item) => ({
      sha256: item.sha256, storageObject: item.storageObject, bytes: item.bytes, mediaType: item.mediaType,
      width: item.width, height: item.height, altText: item.review.altText, textEquivalent: item.review.textEquivalent,
      reviewer: item.review.reviewer, reviewedAt: item.review.at,
    })) : [],
  };
}

function saveJob(root, jobDir, job) {
  writeJson(join(jobDir, 'job.json'), job);
  writeJson(join(jobDir, 'inventory.json'), inventoryOf(root, job));
}

export async function prepareTrainingImage({ workspace, spec, now = new Date() }) {
  const root = rootOf(workspace);
  const { request, estimate, retainUntil } = prepareRequest(spec, now);
  const sourceFile = workspaceFile(root, spec.source.file, 1024 * 1024);
  const sourceBytes = readFileSync(sourceFile);
  if (createHash('sha256').update(sourceBytes).digest('hex') !== request.source.sha256) {
    fail('source-changed', 'the provided source file does not match its recorded hash');
  }
  const id = hashOf(request);
  const jobs = directory(root, 'jobs', 'runware');
  const selections = directory(root, 'jobs', 'runware-selections');
  return withLock(join(jobs, '.prepare.lock'), async () => {
    const jobDir = join(jobs, id);
    if (existsSync(jobDir)) {
      const existing = loadJob(root, id, request.scope).job;
      return publicJob(root, existing);
    }
    mkdirSync(jobDir, { mode: 0o700 });
    secureNewJobDirectory(jobDir);
    if (readdirSync(jobDir).length !== 0) fail('storage-not-private', 'new job directory was not empty');
    const job = {
      schema: 'media-studio/runware-training-image/1',
      id,
      selectionKey: selectionKey(request),
      taskUUID: randomUUID(),
      status: 'prepared',
      scope: request.scope,
      source: request.source,
      sourceObject: `jobs/runware/${id}/source/${request.source.sha256}.source`,
      provider: 'runware',
      requestedModel: MODEL,
      actualModel: null,
      region: request.region,
      promptSha256: createHash('sha256').update(request.prompt, 'utf8').digest('hex'),
      configSha256: hashOf({
        model: request.model, region: request.region, width: request.width, height: request.height, steps: request.steps,
        numberResults: request.numberResults, ttlSeconds: request.ttlSeconds,
      }),
      width: request.width,
      height: request.height,
      numberResults: request.numberResults,
      retention: { retainUntil, policy: 'operator-managed' },
      cost: { estimate, reportedOutputCostSumUsd: null, allOutputCostsReported: false },
      outputs: [],
      errors: [],
      createdAt: now.toISOString(),
    };
    const sourceDir = directory(root, 'jobs', 'runware', id, 'source');
    writeFileSync(join(sourceDir, `${request.source.sha256}.source`), sourceBytes, { flag: 'wx', mode: 0o600 });
    writeJson(join(jobDir, 'request.json'), request);
    const selectionFile = join(selections, `${job.selectionKey}.json`);
    const previous = existsSync(selectionFile) ? storedJson(selectionFile, 'selection manifest').jobId : null;
    writeJson(join(jobDir, 'job.json'), job);
    writeJson(selectionFile, { jobId: id });
    saveJob(root, jobDir, job);
    if (previous && previous !== id && SHA.test(previous)) {
      // Superseded jobs must stop advertising approved assets in their inventory.
      try {
        const old = jobPaths(root, previous);
        await withLock(join(old.jobDir, '.job.lock'), async () => saveJob(root, old.jobDir, storedJson(old.jobFile, 'job manifest')));
      } catch (error) {
        if (!(error instanceof RunwareImageError)) throw error;
      }
    }
    return publicJob(root, job);
  });
}

function apiKey(key) {
  const value = key ?? process.env.RUNWARE_API_KEY;
  if (typeof value !== 'string' || !value.trim()) fail('credential-missing', 'RUNWARE_API_KEY is not set');
  return value;
}

async function requestApi(task, key, fetchImpl) {
  let response;
  try {
    response = await fetchImpl(API, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify([task]),
      signal: AbortSignal.timeout(30000),
      redirect: 'error',
    });
  } catch {
    fail('provider-unreachable', 'Runware request failed or timed out; recover the existing task');
  }
  if (!response.ok) fail(`http-${response.status}`, `Runware returned HTTP ${response.status}; recover the existing task`);
  try {
    return await response.json();
  } catch {
    fail('invalid-response', 'Runware returned an unreadable response; recover the existing task');
  }
}

function safeErrorCode(code) {
  return ['invalidApiKey', 'timeoutProvider', 'invalidParameter', 'insufficientFunds', 'rateLimitExceeded'].includes(code)
    ? code : 'provider-error';
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function validatePng(bytes, width, height) {
  if (bytes.length < 45 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    fail('invalid-image', 'provider output is not a PNG image');
  }
  let pos = 8;
  let header;
  const data = [];
  let ended = false;
  while (pos + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(pos);
    const end = pos + 12 + length;
    if (end > bytes.length) fail('invalid-image', 'provider PNG is truncated');
    const type = bytes.toString('ascii', pos + 4, pos + 8);
    const chunk = bytes.subarray(pos + 8, pos + 8 + length);
    if (crc32(bytes.subarray(pos + 4, pos + 8 + length)) !== bytes.readUInt32BE(pos + 8 + length)) {
      fail('invalid-image', 'provider PNG failed its integrity check');
    }
    if (type === 'IHDR') {
      if (header || length !== 13 || pos !== 8) fail('invalid-image', 'provider PNG has an invalid header');
      header = chunk;
    } else if (type === 'IDAT') {
      data.push(chunk);
    } else if (type === 'IEND') {
      if (length !== 0 || end !== bytes.length) fail('invalid-image', 'provider PNG has an invalid ending');
      ended = true;
      break;
    }
    pos = end;
  }
  if (!header || !data.length || !ended || header.readUInt32BE(0) !== width || header.readUInt32BE(4) !== height) {
    fail('invalid-dimensions', 'provider image dimensions or PNG structure do not match the request');
  }
  const depth = header[8];
  const color = header[9];
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[color];
  const validDepths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
  if (!channels || !validDepths[color].includes(depth) || header[10] !== 0 || header[11] !== 0 || header[12] !== 0) {
    fail('invalid-image', 'provider PNG uses an unsupported image encoding');
  }
  const rowSize = Math.ceil(width * channels * depth / 8) + 1;
  const expected = rowSize * height;
  let decoded;
  try {
    decoded = inflateSync(Buffer.concat(data), { maxOutputLength: expected + 1 });
  } catch {
    fail('invalid-image', 'provider PNG could not be decoded');
  }
  if (decoded.length !== expected) fail('invalid-image', 'provider PNG pixel data is incomplete');
  for (let row = 0; row < height; row++) {
    if (decoded[row * rowSize] > 4) fail('invalid-image', 'provider PNG has an invalid filter');
  }
}

async function downloadImage(rawUrl, fetchImpl) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    fail('invalid-output-url', 'provider output URL is invalid');
  }
  if (url.protocol !== 'https:' || url.hostname !== 'im.runware.ai' || url.username || url.password || (url.port && url.port !== '443')) {
    fail('invalid-output-url', 'provider output URL is outside the permitted image host');
  }
  let response;
  try {
    response = await fetchImpl(url.href, { redirect: 'error', signal: AbortSignal.timeout(30000) });
  } catch {
    fail('download-failed', 'image download failed; resume the existing task');
  }
  if ([403, 404, 410].includes(response.status)) fail('expired-output', 'provider output is unavailable or expired');
  if (!response.ok) fail('download-failed', `image download returned HTTP ${response.status}; resume the existing task`);
  const length = Number(response.headers.get('content-length'));
  if (Number.isFinite(length) && length > MAX_IMAGE_BYTES) fail('invalid-image', 'provider image exceeds the size limit');
  if (!response.body) fail('invalid-image', 'provider image response has no body');
  const chunks = [];
  let total = 0;
  try {
    for await (const chunk of response.body) {
      total += chunk.length;
      if (total > MAX_IMAGE_BYTES) fail('invalid-image', 'provider image exceeds the size limit');
      chunks.push(Buffer.from(chunk));
    }
  } catch (error) {
    if (error instanceof RunwareImageError) throw error;
    fail('download-failed', 'image download was interrupted; resume the existing task');
  }
  return Buffer.concat(chunks);
}

async function ingestResult(root, job, row, fetchImpl) {
  if (!UUID.test(row.imageUUID || '')) fail('invalid-response', 'provider image identifier is invalid');
  let output = job.outputs.find((item) => item.imageUUID === row.imageUUID);
  if (!output) {
    if (job.outputs.length >= job.numberResults) fail('invalid-response', 'provider returned more images than requested');
    output = { imageUUID: row.imageUUID, status: 'downloading', costUsd: null };
    job.outputs.push(output);
  }
  if (Number.isFinite(row.cost) && row.cost >= 0) output.costUsd = row.cost;
  if (row.NSFWContent === true) {
    output.status = 'unsafe';
    output.error = 'provider flagged unsafe content';
    return;
  }
  if (row.model && row.model !== job.requestedModel) {
    output.status = 'failed';
    output.error = 'provider returned a different model';
    return;
  }
  if (row.model) job.actualModel = row.model;
  if (output.status === 'available-for-review' || output.status === 'accepted' || output.status === 'rejected') return;
  output.providerSafety = row.NSFWContent === false ? 'not-flagged' : 'unknown';
  try {
    const bytes = await downloadImage(row.imageURL, fetchImpl);
    validatePng(bytes, job.width, job.height);
    requireActiveRetention(job);
    const hash = createHash('sha256').update(bytes).digest('hex');
    const assetDir = directory(root, 'jobs', 'runware', job.id, 'assets');
    const file = join(assetDir, `${hash}.png`);
    try {
      writeFileSync(file, bytes, { flag: 'wx', mode: 0o600 });
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const existing = lstatSync(file);
      if (!existing.isFile() || existing.isSymbolicLink() || existing.nlink !== 1 || existing.size > MAX_IMAGE_BYTES
        || createHash('sha256').update(readFileSync(file)).digest('hex') !== hash) {
        fail('unsafe-path', 'existing asset is not the expected owned file');
      }
    }
    output.status = 'available-for-review';
    output.sha256 = hash;
    output.bytes = bytes.length;
    output.storageObject = `jobs/runware/${job.id}/assets/${hash}.png`;
    delete output.error;
  } catch (error) {
    if (!(error instanceof RunwareImageError)) throw error;
    output.status = error.code === 'expired-output' ? 'expired' : error.code === 'download-failed' ? 'download-failed' : 'failed';
    output.error = error.message;
  }
}

async function applyResponse(root, paths, job, response, fetchImpl, allowAcknowledgement = false) {
  requireActiveRetention(job);
  if (!response || typeof response !== 'object' || (!Array.isArray(response.data) && !Array.isArray(response.errors))) {
    fail('invalid-response', 'provider response does not contain task data or errors');
  }
  const rows = response.data || [];
  const errors = response.errors || [];
  for (const row of rows) {
    if (row.taskUUID !== job.taskUUID || row.taskType !== 'imageInference') {
      fail('invalid-response', 'provider response does not match the requested image task');
    }
    if (row.imageUUID) {
      const previous = job.outputs.find((item) => item.imageUUID === row.imageUUID);
      if (row.NSFWContent !== true && (!row.model || row.model === job.requestedModel)
        && !['available-for-review', 'accepted', 'rejected'].includes(previous?.status)) {
        job.status = 'downloading';
        saveJob(root, paths.jobDir, job);
      }
      await ingestResult(root, job, row, fetchImpl);
    }
    else if (!['processing', 'queued'].includes(row.status) && !(allowAcknowledgement && row.status === undefined)) {
      fail('invalid-response', 'provider response does not contain a valid task state');
    }
  }
  for (const error of errors) {
    if (error.taskUUID && error.taskUUID !== job.taskUUID) fail('invalid-response', 'provider error belongs to another task');
    const code = safeErrorCode(error.code);
    if (!job.errors.includes(code)) job.errors.push(code);
  }
  const costs = job.outputs.map((item) => item.costUsd).filter((value) => Number.isFinite(value));
  job.cost.reportedOutputCostSumUsd = costs.length ? costs.reduce((sum, value) => sum + value, 0) : null;
  job.cost.allOutputCostsReported = job.outputs.length === job.numberResults && job.outputs.every((item) => Number.isFinite(item.costUsd));
  job.cost.reportedExceedsCeiling = Number.isFinite(job.cost.authorizedEstimateCeilingUsd)
    && Number.isFinite(job.cost.reportedOutputCostSumUsd)
    && job.cost.reportedOutputCostSumUsd > job.cost.authorizedEstimateCeilingUsd;
  const available = job.outputs.filter((item) => item.status === 'available-for-review').length;
  const problem = job.errors.length > 0 || job.outputs.some((item) => ['unsafe', 'expired', 'failed', 'download-failed'].includes(item.status));
  if (available && (problem || job.outputs.length < job.numberResults)) job.status = 'partial';
  else if (available === job.numberResults) job.status = 'available-for-review';
  else if (job.outputs.some((item) => item.status === 'expired')) job.status = 'expired';
  else if (problem) job.status = 'failed';
  else if (rows.length && rows.every((row) => row.status === 'queued'
    || (allowAcknowledgement && !row.imageUUID && row.status === undefined))) job.status = 'queued';
  else job.status = 'generating';
  saveJob(root, paths.jobDir, job);
  return publicJob(root, job);
}

export async function submitTrainingImage({ workspace, id, scope, source, maxEstimatedUsd, key, fetchImpl = fetch, now = new Date() }) {
  const root = rootOf(workspace);
  const paths = loadJob(root, id, scope);
  const jobs = directory(root, 'jobs', 'runware');
  return withLock(join(jobs, '.prepare.lock'), () => withLock(join(paths.jobDir, '.job.lock'), async () => {
    const { job } = loadJob(root, id, scope);
    if (job.status !== 'prepared') fail('already-submitted', 'this request already has a task; resume it instead of submitting again');
    requireActiveRetention(job, now);
    if (!selected(root, job)) fail('stale-selection', 'a newer job is selected for this objective');
    currentSource(job, source);
    checkSourceSnapshot(root, job);
    if (!Number.isFinite(maxEstimatedUsd) || maxEstimatedUsd < job.cost.estimate.usd) {
      fail('estimate-not-authorized', 'an explicit estimate ceiling covering this request is required');
    }
    if (maxEstimatedUsd > MAX_JOB_CEILING_USD) {
      fail('estimate-over-bound', `the estimate ceiling exceeds the $${MAX_JOB_CEILING_USD} per-job bound`);
    }
    const secret = apiKey(key);
    const request = storedJson(paths.requestFile, 'prepared request');
    if (hashOf(request) !== id) fail('request-changed', 'the prepared request changed; do not submit it');
    job.status = 'submitting';
    job.cost.authorizedEstimateCeilingUsd = maxEstimatedUsd;
    job.submittedAt = new Date().toISOString();
    saveJob(root, paths.jobDir, job);
    try {
      const response = await requestApi({
        taskType: 'imageInference',
        taskUUID: job.taskUUID,
        model: request.model,
        positivePrompt: request.prompt,
        width: request.width,
        height: request.height,
        steps: request.steps,
        numberResults: request.numberResults,
        ttl: request.ttlSeconds,
        outputType: 'URL',
        outputFormat: 'PNG',
        deliveryMethod: 'async',
        includeCost: true,
        safety: { checkContent: true },
      }, secret, fetchImpl);
      return await applyResponse(root, paths, job, response, fetchImpl, true);
    } catch (error) {
      job.status = ['http-401', 'http-403'].includes(error.code) ? 'denied' : 'ambiguous-submit';
      job.lastError = error instanceof RunwareImageError ? error.code : 'local-error';
      saveJob(root, paths.jobDir, job);
      throw error;
    }
  }));
}

export async function resumeTrainingImage({ workspace, id, scope, key, fetchImpl = fetch, now = new Date() }) {
  const root = rootOf(workspace);
  const paths = loadJob(root, id, scope);
  return withLock(join(paths.jobDir, '.job.lock'), async () => {
    const { job } = loadJob(root, id, scope);
    if (job.status === 'prepared') fail('not-submitted', 'the job has not been submitted');
    if (job.status === 'locally-canceled') fail('locally-canceled', 'this job was canceled locally and cannot publish');
    if (['purging', 'expired-and-purged'].includes(job.status)) fail('retention-expired', 'this job is being removed under its retention policy');
    requireActiveRetention(job, now);
    if ((job.status === 'accepted' || job.status === 'rejected') && job.cost.allOutputCostsReported) return publicJob(root, job);
    const reviewedStatus = ['accepted', 'rejected'].includes(job.status) ? job.status : null;
    const secret = apiKey(key);
    try {
      const response = await requestApi({ taskType: 'getResponse', taskUUID: job.taskUUID }, secret, fetchImpl);
      delete job.lastError;
      await applyResponse(root, paths, job, response, fetchImpl);
      if (reviewedStatus) {
        job.status = reviewedStatus === 'accepted' && !job.outputs.some((output) => output.status === 'accepted')
          ? 'failed' : reviewedStatus;
        saveJob(root, paths.jobDir, job);
      }
      return publicJob(root, job);
    } catch (error) {
      job.lastError = error instanceof RunwareImageError ? error.code : 'local-error';
      saveJob(root, paths.jobDir, job);
      throw error;
    }
  });
}

export async function cancelTrainingImage({ workspace, id, scope }) {
  const root = rootOf(workspace);
  const paths = loadJob(root, id, scope);
  return withLock(join(paths.jobDir, '.job.lock'), async () => {
    const { job } = loadJob(root, id, scope);
    if (job.status === 'accepted' || job.status === 'rejected') fail('already-reviewed', 'reviewed assets cannot be canceled');
    job.status = 'locally-canceled';
    job.canceledAt = new Date().toISOString();
    saveJob(root, paths.jobDir, job);
    return publicJob(root, job);
  });
}

export async function reviewTrainingImage({ workspace, id, scope, source, imageSha256, reviewer, decision, altText, textEquivalent, checklist, reason, now = new Date() }) {
  const root = rootOf(workspace);
  const paths = loadJob(root, id, scope);
  const jobs = directory(root, 'jobs', 'runware');
  return withLock(join(jobs, '.prepare.lock'), () => withLock(join(paths.jobDir, '.job.lock'), async () => {
    const { job } = loadJob(root, id, scope);
    if (job.status === 'locally-canceled') fail('locally-canceled', 'a locally canceled job cannot be reviewed');
    if (job.status === 'accepted') fail('already-reviewed', 'this job already has an accepted asset');
    if (!selected(root, job)) fail('stale-selection', 'a newer job is selected for this objective');
    currentSource(job, source);
    checkSourceSnapshot(root, job);
    requireActiveRetention(job, now);
    sha(imageSha256, 'image hash');
    const output = job.outputs.find((item) => item.sha256 === imageSha256 && item.status === 'available-for-review');
    if (!output) fail('asset-not-reviewable', 'only a downloaded image awaiting review can be reviewed');
    const assetDir = directory(root, 'jobs', 'runware', job.id, 'assets');
    const asset = join(assetDir, `${imageSha256}.png`);
    if (!existsSync(asset)) fail('asset-missing', 'the owned image is missing');
    const assetStat = lstatSync(asset);
    if (!assetStat.isFile() || assetStat.isSymbolicLink() || assetStat.nlink !== 1 || assetStat.size > MAX_IMAGE_BYTES) {
      fail('asset-missing', 'the owned image is missing or invalid');
    }
    const bytes = readFileSync(asset);
    if (createHash('sha256').update(bytes).digest('hex') !== imageSha256) fail('asset-changed', 'the owned image hash no longer matches');
    validatePng(bytes, job.width, job.height);
    const actor = text(reviewer, 'reviewer');
    if (!['accept', 'reject'].includes(decision)) fail('invalid-input', 'decision must be accept or reject');
    if (decision === 'accept') {
      if (!['available-for-review', 'partial', 'rejected'].includes(job.status) || job.lastError
        || job.outputs.length !== job.numberResults
        || job.outputs.some((item) => !['available-for-review', 'rejected'].includes(item.status))) {
        fail('job-incomplete', 'all requested outputs must be safely retrieved or reviewed before accepting an asset');
      }
      const checks = ['sequence', 'ppe', 'hazards', 'accessibility', 'contentSafe'];
      if (!checklist || checks.some((name) => checklist[name] !== true)) {
        fail('review-incomplete', 'sequence, PPE, hazards, accessibility and content safety must be reviewed');
      }
      output.review = {
        decision, reviewer: actor, at: now.toISOString(), source: job.source, sha256: imageSha256,
        altText: text(altText, 'alt text', 1000), textEquivalent: text(textEquivalent, 'text equivalent', 5000),
        checklist: Object.fromEntries(checks.map((name) => [name, true])),
      };
      output.status = 'accepted';
      job.status = 'accepted';
    } else {
      output.review = { decision, reviewer: actor, at: now.toISOString(), source: job.source, sha256: imageSha256, reason: text(reason, 'rejection reason', 1000) };
      output.status = 'rejected';
      if (!job.outputs.some((item) => item.status === 'available-for-review')) job.status = 'rejected';
    }
    saveJob(root, paths.jobDir, job);
    return publicJob(root, job);
  }));
}

export function getTrainingImage({ workspace, id, scope, now = new Date() }) {
  const root = rootOf(workspace);
  return publicJob(root, loadJob(root, id, scope).job, now);
}

export function getTrainingInventory({ workspace, id, scope, now = new Date() }) {
  const root = rootOf(workspace);
  return inventoryOf(root, loadJob(root, id, scope).job, now);
}

export async function purgeExpiredTrainingImage({ workspace, id, scope, confirmExpiredDeletion, now = new Date() }) {
  const root = rootOf(workspace);
  const paths = loadJob(root, id, scope);
  return withLock(join(paths.jobDir, '.job.lock'), async () => {
    const { job } = loadJob(root, id, scope);
    if (confirmExpiredDeletion !== true) fail('confirmation-required', 'explicit confirmation is required to remove expired owned content');
    if (retentionExpiry(job) > dateMillis(now)) fail('retention-active', 'the retention period has not expired');
    const files = [];
    if (existsSync(paths.requestFile)) {
      if (!lstatSync(paths.requestFile).isFile() || hashOf(storedJson(paths.requestFile, 'prepared request')) !== id) {
        fail('request-changed', 'the stored request changed; inspect it before deletion');
      }
      files.push(paths.requestFile);
    }
    sha(job.source?.sha256, 'source hash');
    const sourceDir = directory(root, 'jobs', 'runware', id, 'source');
    const sourceFile = join(sourceDir, `${job.source.sha256}.source`);
    if (existsSync(sourceFile)) {
      checkSourceSnapshot(root, job);
      files.push(sourceFile);
    }
    const assetDir = directory(root, 'jobs', 'runware', id, 'assets');
    for (const hash of new Set(job.outputs.map((output) => output.sha256).filter(Boolean))) {
      sha(hash, 'image hash');
      const file = join(assetDir, `${hash}.png`);
      if (!existsSync(file)) continue;
      const stat = lstatSync(file);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.nlink !== 1 || stat.size > MAX_IMAGE_BYTES
        || createHash('sha256').update(readFileSync(file)).digest('hex') !== hash) {
        fail('asset-changed', 'an owned image changed; inspect it before deletion');
      }
      files.push(file);
    }
    job.status = 'purging';
    saveJob(root, paths.jobDir, job);
    for (const file of files) unlinkSync(file);
    for (const output of job.outputs) {
      if (output.sha256) output.status = 'purged';
      if (output.review) {
        const retained = { ...output.review };
        delete retained.altText;
        delete retained.textEquivalent;
        delete retained.reason;
        output.review = retained;
      }
    }
    job.status = 'expired-and-purged';
    job.purgedAt = now.toISOString();
    saveJob(root, paths.jobDir, job);
    return publicJob(root, job);
  });
}

export async function runwareImageCli(opts) {
  if (opts.provider !== 'runware') fail('invalid-input', 'illustration requires --provider runware');
  const workspace = process.env.MEDIA_STUDIO_ROOT || (process.env.LOCALAPPDATA && join(process.env.LOCALAPPDATA, 'AgentHub', 'media-studio'));
  if (!workspace) fail('invalid-input', 'set MEDIA_STUDIO_ROOT to an external media workspace');
  const root = rootOf(workspace);
  if (!opts.input) fail('invalid-input', 'illustration requires --input pointing to a private JSON file in the media workspace');
  const inputPath = workspaceFile(root, opts.input, 64 * 1024);
  let input;
  try {
    input = readJson(inputPath);
  } catch (error) {
    if (error instanceof SyntaxError) fail('invalid-input', 'illustration input is not valid JSON');
    throw error;
  }
  const options = { workspace: root, id: input.id, scope: input.scope };
  if (opts.action === 'inventory') {
    const inventory = getTrainingInventory(options);
    const redact = ({ altText, textEquivalent, ...rest }) => rest;
    console.log(JSON.stringify({
      ...inventory,
      inventoryObject: `jobs/runware/${inventory.job.id}/inventory.json`,
      outputs: inventory.outputs.map((item) => ({ ...item, review: item.review && redact(item.review) })),
      approved: inventory.approved.map(redact),
    }, null, 2));
    return 0;
  }
  let job;
  if (opts.action === 'prepare') job = await prepareTrainingImage({ workspace: root, spec: input });
  else if (opts.action === 'submit') job = await submitTrainingImage({ ...options, source: input.source, maxEstimatedUsd: input.maxEstimatedUsd });
  else if (opts.action === 'resume') job = await resumeTrainingImage(options);
  else if (opts.action === 'cancel') job = await cancelTrainingImage(options);
  else if (opts.action === 'review') job = await reviewTrainingImage({
    ...options, source: input.source, imageSha256: input.imageSha256, reviewer: input.reviewer,
    decision: input.decision, altText: input.altText, textEquivalent: input.textEquivalent,
    checklist: input.checklist, reason: input.reason,
  });
  else if (opts.action === 'purge-expired') job = await purgeExpiredTrainingImage({ ...options, confirmExpiredDeletion: input.confirmExpiredDeletion });
  else if (opts.action === 'status') job = getTrainingImage(options);
  else fail('invalid-input', 'illustration action must be prepare, submit, resume, cancel, review, status, inventory or purge-expired');
  const outputs = job.outputs.map(({ review, ...output }) => ({
    ...output,
    ...(review ? { review: {
      decision: review.decision, reviewer: review.reviewer, at: review.at, sha256: review.sha256,
      ...(review.checklist ? { checklist: review.checklist } : {}),
    } } : {}),
  }));
  console.log(JSON.stringify({
    id: job.id, taskUUID: job.taskUUID, status: job.status, selected: job.selected, effectiveStatus: job.effectiveStatus,
    provider: job.provider, requestedModel: job.requestedModel, actualModel: job.actualModel, region: job.region,
    cost: {
      estimatedUsd: job.cost.estimate.usd,
      authorizedEstimateCeilingUsd: job.cost.authorizedEstimateCeilingUsd,
      reportedOutputCostSumUsd: job.cost.reportedOutputCostSumUsd,
      allOutputCostsReported: job.cost.allOutputCostsReported,
      reportedExceedsCeiling: job.cost.reportedExceedsCeiling === true,
    },
    outputs, errors: job.errors, lastError: job.lastError,
  }, null, 2));
  if (['submit', 'resume'].includes(opts.action) && ['failed', 'partial', 'expired', 'denied', 'ambiguous-submit'].includes(job.status)) return 1;
  return 0;
}
