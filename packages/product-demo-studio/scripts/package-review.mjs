#!/usr/bin/env node
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const value = (name) => {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
};
const values = (name) => args.flatMap((arg, index) => arg === name ? [args[index + 1]] : []).filter(Boolean);
const repoArg = value("--repo");
const registryArg = value("--delivery-registry");
const decisionArg = value("--decision");
const finalArg = value("--final-verification");

function stop(message) {
  console.error(message);
  process.exit(1);
}

function canonical(path) {
  const absolute = resolve(path);
  const resolved = existsSync(absolute) ? realpathSync.native(absolute) : absolute;
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    stop(`${label} is unreadable: ${error.message}`);
  }
}

function runValidator(script, path, extraArgs = []) {
  const result = spawnSync(process.execPath, [join(scriptsDir, script), path, ...extraArgs], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`${script} blocked private review delivery:\n${result.stderr || result.stdout}`);
  }
}

function fileRecord(path) {
  const bytes = readFileSync(path);
  return {
    relativePath: basename(path),
    sha256: createHash("sha256").update(bytes).digest("hex"),
    bytes: bytes.length,
  };
}

if (!repoArg || !registryArg || !decisionArg || !finalArg) {
  stop(
    "Usage: node package-review.mjs --repo <path> --delivery-registry <registry.json> " +
      "--decision <release-decision.json> --final-verification <final-verification.json> " +
      "[--artifact <review-file> ...]",
  );
}
for (const [path, label] of [
  [repoArg, "repository"],
  [registryArg, "delivery registry"],
  [decisionArg, "release decision"],
  [finalArg, "final verification"],
]) {
  if (!existsSync(path)) stop(`${label} does not exist: ${path}`);
}

try {
  runValidator("validate-release-decision.mjs", resolve(decisionArg));
  runValidator("validate-final-verification.mjs", resolve(finalArg));
} catch (error) {
  stop(error.message);
}

const registry = readJson(resolve(registryArg), "delivery registry");
const repoPath = canonical(repoArg);
const mapping = (registry.products ?? []).find((product) => canonical(product.repositoryRoot) === repoPath);
if (!mapping) stop(`No private review-delivery mapping exists for repository: ${resolve(repoArg)}`);
if (!existsSync(mapping.reviewRoot) || !statSync(mapping.reviewRoot).isDirectory()) {
  stop(`Configured review root is not an existing directory: ${mapping.reviewRoot}`);
}
if (registry.deliveryPolicy?.classification !== "review-only" ||
    registry.deliveryPolicy?.immutableCandidateDirectories !== true ||
    registry.deliveryPolicy?.overwriteAllowed !== false ||
    registry.deliveryPolicy?.firstHumanTouchpoint !== "final-presentation" ||
    registry.deliveryPolicy?.automatedAcceptanceRequired !== true) {
  stop("Delivery registry does not enforce immutable packages, automated acceptance, and final-presentation-only human involvement.");
}

const decisionPath = resolve(decisionArg);
const finalPath = resolve(finalArg);
const decision = readJson(decisionPath, "release decision");
const finalVerification = readJson(finalPath, "final verification");
if (decision.decision !== "PASS" || finalVerification.status !== "PASS") {
  stop("Private review delivery requires both arbiter PASS and final-verifier PASS.");
}
for (const key of ["candidateId", "sha256", "bytes"]) {
  if (decision.candidate?.[key] !== finalVerification.candidate?.[key]) {
    stop(`Decision and final verification disagree on candidate ${key}.`);
  }
}

const candidatePath = resolve(dirname(finalPath), finalVerification.candidate.artifactPath);
const sourceFiles = [
  candidatePath,
  decisionPath,
  finalPath,
  ...values("--artifact").map((path) => resolve(path)),
];
const uniqueSources = [...new Set(sourceFiles.map((path) => canonical(path)))];
for (const source of uniqueSources) {
  if (!existsSync(source) || !statSync(source).isFile()) stop(`Review artifact does not exist: ${source}`);
}
const names = uniqueSources.map((path) => basename(path));
if (new Set(names.map((name) => name.toLowerCase())).size !== names.length) {
  stop("Review artifacts contain duplicate file names; rename them before creating a flat immutable package.");
}

const candidateId = finalVerification.candidate.candidateId;
const reviewDirectory = join(
  mapping.reviewRoot,
  registry.deliveryPolicy.reviewSubdirectory,
  candidateId,
);
if (existsSync(reviewDirectory)) {
  stop(`Immutable review package already exists; refusing overwrite: ${reviewDirectory}`);
}
const reviewParent = dirname(reviewDirectory);
mkdirSync(reviewParent, { recursive: true });
let stagingDirectory;
let promoted = false;
try {
  stagingDirectory = mkdtempSync(join(reviewParent, `.agenthub-${candidateId}-`));
  const records = [];
  for (const source of uniqueSources) {
    const target = join(stagingDirectory, basename(source));
    copyFileSync(source, target);
    records.push(fileRecord(target));
  }
  const recordByName = new Map(records.map((record) => [record.relativePath, record]));
  const candidateArtifact = recordByName.get(basename(candidatePath));
  if (candidateArtifact.sha256 !== finalVerification.candidate.sha256 ||
      candidateArtifact.bytes !== finalVerification.candidate.bytes) {
    throw new Error("Copied candidate bytes do not match the final-verifier candidate binding.");
  }
  const manifest = {
    schemaVersion: "1.0.0",
    classification: "review-only",
    candidate: {
      candidateId,
      artifact: candidateArtifact,
    },
    sourceRepository: resolve(repoArg),
    delivery: {
      productId: mapping.productId,
      reviewRoot: resolve(mapping.reviewRoot),
      packagePath: resolve(reviewDirectory),
      immutable: true,
    },
    gates: {
      arbiterDecision: recordByName.get(basename(decisionPath)),
      finalVerification: recordByName.get(basename(finalPath)),
    },
    files: records,
    createdAt: new Date().toISOString(),
  };
  const stagingManifestPath = join(stagingDirectory, "review-package.json");
  writeFileSync(stagingManifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  runValidator(
    "validate-review-delivery.mjs",
    stagingManifestPath,
    ["--staging-for", reviewDirectory],
  );
  renameSync(stagingDirectory, reviewDirectory);
  promoted = true;
  const manifestPath = join(reviewDirectory, "review-package.json");
  runValidator("validate-review-delivery.mjs", manifestPath);
  console.log(`Private review package ready: ${manifestPath}`);
} catch (error) {
  const cleanupTarget = promoted ? reviewDirectory : stagingDirectory;
  if (cleanupTarget && existsSync(cleanupTarget)) {
    rmSync(cleanupTarget, { recursive: true, force: true });
  }
  stop(`Private review package was not created: ${error.message}`);
}
