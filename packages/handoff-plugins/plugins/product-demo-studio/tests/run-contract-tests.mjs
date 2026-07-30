#!/usr/bin/env node
import { createHash, generateKeyPairSync, sign } from "node:crypto";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const testDir = dirname(fileURLToPath(import.meta.url));
const pluginDir = resolve(testDir, "..");
const schemaDir = join(pluginDir, "schemas");
const fixtureDir = join(testDir, "fixtures");
const schemaCache = new Map();
let assertions = 0;
let failures = 0;

function assert(condition, message) {
  assertions++;
  if (!condition) {
    failures++;
    console.error(`[fail] ${message}`);
  } else {
    console.log(`[pass] ${message}`);
  }
}

function deepEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function loadSchema(path) {
  const absolute = resolve(path);
  if (!schemaCache.has(absolute)) schemaCache.set(absolute, loadJson(absolute));
  return schemaCache.get(absolute);
}

function pointer(root, fragment) {
  if (!fragment || fragment === "#") return root;
  if (!fragment.startsWith("#/")) throw new Error(`Unsupported JSON pointer: ${fragment}`);
  return fragment.slice(2).split("/").reduce((value, part) => value[part.replaceAll("~1", "/").replaceAll("~0", "~")], root);
}

function typeMatches(type, value) {
  if (type === "object") return value !== null && typeof value === "object" && !Array.isArray(value);
  if (type === "array") return Array.isArray(value);
  if (type === "string") return typeof value === "string";
  if (type === "integer") return Number.isInteger(value);
  if (type === "number") return typeof value === "number" && Number.isFinite(value);
  if (type === "boolean") return typeof value === "boolean";
  if (type === "null") return value === null;
  return true;
}

function subValid(schema, value, schemaPath, rootSchema) {
  const nested = [];
  validate(schema, value, "$", schemaPath, rootSchema, nested);
  return nested.length === 0;
}

function validate(schema, value, instancePath, schemaPath, rootSchema, errors) {
  if (schema === true) return;
  if (schema === false) {
    errors.push(`${instancePath}: is disallowed by the schema.`);
    return;
  }

  if (schema.$ref) {
    const [refFile, refFragment = ""] = schema.$ref.split("#");
    if (refFile) {
      const targetPath = resolve(dirname(schemaPath), refFile);
      const targetRoot = loadSchema(targetPath);
      validate(pointer(targetRoot, refFragment ? `#${refFragment}` : "#"), value, instancePath, targetPath, targetRoot, errors);
    } else {
      validate(pointer(rootSchema, refFragment ? `#${refFragment}` : "#"), value, instancePath, schemaPath, rootSchema, errors);
    }
  }

  if (schema.const !== undefined && !deepEqual(value, schema.const)) errors.push(`${instancePath}: must equal ${JSON.stringify(schema.const)}.`);
  if (schema.enum && !schema.enum.some((candidate) => deepEqual(candidate, value))) errors.push(`${instancePath}: is not in the allowed enum.`);
  if (schema.type && !typeMatches(schema.type, value)) {
    errors.push(`${instancePath}: must have type ${schema.type}.`);
    return;
  }

  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${instancePath}: is shorter than minLength.`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${instancePath}: does not match pattern.`);
    if (schema.format === "date-time" && !Number.isFinite(Date.parse(value))) errors.push(`${instancePath}: is not a valid date-time.`);
  }
  if (typeof value === "number") {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${instancePath}: is below minimum.`);
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(`${instancePath}: is above maximum.`);
    if (schema.exclusiveMinimum !== undefined && value <= schema.exclusiveMinimum) errors.push(`${instancePath}: is not above exclusiveMinimum.`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) errors.push(`${instancePath}: has too few items.`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems) errors.push(`${instancePath}: has too many items.`);
    if (schema.prefixItems) {
      schema.prefixItems.forEach((itemSchema, index) => {
        if (index < value.length) validate(itemSchema, value[index], `${instancePath}[${index}]`, schemaPath, rootSchema, errors);
      });
    }
    if (schema.items === false && schema.prefixItems && value.length > schema.prefixItems.length) {
      errors.push(`${instancePath}: has items beyond prefixItems.`);
    } else if (schema.items && schema.items !== true) {
      const start = schema.prefixItems?.length ?? 0;
      for (let index = start; index < value.length; index++) {
        validate(schema.items, value[index], `${instancePath}[${index}]`, schemaPath, rootSchema, errors);
      }
    }
    if (schema.contains && !value.some((item) => subValid(schema.contains, item, schemaPath, rootSchema))) {
      errors.push(`${instancePath}: does not contain a required matching item.`);
    }
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    for (const key of schema.required ?? []) {
      if (!Object.hasOwn(value, key)) errors.push(`${instancePath}: missing required property "${key}".`);
    }
    for (const [key, propertySchema] of Object.entries(schema.properties ?? {})) {
      if (Object.hasOwn(value, key)) validate(propertySchema, value[key], `${instancePath}.${key}`, schemaPath, rootSchema, errors);
    }
    if (schema.additionalProperties === false) {
      const known = new Set(Object.keys(schema.properties ?? {}));
      for (const key of Object.keys(value)) if (!known.has(key)) errors.push(`${instancePath}: unknown property "${key}".`);
    }
  }

  for (const item of schema.allOf ?? []) validate(item, value, instancePath, schemaPath, rootSchema, errors);
  if (schema.anyOf && !schema.anyOf.some((item) => subValid(item, value, schemaPath, rootSchema))) {
    errors.push(`${instancePath}: does not satisfy anyOf.`);
  }
  if (schema.not && subValid(schema.not, value, schemaPath, rootSchema)) errors.push(`${instancePath}: satisfies a forbidden schema.`);
  if (schema.if) {
    if (subValid(schema.if, value, schemaPath, rootSchema) && schema.then) validate(schema.then, value, instancePath, schemaPath, rootSchema, errors);
    if (!subValid(schema.if, value, schemaPath, rootSchema) && schema.else) validate(schema.else, value, instancePath, schemaPath, rootSchema, errors);
  }
}

function schemaFixture(schemaName, fixtureName, expectedValid) {
  const schemaPath = join(schemaDir, schemaName);
  const schema = loadSchema(schemaPath);
  const fixture = loadJson(join(fixtureDir, fixtureName));
  const errors = [];
  validate(schema, fixture, "$", schemaPath, schema, errors);
  assert((errors.length === 0) === expectedValid, `${fixtureName} ${expectedValid ? "passes" : "fails"} ${schemaName}${errors.length ? ` (${errors.length} error(s))` : ""}`);
}

function cli(scriptName, fixtureName, expectedCode) {
  const result = spawnSync(process.execPath, [join(pluginDir, "scripts", scriptName), join(fixtureDir, fixtureName)], {
    encoding: "utf8",
  });
  assert(result.status === expectedCode, `${scriptName} ${expectedCode === 0 ? "accepts" : "rejects"} ${fixtureName}`);
  if (result.status !== expectedCode) {
    console.error(result.stdout);
    console.error(result.stderr);
  }
}

function screencastChoreographyIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-screencast-contract-"));
  try {
    const storyboard = loadJson(join(pluginDir, "scripts", "storyboard.example.json"));
    const storyboardPath = join(root, "storyboard.json");
    writeFileSync(storyboardPath, `${JSON.stringify(storyboard, null, 2)}\n`);
    let result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-storyboard.mjs"),
      storyboardPath,
    ], { encoding: "utf8" });
    assert(
      result.status === 0,
      "storyboard validator accepts explicit interaction and screen-space choreography",
    );

    const invalidStoryboard = JSON.parse(JSON.stringify(storyboard));
    delete invalidStoryboard.segments[0].interaction;
    delete invalidStoryboard.segments[1].framing;
    const invalidStoryboardPath = join(root, "storyboard.invalid.json");
    writeFileSync(invalidStoryboardPath, `${JSON.stringify(invalidStoryboard, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-storyboard.mjs"),
      invalidStoryboardPath,
    ], { encoding: "utf8" });
    assert(
      result.status !== 0,
      "storyboard validator rejects missing interaction or screen-space choreography",
    );

    const capture = {
      scenario: "synthetic-guided-screencast",
      beat: "review-exception",
      route: "/synthetic/review",
      viewport: { width: 1920, height: 1080, deviceScaleFactor: 2 },
      focus: { x: 900, y: 160, width: 850, height: 700 },
      protectedRegions: [{ x: 1180, y: 240, width: 520, height: 420 }],
      captureSurface: {
        mode: "page-only",
        extraneousChrome: "none",
        irrelevantNavigation: "collapsed",
        plannedTreatment: "push-in",
        plannedActiveRegionCoverage: 0.68,
        deliveryLegibility: "pass",
      },
      interaction: {
        kind: "click",
        target: "button[data-demo='review-exception']",
        cursor: {
          from: [1450, 780],
          to: [1520, 430],
          park: [1760, 930],
          durationMs: 700,
        },
        cue: "visual",
        narrationSync: {
          cursorLeadSeconds: 0.35,
          actionAtSeconds: 1.1,
          resultVisibleAtSeconds: 1.8,
          spokenResultAtSeconds: 2.0,
        },
      },
    };
    const capturePath = join(root, "capture.json");
    writeFileSync(capturePath, `${JSON.stringify(capture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      capturePath,
    ], { encoding: "utf8" });
    assert(
      result.status === 0,
      "capture validator accepts page-only framing and action-before-spoken-result timing",
    );

    capture.captureSurface.plannedActiveRegionCoverage = 0.3;
    capture.interaction.cue = "none";
    capture.interaction.narrationSync.spokenResultAtSeconds = 1.2;
    const invalidCapturePath = join(root, "capture.invalid.json");
    writeFileSync(invalidCapturePath, `${JSON.stringify(capture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      invalidCapturePath,
    ], { encoding: "utf8" });
    assert(
      result.status !== 0,
      "capture validator rejects wasted screen space, invisible clicks, and premature narration",
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function reviewDeliveryIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-review-delivery-"));
  try {
    const files = [
      ["candidate.mp4", Buffer.from("synthetic candidate")],
      ["decision.json", Buffer.from('{"decision":"PASS"}')],
      ["final.json", Buffer.from('{"status":"PASS"}')],
    ];
    const records = [];
    for (const [name, bytes] of files) {
      writeFileSync(join(root, name), bytes);
      records.push({
        relativePath: name,
        sha256: shaBytes(bytes),
        bytes: bytes.length,
      });
    }
    const manifestPath = join(root, "review-package.json");
    writeFileSync(manifestPath, `${JSON.stringify({
      schemaVersion: "1.0.0",
      classification: "review-only",
      candidate: {
        candidateId: "synthetic-candidate-001",
        artifact: records[0],
      },
      sourceRepository: "C:/Repos/synthetic/product",
      delivery: {
        productId: "synthetic-product",
        reviewRoot: root,
        packagePath: root,
        immutable: true,
      },
      gates: {
        arbiterDecision: records[1],
        finalVerification: records[2],
      },
      humanReview: {
        status: "pending",
        publicationApproved: false,
      },
      files: records,
      createdAt: "2026-07-30T12:00:00.000Z",
    }, null, 2)}\n`);
    let result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-review-delivery.mjs"),
      manifestPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "private review delivery validator accepts an immutable review-only package");

    writeFileSync(join(root, "candidate.mp4"), "mutated candidate");
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-review-delivery.mjs"),
      manifestPath,
    ], { encoding: "utf8" });
    assert(result.status !== 0, "private review delivery validator rejects changed candidate bytes");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function sha(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

function shaBytes(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function createExecutionTrust(root) {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const publicKeyPath = join(root, "synthetic-execution-host.pem");
  const trustPath = join(root, "execution-host-trust.json");
  writeFileSync(publicKeyPath, publicKey.export({ type: "spki", format: "pem" }), "utf8");
  writeJson(trustPath, {
    schemaVersion: "1.0.0",
    hosts: [{
      hostId: "synthetic-contract-host",
      keyId: "synthetic-contract-key",
      enabled: true,
      publicKeyPath: "synthetic-execution-host.pem",
      publicKeySha256: shaBytes(publicKey.export({ type: "spki", format: "der" })),
      allowedRoles: ["reviewer", "arbiter", "final-verifier"],
      allowedMechanisms: ["container-read-only-mount"],
      allowedReadOnlyTools: ["filesystem-read", "media-inspect", "checksum"],
    }],
  });
  let sequence = 0;
  const signedReceipt = ({
    baseDir = root,
    role,
    domain,
    contextId,
    candidateId,
    startedAt,
    completedAt,
    issuedAt = completedAt,
  }) => {
    sequence += 1;
    const slug = `${role}-${String(sequence).padStart(3, "0")}`;
    const receiptPath = join(baseDir, `execution-receipt-${slug}.json`);
    const signaturePath = join(baseDir, `execution-receipt-${slug}.ed25519`);
    const receipt = {
      schemaVersion: "1.0.0",
      receiptId: `PVE-${role.replaceAll("-", "").toUpperCase()}-${String(sequence).padStart(3, "0")}`,
      immutable: true,
      role,
      ...(domain ? { domain } : {}),
      contextId,
      candidateId,
      hostId: "synthetic-contract-host",
      hostKeyId: "synthetic-contract-key",
      mechanism: "container-read-only-mount",
      readOnly: true,
      writeTools: [],
      permittedReadOnlyTools: ["filesystem-read", "media-inspect", "checksum"],
      startedAt,
      completedAt,
      issuedAt,
    };
    writeJson(receiptPath, receipt);
    writeFileSync(signaturePath, sign(null, readFileSync(receiptPath), privateKey));
    const reference = (path) => ({
      artifactPath: path.replaceAll("\\", "/").split("/").at(-1),
      sha256: sha(path),
      bytes: statSync(path).size,
    });
    return {
      receipt: reference(receiptPath),
      signature: reference(signaturePath),
    };
  };
  return {
    environment: {
      ...process.env,
      AGENTHUB_EXECUTION_HOST_TRUST_CONFIG: trustPath,
    },
    privateKey,
    publicKey,
    signedReceipt,
    trustPath,
  };
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function generateRealCandidate(videoPath) {
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-f", "lavfi",
    "-i", "testsrc2=size=320x180:rate=30",
    "-f", "lavfi",
    "-i", "sine=frequency=1000:sample_rate=48000",
    "-t", "2",
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-color_primaries", "bt709",
    "-color_trc", "bt709",
    "-colorspace", "bt709",
    "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
    "-c:a", "aac",
    "-ac", "2",
    "-ar", "48000",
    "-af", "loudnorm=I=-16:TP=-1.5:LRA=7",
    "-movflags", "+faststart",
    "-y",
    videoPath,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`FFmpeg could not generate the real candidate: ${result.stderr || result.stdout}`);
  }
}

function buildPassingEvidence(root, candidateId) {
  const generatedAt = "2026-07-29T22:00:00.000Z";
  const artifacts = [];
  const addArtifact = (artifactId, type, name, mediaType, content, { existing = false } = {}) => {
    const path = join(root, name);
    if (!existing) {
      if (typeof content === "string") writeFileSync(path, content, "utf8");
      else writeJson(path, content);
    }
    const artifact = {
      artifactId,
      type,
      artifactPath: name,
      sha256: sha(path),
      mediaType,
      bytes: statSync(path).size,
    };
    artifacts.push(artifact);
    return artifact;
  };

  const candidatePath = join(root, "candidate.mp4");
  generateRealCandidate(candidatePath);
  const media = addArtifact("media", "video", "candidate.mp4", "video/mp4", null, { existing: true });
  const build = addArtifact("build-manifest", "manifest", "build.json", "application/json", { synthetic: true });
  const config = addArtifact("configuration-manifest", "manifest", "configuration.json", "application/json", { locale: "en-US" });
  const environment = addArtifact("environment-manifest", "manifest", "environment.json", "application/json", { runtime: "synthetic" });
  const reportChecks = {
    mediaMetadata: ["artifact-completeness", "output-specifications"],
    framesAndContactSheets: ["asset-completeness"],
    sceneBoundaries: ["frame-duplicate"],
    frameIntegrity: ["frame-black", "frame-frozen", "frame-corruption"],
    audioQuality: ["audio-loudness", "audio-clipping", "audio-silence"],
    asrWordTimestamps: ["script-narration-caption-parity"],
    captionTimingAndLayout: ["caption-overflow-obstruction-speed-safe-areas"],
    ocrVisibleText: ["names-dates-numbers-claims"],
    motionAnalysis: ["render-errors"],
    browserPlayback: ["browser-console-network"],
    browserConsole: ["browser-console-network"],
    browserNetwork: ["browser-console-network"],
    technicalDelivery: ["checksums-provenance", "output-specifications"],
    claimVerification: ["names-dates-numbers-claims"],
    truthSheetVerification: ["names-dates-numbers-claims"],
  };
  const reportGenerators = {
    mediaMetadata: "product-demo-studio-technical-checks",
    framesAndContactSheets: "product-demo-studio-technical-checks",
    sceneBoundaries: "product-demo-studio-technical-checks",
    frameIntegrity: "product-demo-studio-technical-checks",
    audioQuality: "product-demo-studio-technical-checks",
    asrWordTimestamps: "repository-native-asr",
    captionTimingAndLayout: "repository-native-caption-validator",
    ocrVisibleText: "repository-native-ocr",
    motionAnalysis: "product-demo-studio-technical-checks",
    browserPlayback: "repository-native-playwright",
    browserConsole: "repository-native-playwright",
    browserNetwork: "repository-native-playwright",
    technicalDelivery: "product-demo-studio-technical-checks",
    claimVerification: "repository-native-claim-validator",
    truthSheetVerification: "repository-native-truth-sheet-validator",
  };
  const reports = {};
  for (const [reportType, checkIds] of Object.entries(reportChecks)) {
    const report = {
      schemaVersion: "1.0.0",
      candidateId,
      reportType,
      status: "PASS",
      generator: {
        tool: reportGenerators[reportType],
        version: "1.0.0",
        command: `synthetic-fixture ${reportType} --input ${media.sha256}`,
      },
      inputs: [{ artifactId: media.artifactId, sha256: media.sha256 }],
      checks: checkIds.map((id) => ({ id, passed: true, evidenceArtifactIds: [media.artifactId] })),
      summary: { total: checkIds.length, passed: checkIds.length, failed: 0 },
      generatedAt,
    };
    const artifact = addArtifact(
      `report-${reportType}`,
      "report",
      `${reportType}.json`,
      "application/json",
      report,
    );
    reports[reportType] = {
      artifactId: artifact.artifactId,
      artifactPath: artifact.artifactPath,
      sha256: artifact.sha256,
      candidateId,
      reportType,
      status: "PASS",
      generatedAt,
    };
  }
  const evidencePackage = {
    schemaVersion: "1.0.0",
    candidate: { candidateId, immutable: true, mediaArtifactId: media.artifactId },
    provenance: {
      source: { repository: "https://example.invalid/synthetic.git", revision: "0123456789abcdef", dirty: false },
      build: { buildId: "synthetic-build", manifest: { artifactId: build.artifactId, artifactPath: build.artifactPath, sha256: build.sha256 } },
      configuration: { manifest: { artifactId: config.artifactId, artifactPath: config.artifactPath, sha256: config.sha256 } },
      render: {
        renderId: "synthetic-render-001",
        renderer: "ffmpeg-synthetic-fixture",
        pipelineVersion: "1.0.0",
        command: "ffmpeg testsrc2+sine deterministic candidate",
        environmentManifest: {
          artifactId: environment.artifactId,
          artifactPath: environment.artifactPath,
          sha256: environment.sha256,
        },
        startedAt: "2026-07-29T21:59:00.000Z",
        completedAt: generatedAt,
      },
    },
    artifacts,
    reports,
    createdAt: generatedAt,
  };
  const evidencePath = join(root, "evidence-package.json");
  const preflightPath = join(root, "preflight-report.json");
  writeJson(evidencePath, evidencePackage);
  const result = spawnSync(process.execPath, [
    join(pluginDir, "scripts", "preflight.mjs"),
    "--evidence-package", evidencePath,
    "--out", preflightPath,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`Canonical fixture preflight failed: ${result.stderr || result.stdout}`);
  }
  return {
    candidatePath,
    evidencePath,
    preflightPath,
    candidate: {
      candidateId,
      artifactPath: "candidate.mp4",
      sha256: media.sha256,
      bytes: media.bytes,
      sourceRevision: "0123456789abcdef",
      renderProvenanceId: "synthetic-render-001",
    },
  };
}

function executionReceiptIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-execution-receipt-"));
  try {
    const trust = createExecutionTrust(root);
    const bundle = trust.signedReceipt({
      role: "reviewer",
      domain: "story-experience",
      contextId: "isolated-receipt-context",
      candidateId: "synthetic-receipt-candidate",
      startedAt: "2026-07-29T20:00:00.000Z",
      completedAt: "2026-07-29T20:05:00.000Z",
    });
    const receiptPath = join(root, bundle.receipt.artifactPath);
    const signaturePath = join(root, bundle.signature.artifactPath);
    const validator = join(pluginDir, "scripts", "validate-execution-receipt.mjs");
    const run = (receipt = receiptPath, signature = signaturePath, environment = trust.environment) =>
      spawnSync(process.execPath, [validator, receipt, signature], {
        encoding: "utf8",
        env: environment,
      });

    assert(run().status === 0, "execution receipt accepts an exact signature from an authorized host key");

    const missingTrustEnvironment = { ...process.env };
    delete missingTrustEnvironment.AGENTHUB_EXECUTION_HOST_TRUST_CONFIG;
    assert(run(receiptPath, signaturePath, missingTrustEnvironment).status === 1,
      "execution receipt fails closed without the operator-owned host trust registry");

    const originalReceipt = readFileSync(receiptPath);
    const originalSignature = readFileSync(signaturePath);
    const originalTrust = readFileSync(trust.trustPath);
    const receiptDocument = JSON.parse(originalReceipt.toString("utf8"));
    const rewriteSignedReceipt = (changes) => {
      writeJson(receiptPath, { ...receiptDocument, ...changes });
      writeFileSync(signaturePath, sign(null, readFileSync(receiptPath), trust.privateKey));
    };

    rewriteSignedReceipt({ hostKeyId: "unknown-host-key" });
    assert(run().status === 1, "execution receipt rejects an unknown host key");

    rewriteSignedReceipt({ mechanism: "os-filesystem-read-only-sandbox" });
    assert(run().status === 1, "execution receipt rejects a mechanism not authorized for the host key");

    rewriteSignedReceipt({ permittedReadOnlyTools: ["filesystem-read", "github-read"] });
    assert(run().status === 1, "execution receipt rejects a read tool not authorized for the host key");

    writeFileSync(receiptPath, originalReceipt);
    writeFileSync(signaturePath, originalSignature);
    const disabledTrust = JSON.parse(originalTrust.toString("utf8"));
    disabledTrust.hosts[0].enabled = false;
    writeJson(trust.trustPath, disabledTrust);
    assert(run().status === 1, "execution receipt rejects a disabled host key");

    const badFingerprintTrust = JSON.parse(originalTrust.toString("utf8"));
    badFingerprintTrust.hosts[0].publicKeySha256 = "0".repeat(64);
    writeJson(trust.trustPath, badFingerprintTrust);
    assert(run().status === 1, "execution receipt rejects a trusted-key fingerprint mismatch");

    writeFileSync(trust.trustPath, originalTrust);
    writeFileSync(receiptPath, Buffer.concat([originalReceipt, Buffer.from("\n")]));
    assert(run().status === 1, "execution receipt rejects receipt-byte tampering after signing");

    writeFileSync(receiptPath, originalReceipt);
    const tamperedSignature = Buffer.from(originalSignature);
    tamperedSignature[0] ^= 0xff;
    writeFileSync(signaturePath, tamperedSignature);
    assert(run().status === 1, "execution receipt rejects detached-signature tampering");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function preflightIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-preflight-"));
  try {
    mkdirSync(root, { recursive: true });
    const generatedAt = "2026-07-29T22:00:00.000Z";
    const candidateId = "synthetic-system-fixture-v1";
    const artifacts = [];
    const addArtifact = (artifactId, type, name, mediaType, content) => {
      const path = join(root, name);
      if (typeof content === "string") writeFileSync(path, content, "utf8");
      else writeJson(path, content);
      const artifact = {
        artifactId,
        type,
        artifactPath: name,
        sha256: sha(path),
        mediaType,
        bytes: statSync(path).size,
      };
      artifacts.push(artifact);
      return artifact;
    };

    const media = addArtifact("media", "video", "candidate.mp4", "video/mp4", "synthetic-video-fixture");
    const build = addArtifact("build-manifest", "manifest", "build.json", "application/json", { synthetic: true });
    const config = addArtifact("configuration-manifest", "manifest", "configuration.json", "application/json", { locale: "en-US" });
    const environment = addArtifact("environment-manifest", "manifest", "environment.json", "application/json", { runtime: "synthetic" });
    const reportChecks = {
      mediaMetadata: ["artifact-completeness", "output-specifications"],
      framesAndContactSheets: ["asset-completeness"],
      sceneBoundaries: ["frame-duplicate"],
      frameIntegrity: ["frame-black", "frame-frozen", "frame-corruption"],
      audioQuality: ["audio-loudness", "audio-clipping", "audio-silence"],
      asrWordTimestamps: ["script-narration-caption-parity"],
      captionTimingAndLayout: ["caption-overflow-obstruction-speed-safe-areas"],
      ocrVisibleText: ["names-dates-numbers-claims"],
      motionAnalysis: ["render-errors"],
      browserPlayback: ["browser-console-network"],
      browserConsole: ["browser-console-network"],
      browserNetwork: ["browser-console-network"],
      technicalDelivery: ["checksums-provenance", "output-specifications"],
      claimVerification: ["names-dates-numbers-claims"],
      truthSheetVerification: ["names-dates-numbers-claims"],
    };
    const reportGenerators = {
      mediaMetadata: "product-demo-studio-technical-checks",
      framesAndContactSheets: "product-demo-studio-technical-checks",
      sceneBoundaries: "product-demo-studio-technical-checks",
      frameIntegrity: "product-demo-studio-technical-checks",
      audioQuality: "product-demo-studio-technical-checks",
      asrWordTimestamps: "repository-native-asr",
      captionTimingAndLayout: "repository-native-caption-validator",
      ocrVisibleText: "repository-native-ocr",
      motionAnalysis: "product-demo-studio-technical-checks",
      browserPlayback: "repository-native-playwright",
      browserConsole: "repository-native-playwright",
      browserNetwork: "repository-native-playwright",
      technicalDelivery: "product-demo-studio-technical-checks",
      claimVerification: "repository-native-claim-validator",
      truthSheetVerification: "repository-native-truth-sheet-validator",
    };
    const reports = {};
    for (const [reportType, checkIds] of Object.entries(reportChecks)) {
      const report = {
        schemaVersion: "1.0.0",
        candidateId,
        reportType,
        status: "PASS",
        generator: {
          tool: reportGenerators[reportType],
          version: "1.0.0",
          command: `node synthetic-${reportType}-extractor.mjs`,
        },
        inputs: [
          {
            artifactId: media.artifactId,
            sha256: media.sha256,
          },
        ],
        checks: checkIds.map((id) => ({ id, passed: true, evidenceArtifactIds: ["media"] })),
        summary: { total: checkIds.length, passed: checkIds.length, failed: 0 },
        generatedAt,
      };
      const artifact = addArtifact(
        `report-${reportType}`,
        "report",
        `${reportType}.json`,
        "application/json",
        report,
      );
      reports[reportType] = {
        artifactId: artifact.artifactId,
        artifactPath: artifact.artifactPath,
        sha256: artifact.sha256,
        candidateId,
        reportType,
        status: "PASS",
        generatedAt,
      };
    }
    const evidencePackage = {
      schemaVersion: "1.0.0",
      candidate: { candidateId, immutable: true, mediaArtifactId: media.artifactId },
      provenance: {
        source: { repository: "https://example.invalid/synthetic.git", revision: "0123456789abcdef", dirty: false },
        build: { buildId: "synthetic-build", manifest: { artifactId: build.artifactId, artifactPath: build.artifactPath, sha256: build.sha256 } },
        configuration: { manifest: { artifactId: config.artifactId, artifactPath: config.artifactPath, sha256: config.sha256 } },
        render: {
          renderId: "synthetic-render",
          renderer: "fixture",
          pipelineVersion: "1.0.0",
          command: "node synthetic-render.mjs",
          environmentManifest: {
            artifactId: environment.artifactId,
            artifactPath: environment.artifactPath,
            sha256: environment.sha256,
          },
          startedAt: "2026-07-29T21:59:00.000Z",
          completedAt: generatedAt,
        },
      },
      artifacts,
      reports,
      createdAt: generatedAt,
    };
    const evidencePath = join(root, "evidence-package.json");
    const preflightPath = join(root, "preflight-report.json");
    writeJson(evidencePath, evidencePackage);
    let result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"),
      "--evidence-package", evidencePath,
      "--out", preflightPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "preflight accepts a complete immutable synthetic evidence package");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }
    const preflight = loadJson(preflightPath);
    assert(preflight.status === "PASS" && preflight.readyForIndependentReview === true,
      "preflight emits a PASS report ready for independent review");
    const schemaPath = join(schemaDir, "preflight-report.schema.json");
    const schema = loadSchema(schemaPath);
    const validationErrors = [];
    validate(schema, preflight, "$", schemaPath, schema, validationErrors);
    assert(validationErrors.length === 0, "generated preflight report conforms to preflight-report.schema.json");

    const asrPath = join(root, "asrWordTimestamps.json");
    const originalAsr = readFileSync(asrPath);
    const inventedGeneratorReport = JSON.parse(originalAsr.toString("utf8"));
    inventedGeneratorReport.generator.tool = "invented-all-pass-extractor";
    writeJson(asrPath, inventedGeneratorReport);
    const inventedEvidence = structuredClone(evidencePackage);
    const asrArtifact = inventedEvidence.artifacts.find((artifact) => artifact.artifactId === "report-asrWordTimestamps");
    asrArtifact.sha256 = sha(asrPath);
    asrArtifact.bytes = statSync(asrPath).size;
    inventedEvidence.reports.asrWordTimestamps.sha256 = asrArtifact.sha256;
    writeJson(evidencePath, inventedEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"),
      "--evidence-package", evidencePath,
      "--out", preflightPath,
    ], { encoding: "utf8" });
    assert(result.status === 1, "preflight rejects an unregistered deterministic-report generator even when hashes match");
    writeFileSync(asrPath, originalAsr);
    writeJson(evidencePath, evidencePackage);

    writeFileSync(join(root, media.artifactPath), "tampered", "utf8");
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"),
      "--evidence-package", evidencePath,
      "--out", preflightPath,
    ], { encoding: "utf8" });
    assert(result.status === 1, "preflight rejects checksum and byte-count drift");
    const failed = loadJson(preflightPath);
    assert(failed.status === "FAIL" && failed.readyForIndependentReview === false,
      "failed preflight blocks independent review");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function realMediaIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-media-"));
  try {
    const videoPath = join(root, "candidate.mp4");
    const evidenceDir = join(root, "technical");
    const deterministicDir = join(root, "deterministic");
    const specPath = join(root, "delivery-spec.json");
    const spec = loadJson(join(fixtureDir, "delivery-spec.pass.json"));
    writeJson(specPath, spec);

    let result = spawnSync("ffmpeg", [
      "-v", "error",
      "-f", "lavfi",
      "-i", "testsrc2=size=320x180:rate=30",
      "-f", "lavfi",
      "-i", "sine=frequency=1000:sample_rate=48000",
      "-t", "2",
      "-c:v", "libx264",
      "-pix_fmt", "yuv420p",
      "-color_primaries", "bt709",
      "-color_trc", "bt709",
      "-colorspace", "bt709",
      "-x264-params", "colorprim=bt709:transfer=bt709:colormatrix=bt709",
      "-c:a", "aac",
      "-ac", "2",
      "-ar", "48000",
      "-af", "loudnorm=I=-16:TP=-1.5:LRA=7",
      "-movflags", "+faststart",
      "-y",
      videoPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "FFmpeg generates the deterministic real-media fixture");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
      return;
    }

    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "technical-checks.mjs"),
      "--video", videoPath,
      "--out", evidenceDir,
      "--spec", specPath,
      "--candidate-id", "synthetic-real-media-v1",
      "--artifact-id", "candidate-media",
      "--deterministic-out", deterministicDir,
    ], { encoding: "utf8" });
    assert(result.status === 0, "technical checks accept media that matches the declared delivery spec");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
      return;
    }
    const technical = loadJson(join(evidenceDir, "technical-report.json"));
    assert(
      technical.pass === true &&
        technical.checks.decodeIntegrity.status === "ok" &&
        technical.checks.fastStart.enabled === true,
      "real-media evidence proves decode integrity and MP4 fast start",
    );
    assert(
      technical.checks.metadata.colorSpace === "bt709" &&
        technical.checks.metadata.colorTransfer === "bt709" &&
        technical.checks.metadata.colorPrimaries === "bt709",
      "real-media evidence verifies declared color metadata",
    );
    const deterministicSchemaPath = join(schemaDir, "deterministic-report.schema.json");
    const deterministicSchema = loadSchema(deterministicSchemaPath);
    for (const reportType of [
      "mediaMetadata",
      "framesAndContactSheets",
      "sceneBoundaries",
      "frameIntegrity",
      "audioQuality",
      "motionAnalysis",
      "technicalDelivery",
    ]) {
      const report = loadJson(join(deterministicDir, `${reportType}.json`));
      const errors = [];
      validate(
        deterministicSchema,
        report,
        "$",
        deterministicSchemaPath,
        deterministicSchema,
        errors,
      );
      assert(
        errors.length === 0 && report.status === "PASS" &&
          report.inputs[0].sha256 === sha(videoPath),
        `${reportType} is schema-valid and checksum-bound to exact media bytes`,
      );
    }

    spec.video.width = 640;
    writeJson(specPath, spec);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "technical-checks.mjs"),
      "--video", videoPath,
      "--out", join(root, "mismatch"),
      "--spec", specPath,
    ], { encoding: "utf8" });
    assert(result.status === 1, "technical checks reject media that differs from the declared output spec");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function videoCliGateIntegration() {
  const cliPath = join(pluginDir, "scripts", "video-cli.mjs");
  for (const verb of ["review", "arbitrate", "all", "revise"]) {
    const args = [cliPath, verb];
    if (verb === "all") args.push("--repo", pluginDir);
    const result = spawnSync(process.execPath, args, { encoding: "utf8" });
    assert(result.status === 2, `video-cli ${verb} is explicitly advisory and cannot report gate success`);
  }

  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-package-"));
  try {
    const result = spawnSync(process.execPath, [
      cliPath,
      "package",
      "--repo", pluginDir,
      "--out", join(root, "invalid-bundle.json"),
      "--decision", join(root, "missing-decision.json"),
      "--final-verification", join(root, "missing-final-verification.json"),
      "--release-evidence", join(root, "missing-release-evidence.json"),
      join(root, "missing.mp4"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "video-cli package rejects missing gate files and deliverables instead of skipping them");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function releaseDecisionIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-release-"));
  try {
    const policyDir = join(root, "policy");
    const reviewsDir = join(root, "reviews");
    const remediationDir = join(root, "remediation");
    mkdirSync(policyDir, { recursive: true });
    mkdirSync(reviewsDir, { recursive: true });
    mkdirSync(remediationDir, { recursive: true });
    const executionTrust = createExecutionTrust(root);

    const canonicalPolicyPath = join(pluginDir, "policy", "product-video-policy.json");
    const policyPath = join(policyDir, "product-video-policy.json");
    writeFileSync(policyPath, readFileSync(canonicalPolicyPath));
    const generatedAt = "2026-07-29T22:00:00.000Z";
    const passingEvidence = buildPassingEvidence(root, "synthetic-release-candidate");
    const {
      candidatePath,
      evidencePath,
      preflightPath,
      candidate,
    } = passingEvidence;
    const syncEvidencePath = join(root, "sync-report.json");
    writeJson(syncEvidencePath, { schemaVersion: "1.0.0", status: "FAIL", findingId: "PVF-AUDIO-SYNC-001" });

    const reportCandidate = {
      candidateId: candidate.candidateId,
      artifactPath: candidate.artifactPath,
      sha256: candidate.sha256,
      sourceRevision: candidate.sourceRevision,
      renderProvenanceId: candidate.renderProvenanceId,
    };
    const evidenceReference = { artifactPath: "evidence-package.json", sha256: sha(evidencePath) };
    const policyReference = {
      artifactPath: "policy/product-video-policy.json",
      sha256: sha(policyPath),
      policyVersion: "1.0.0",
    };
    const domainChecks = {
      "story-experience": [
        "hook", "before-state", "outcome", "hero-moment", "wiifm", "emotional-payoff",
        "pacing", "visual-direction", "result-holds", "ending", "story-product-alignment",
      ],
      "screen-accuracy-compliance": [
        "visible-values", "product-behavior", "permissions", "claims", "state-freshness",
        "layouts", "annotations", "branding", "privacy", "disclosures", "content-freshness",
      ],
      "audio-captions-synchronization": [
        "narration-accuracy", "pronunciation", "pacing", "loudness", "clipping", "music-balance",
        "action-synchronization", "pauses", "result-holds", "caption-accuracy", "caption-timing",
        "reading-speed", "caption-layout", "accessibility",
      ],
      "technical-frame-integrity": [
        "codecs", "resolution", "aspect-ratio", "frame-rate", "color", "audio-streams",
        "fast-start", "checksums", "frame-integrity", "browser-playback", "assets",
        "deterministic-rendering", "naming", "platform-compatibility", "provenance",
      ],
    };
    const slugs = {
      "story-experience": "story",
      "screen-accuracy-compliance": "screen",
      "audio-captions-synchronization": "audio",
      "technical-frame-integrity": "technical",
    };
    const scores = {
      "story-experience": 92,
      "screen-accuracy-compliance": 100,
      "audio-captions-synchronization": 98,
      "technical-frame-integrity": 100,
    };

    function finding() {
      return {
        schemaVersion: "1.0.0",
        id: "PVF-AUDIO-SYNC-001",
        category: "audio-captions-synchronization",
        severity: "major",
        fixClassification: "narration-audio",
        location: {
          startTimestampMs: 0,
          endTimestampMs: 1000,
          startFrame: 0,
          endFrame: 30,
          fps: 30,
        },
        expectedBehavior: "Narration and product action are synchronized.",
        observedBehavior: "Narration precedes the visible product action.",
        impact: "The viewer cannot confidently connect the claim to the demonstrated result.",
        evidence: [{
          artifactId: "sync-report",
          artifactPath: "sync-report.json",
          sha256: sha(syncEvidencePath),
          description: "Deterministic word-to-frame synchronization report.",
        }],
        concreteFix: {
          summary: "Align narration timing to the captured action.",
          steps: ["Move the narration cue to the action frame.", "Rerender and rerun synchronization checks."],
        },
        automatedValidation: {
          command: "node scripts/validate-release-decision.mjs decision.json",
          expectedResult: "The synchronization report passes and the reviewer reports no finding.",
        },
        confidence: 0.99,
      };
    }

    function writeReports({ audioFinding = false, malformedDomain } = {}) {
      const references = [];
      for (const [domain, checks] of Object.entries(domainChecks)) {
        const slug = slugs[domain];
        const reportPath = join(reviewsDir, `${slug}.json`);
        const common = {
          schemaVersion: "1.0.0",
          reportId: `PVR-SYNTHETIC-${slug.toUpperCase()}-001`,
          status: domain === malformedDomain ? "MALFORMED_INPUT" : "COMPLETE",
          candidate: reportCandidate,
          reviewer: {
            domain,
            contextId: `isolated-${slug}-context`,
            readOnly: true,
            executionReceipt: executionTrust.signedReceipt({
              baseDir: reviewsDir,
              role: "reviewer",
              domain,
              contextId: `isolated-${slug}-context`,
              candidateId: candidate.candidateId,
              startedAt: "2026-07-29T22:01:00.000Z",
              completedAt: "2026-07-29T22:02:00.000Z",
            }),
            startedAt: "2026-07-29T22:01:00.000Z",
            completedAt: "2026-07-29T22:02:00.000Z",
          },
          evidencePackage: evidenceReference,
          summary: `Synthetic ${domain} independent review.`,
        };
        if (domain === malformedDomain) {
          writeJson(reportPath, {
            ...common,
            missingEvidence: ["frame-integrity-report"],
            reason: "Required deterministic evidence is absent.",
          });
          references.push({
            domain,
            reportPath: `reviews/${slug}.json`,
            sha256: sha(reportPath),
            status: "MALFORMED_INPUT",
          });
          continue;
        }
        const hasFinding = audioFinding && domain === "audio-captions-synchronization";
        const reportFindings = hasFinding ? [finding()] : [];
        const reportScore = hasFinding ? 94 : scores[domain];
        writeJson(reportPath, {
          ...common,
          score: reportScore,
          checks: checks.map((id, index) => ({
            id,
            passed: !(hasFinding && index === 0),
            evidenceArtifactIds: ["synthetic-evidence"],
          })),
          domainPass: !hasFinding,
          findings: reportFindings,
        });
        references.push({
          domain,
          reportPath: `reviews/${slug}.json`,
          sha256: sha(reportPath),
          status: "COMPLETE",
          score: reportScore,
          passed: !hasFinding,
          findingCount: reportFindings.length,
          blockerFindings: 0,
          criticalFindings: 0,
        });
      }
      return references;
    }

    const releaseChecks = {
      accuracy: true,
      compliance: true,
      privacy: true,
      technicalIntegrity: true,
      browserPlayback: true,
      claims: true,
      checksums: true,
      provenance: true,
      captions: true,
      synchronization: true,
      visualIntegrity: true,
    };
    const decisionBase = {
      schemaVersion: "1.0.0",
      decisionId: "PVD-SYNTHETIC-RELEASE-001",
      candidate,
      arbiter: {
        contextId: "isolated-arbiter-context",
        readOnly: true,
        executionReceipt: executionTrust.signedReceipt({
          role: "arbiter",
          contextId: "isolated-arbiter-context",
          candidateId: candidate.candidateId,
          startedAt: "2026-07-29T22:02:00.000Z",
          completedAt: "2026-07-29T22:03:00.000Z",
        }),
      },
      policy: policyReference,
      preflight: { artifactPath: "preflight-report.json", sha256: sha(preflightPath) },
      reviewReports: writeReports(),
      releaseChecks,
      findingDispositions: [],
      evidenceValidation: {
        allReportsValidated: true,
        unsupportedFindingsRejected: true,
        overlapsDeduplicated: true,
        contradictionsResolved: true,
      },
      decision: "PASS",
      rationale: "The synthetic candidate passes every canonical release gate.",
      decidedAt: "2026-07-29T22:03:00.000Z",
    };
    const decisionPath = join(root, "decision.json");
    const run = (value) => {
      writeJson(decisionPath, value);
      return spawnSync(process.execPath, [join(pluginDir, "scripts", "validate-release-decision.mjs"), decisionPath], {
        encoding: "utf8",
        env: executionTrust.environment,
      });
    };

    let result = run(decisionBase);
    assert(result.status === 0, "release validator accepts a fully materialized PASS decision");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }

    result = run({ ...decisionBase, candidate: { ...candidate, artifactPath: "missing-candidate.mp4" } });
    assert(result.status === 1, "release validator rejects a nonexistent candidate reference");

    const missingReport = structuredClone(decisionBase);
    missingReport.reviewReports[0].reportPath = "reviews/missing-story.json";
    result = run(missingReport);
    assert(result.status === 1, "release validator rejects a nonexistent review report reference");

    const forgedSummary = structuredClone(decisionBase);
    forgedSummary.reviewReports[0].score = 100;
    result = run(forgedSummary);
    assert(result.status === 1, "release validator rejects a decision summary that differs from the review report");

    const wrongPolicy = structuredClone(decisionBase);
    writeJson(policyPath, { ...loadJson(canonicalPolicyPath), schemaVersion: "9.9.9" });
    wrongPolicy.policy.sha256 = sha(policyPath);
    result = run(wrongPolicy);
    assert(result.status === 1, "release validator rejects a noncanonical policy even when its copied hash matches");
    writeFileSync(policyPath, readFileSync(canonicalPolicyPath));

    const remediationPath = join(remediationDir, "audio-sync.json");
    writeJson(remediationPath, { assignmentId: "synthetic-audio-sync" });
    const remediate = structuredClone(decisionBase);
    remediate.decisionId = "PVD-SYNTHETIC-RELEASE-002";
    remediate.reviewReports = writeReports({ audioFinding: true });
    remediate.releaseChecks.synchronization = false;
    remediate.findingDispositions = [{
      findingId: "PVF-AUDIO-SYNC-001",
      disposition: "accepted",
      rationale: "The deterministic synchronization report reproduces the defect.",
      evidenceArtifactIds: ["sync-report"],
    }];
    remediate.decision = "REMEDIATE";
    remediate.remediationPlan = {
      findingIds: ["PVF-AUDIO-SYNC-001"],
      assignmentPaths: ["remediation/audio-sync.json"],
    };
    remediate.rationale = "One evidence-backed synchronization defect requires scoped remediation.";
    result = run(remediate);
    assert(result.status === 0, "release validator derives and accepts a materialized REMEDIATE decision");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }

    const missingDisposition = structuredClone(remediate);
    missingDisposition.findingDispositions = [];
    result = run(missingDisposition);
    assert(result.status === 1, "release validator requires exactly one disposition for every actual finding");

    const readinessPath = join(root, "readiness-report.json");
    const readinessCriteria = [
      "single-clear-outcome",
      "fast-to-value",
      "clean-believable-states",
      "visual-stability",
      "legibility",
      "bounded-feedback-rich-waits",
      "discoverable-primary-action",
      "deterministic-resettable",
      "visible-guardrail",
      "hero-moment-exists",
      "polish-baseline",
    ];
    writeJson(readinessPath, {
      episodeId: "synthetic-product-blocked-episode",
      workflow: "Synthetic approval workflow",
      assessedEnvironment: "local-synthetic",
      assessedRevision: "0123456789abcdef",
      persona: "Synthetic operator",
      permissions: ["synthetic-operator"],
      verdict: "FAIL",
      productExperienceHandoff: {
        assessmentOwner: "product-experience-engineering",
        assessedRevision: "0123456789abcdef",
        assessedEnvironment: "local-synthetic",
        workflow: "Synthetic approval workflow",
        persona: "Synthetic operator",
        permissions: ["synthetic-operator"],
        heroMoment: "A verified approval visibly completes.",
        handoffPath: "synthetic/product-experience-handoff.json",
        afterVerdict: "DEMO-READY",
        handoffDecision: "PROCEED",
        seedProfile: {
          fixture: "synthetic-fixture",
          seedCommand: "synthetic seed",
          resetCommand: "synthetic reset",
        },
        criteria: readinessCriteria.map((id) => ({
          id,
          passed: true,
          evidence: [`synthetic upstream evidence for ${id}`],
        })),
      },
      criteria: readinessCriteria.map((id) => ({
        id,
        passed: id !== "hero-moment-exists",
        ...(id === "hero-moment-exists" ? { classification: "product-fix-required" } : {}),
        evidence: [`synthetic current evidence for ${id}`],
      })),
      productFixes: [{
        id: "PV-READINESS-001",
        principle: "A truthful episode requires a protected hero moment.",
        observedBehavior: "The current product state does not visibly complete the promised outcome.",
        viewerImpact: "The episode would become an unpersuasive feature tour.",
        suggestedFix: "Add a visible, deterministic completion state for the synthetic approval.",
        evidence: ["synthetic current evidence for hero-moment-exists"],
        severity: "blocks-video",
      }],
      feedbackPath: "synthetic/product-readiness-feedback.json",
      shortestPathToReady: "Implement and verify the visible completion state.",
    });
    const earlyProductBlocked = {
      schemaVersion: "1.0.0",
      decisionId: "PVD-SYNTHETIC-RELEASE-003",
      arbiter: {
        contextId: "isolated-blocker-arbiter",
        readOnly: true,
        executionReceipt: executionTrust.signedReceipt({
          role: "arbiter",
          contextId: "isolated-blocker-arbiter",
          candidateId: "NO-CANDIDATE",
          startedAt: "2026-07-29T22:02:00.000Z",
          completedAt: "2026-07-29T22:03:00.000Z",
        }),
      },
      policy: policyReference,
      decision: "PRODUCT_BLOCKED",
      blocker: {
        classification: "product",
        summary: "The product cannot yet support a truthful and compelling episode.",
        evidence: [{
          evidenceType: "readiness",
          artifactPath: "readiness-report.json",
          sha256: sha(readinessPath),
          immutable: true,
        }],
      },
      rationale: "Production stops before candidate creation.",
      decidedAt: "2026-07-29T22:03:00.000Z",
    };
    result = run(earlyProductBlocked);
    assert(result.status === 0, "release validator accepts an evidence-backed early PRODUCT_BLOCKED decision without candidate or reviews");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }

    const invalidReadinessPath = join(root, "invalid-readiness-report.json");
    writeJson(invalidReadinessPath, {
      schemaVersion: "1.0.0",
      immutable: true,
      status: "PRODUCT_BLOCKED",
      reason: "A hand-authored blocker must not pass without the canonical readiness contract.",
    });
    const invalidReadinessDecision = structuredClone(earlyProductBlocked);
    invalidReadinessDecision.blocker.evidence[0].artifactPath = "invalid-readiness-report.json";
    invalidReadinessDecision.blocker.evidence[0].sha256 = sha(invalidReadinessPath);
    result = run(invalidReadinessDecision);
    assert(result.status === 1, "release validator rejects hand-authored PRODUCT_BLOCKED evidence that bypasses readiness validation");

    const missingBlockerEvidence = structuredClone(earlyProductBlocked);
    missingBlockerEvidence.blocker.evidence[0].artifactPath = "missing-readiness.json";
    result = run(missingBlockerEvidence);
    assert(result.status === 1, "release validator rejects blocker evidence that does not exist");

    const failedPreflightPath = join(root, "failed-preflight-report.json");
    const failedPreflight = loadJson(preflightPath);
    failedPreflight.reportId = "PVP-SYNTHETIC-RELEASE-002";
    failedPreflight.checks[0].passed = false;
    failedPreflight.failures = [{
      id: "PVF-PREFLIGHT-001",
      checkId: failedPreflight.checks[0].id,
      subsystem: "infrastructure-assets",
      severity: "blocker",
      expectedBehavior: "The immutable candidate artifact is available.",
      observedBehavior: "The synthetic candidate artifact is unavailable.",
      evidenceArtifactIds: ["synthetic-evidence"],
      concreteFix: "Restore the immutable candidate artifact.",
      validationCommand: "node scripts/preflight.mjs --evidence-package evidence-package.json --out preflight.json",
    }];
    failedPreflight.summary = { total: 16, passed: 15, failed: 1 };
    failedPreflight.status = "FAIL";
    failedPreflight.readyForIndependentReview = false;
    writeJson(failedPreflightPath, failedPreflight);
    const earlyPipelineBlocked = {
      schemaVersion: "1.0.0",
      decisionId: "PVD-SYNTHETIC-RELEASE-005",
      arbiter: {
        contextId: "isolated-pipeline-blocker-arbiter",
        readOnly: true,
        executionReceipt: executionTrust.signedReceipt({
          role: "arbiter",
          contextId: "isolated-pipeline-blocker-arbiter",
          candidateId: "NO-CANDIDATE",
          startedAt: "2026-07-29T22:02:00.000Z",
          completedAt: "2026-07-29T22:03:00.000Z",
        }),
      },
      policy: policyReference,
      decision: "PIPELINE_BLOCKED",
      blocker: {
        classification: "pipeline",
        summary: "The immutable candidate artifact is unavailable.",
        evidence: [{
          evidenceType: "preflight",
          artifactPath: "failed-preflight-report.json",
          sha256: sha(failedPreflightPath),
          immutable: true,
        }],
      },
      rationale: "The pipeline must restore the candidate before independent review.",
      decidedAt: "2026-07-29T22:03:00.000Z",
    };
    result = run(earlyPipelineBlocked);
    assert(result.status === 0, "release validator accepts an evidence-backed early PIPELINE_BLOCKED decision without candidate or reviews");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }

    const malformedReviews = writeReports({ malformedDomain: "technical-frame-integrity" });
    const passWithMalformed = { ...decisionBase, reviewReports: malformedReviews };
    result = run(passWithMalformed);
    assert(result.status === 1, "MALFORMED_INPUT reviewer state cannot pass release");

    const pipelineBlocked = {
      ...passWithMalformed,
      decisionId: "PVD-SYNTHETIC-RELEASE-004",
      decision: "PIPELINE_BLOCKED",
      blocker: {
        classification: "pipeline",
        summary: "A required deterministic technical report is missing.",
        evidence: [{
          evidenceType: "preflight",
          artifactPath: "preflight-report.json",
          sha256: sha(preflightPath),
          immutable: true,
        }],
      },
      rationale: "Malformed reviewer input requires a fresh evidence package and review.",
    };
    result = run(pipelineBlocked);
    assert(result.status === 0, "release validator routes MALFORMED_INPUT reviewer state to PIPELINE_BLOCKED");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function publicationIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-studio-publication-"));
  const script = (name) => join(pluginDir, "scripts", name);
  let executionEnvironment = process.env;
  const run = (name, args, options = {}) => spawnSync(
    process.execPath,
    [script(name), ...args],
    { encoding: "utf8", env: executionEnvironment, ...options },
  );
  const expectCode = (name, args, expected, message, options = {}) => {
    const result = run(name, args, options);
    assert(result.status === expected, message);
    if (result.status !== expected) {
      console.error(result.stdout);
      console.error(result.stderr);
    }
    return result;
  };
  const ref = (path) => ({
    artifactPath: path.replaceAll("\\", "/"),
    sha256: sha(join(root, path)),
    bytes: statSync(join(root, path)).size,
  });

  try {
    const executionTrust = createExecutionTrust(root);
    executionEnvironment = executionTrust.environment;
    const candidateId = "synthetic-publication-candidate-001";
    const passingEvidence = buildPassingEvidence(root, candidateId);
    const {
      candidatePath,
      evidencePath: evidencePackagePath,
    } = passingEvidence;
    const candidateWithBytes = passingEvidence.candidate;
    const candidate = {
      candidateId: candidateWithBytes.candidateId,
      artifactPath: candidateWithBytes.artifactPath,
      sha256: candidateWithBytes.sha256,
      sourceRevision: candidateWithBytes.sourceRevision,
      renderProvenanceId: candidateWithBytes.renderProvenanceId,
    };

    const domainChecks = {
      "story-experience": [
        "hook", "before-state", "outcome", "hero-moment", "wiifm", "emotional-payoff",
        "pacing", "visual-direction", "result-holds", "ending", "story-product-alignment",
      ],
      "screen-accuracy-compliance": [
        "visible-values", "product-behavior", "permissions", "claims", "state-freshness",
        "layouts", "annotations", "branding", "privacy", "disclosures", "content-freshness",
      ],
      "audio-captions-synchronization": [
        "narration-accuracy", "pronunciation", "pacing", "loudness", "clipping",
        "music-balance", "action-synchronization", "pauses", "result-holds",
        "caption-accuracy", "caption-timing", "reading-speed", "caption-layout", "accessibility",
      ],
      "technical-frame-integrity": [
        "codecs", "resolution", "aspect-ratio", "frame-rate", "color", "audio-streams",
        "fast-start", "checksums", "frame-integrity", "browser-playback", "assets",
        "deterministic-rendering", "naming", "platform-compatibility", "provenance",
      ],
    };
    const domainMeta = {
      "story-experience": { file: "story-review.json", id: "STORY", score: 90 },
      "screen-accuracy-compliance": { file: "screen-review.json", id: "SCREEN", score: 100 },
      "audio-captions-synchronization": { file: "audio-review.json", id: "AUDIO", score: 96 },
      "technical-frame-integrity": { file: "technical-review.json", id: "TECHNICAL", score: 100 },
    };
    const reports = new Map();
    let contextSequence = 1;
    for (const [domain, checks] of Object.entries(domainChecks)) {
      const meta = domainMeta[domain];
      const report = {
        schemaVersion: "1.0.0",
        reportId: `PVR-PUBLICATION-${meta.id}-001`,
        status: "COMPLETE",
        candidate,
        reviewer: {
          domain,
          contextId: `isolated-${domain}-context-${contextSequence++}`,
          readOnly: true,
          executionReceipt: executionTrust.signedReceipt({
            role: "reviewer",
            domain,
            contextId: `isolated-${domain}-context-${contextSequence - 1}`,
            candidateId,
            startedAt: "2026-07-29T15:00:00.000Z",
            completedAt: "2026-07-29T15:05:00.000Z",
          }),
          startedAt: "2026-07-29T15:00:00.000Z",
          completedAt: "2026-07-29T15:05:00.000Z",
        },
        evidencePackage: {
          artifactPath: "evidence-package.json",
          sha256: sha(evidencePackagePath),
        },
        score: meta.score,
        checks: checks.map((id) => ({ id, passed: true, evidenceArtifactIds: ["synthetic-proof"] })),
        domainPass: true,
        findings: [],
        summary: `Synthetic ${domain} review passed.`,
      };
      const path = join(root, meta.file);
      writeJson(path, report);
      reports.set(domain, { path, file: meta.file, report });
      expectCode(
        "validate-review-report.mjs",
        [path],
        0,
        `semantic review validator accepts ${domain} publication fixture`,
      );
    }

    const storyReport = reports.get("story-experience").report;
    const invalidReviewPath = join(root, "review-invalid-execution-receipt.json");
    const runInvalidReview = (report, message) => {
      writeJson(invalidReviewPath, report);
      expectCode("validate-review-report.mjs", [invalidReviewPath], 1, message);
    };
    const receiptReferenceTamper = structuredClone(storyReport);
    receiptReferenceTamper.reviewer.executionReceipt.receipt.sha256 = "0".repeat(64);
    runInvalidReview(
      receiptReferenceTamper,
      "review validator rejects execution-receipt reference checksum tampering",
    );
    const signatureReferenceTamper = structuredClone(storyReport);
    signatureReferenceTamper.reviewer.executionReceipt.signature.bytes = 63;
    runInvalidReview(
      signatureReferenceTamper,
      "review validator rejects execution-signature reference byte-count tampering",
    );
    const wrongContext = structuredClone(storyReport);
    wrongContext.reviewer.contextId = "different-review-context";
    runInvalidReview(wrongContext, "review validator rejects a signed receipt for a different context");
    const wrongCandidate = structuredClone(storyReport);
    wrongCandidate.candidate.candidateId = "different-candidate";
    runInvalidReview(wrongCandidate, "review validator rejects a signed receipt for a different candidate");
    const wrongDomain = structuredClone(storyReport);
    wrongDomain.reviewer.executionReceipt = executionTrust.signedReceipt({
      role: "reviewer",
      domain: "screen-accuracy-compliance",
      contextId: storyReport.reviewer.contextId,
      candidateId,
      startedAt: "2026-07-29T15:00:00.000Z",
      completedAt: "2026-07-29T15:05:00.000Z",
    });
    runInvalidReview(wrongDomain, "review validator rejects a signed receipt for a different review domain");
    const wrongRole = structuredClone(storyReport);
    wrongRole.reviewer.executionReceipt = executionTrust.signedReceipt({
      role: "arbiter",
      contextId: storyReport.reviewer.contextId,
      candidateId,
      startedAt: "2026-07-29T15:00:00.000Z",
      completedAt: "2026-07-29T15:05:00.000Z",
    });
    runInvalidReview(wrongRole, "review validator rejects a signed receipt for a different execution role");

    const decision = loadJson(join(fixtureDir, "release-decision.pass.json"));
    const policyPath = join(pluginDir, "policy", "product-video-policy.json");
    decision.candidate = candidateWithBytes;
    decision.arbiter.contextId = "isolated-publication-arbiter-context";
    decision.arbiter.executionReceipt = executionTrust.signedReceipt({
      role: "arbiter",
      contextId: "isolated-publication-arbiter-context",
      candidateId,
      startedAt: "2026-07-29T15:05:00.000Z",
      completedAt: "2026-07-29T15:10:00.000Z",
    });
    decision.policy = {
      artifactPath: policyPath,
      sha256: sha(policyPath),
      policyVersion: "1.0.0",
    };
    decision.preflight = {
      artifactPath: "preflight-report.json",
      sha256: sha(join(root, "preflight-report.json")),
    };
    decision.reviewReports = Object.entries(domainMeta).map(([domain, meta]) => ({
      domain,
      reportPath: meta.file,
      sha256: sha(reports.get(domain).path),
      status: "COMPLETE",
      score: meta.score,
      passed: true,
      findingCount: 0,
      blockerFindings: 0,
      criticalFindings: 0,
    }));
    decision.decidedAt = "2026-07-29T15:10:00.000Z";
    const decisionPath = join(root, "release-decision.json");
    writeJson(decisionPath, decision);
    expectCode(
      "validate-release-decision.mjs",
      [decisionPath],
      0,
      "semantic release validator accepts publication fixture",
    );

    const finalVerification = {
      schemaVersion: "1.0.0",
      verificationId: "PVV-PUBLICATION-001",
      candidate: candidateWithBytes,
      verifier: {
        contextId: "isolated-publication-final-verifier-context",
        readOnly: true,
        independent: true,
        executionReceipt: executionTrust.signedReceipt({
          role: "final-verifier",
          contextId: "isolated-publication-final-verifier-context",
          candidateId,
          startedAt: "2026-07-29T15:10:00.000Z",
          completedAt: "2026-07-29T15:15:00.000Z",
          issuedAt: "2026-07-29T15:15:00.000Z",
        }),
      },
      preflight: ref("preflight-report.json"),
      reviewReports: Object.entries(domainMeta).map(([domain, meta]) => ({
        domain,
        ...ref(meta.file),
      })),
      arbiterDecision: ref("release-decision.json"),
      checks: {
        candidateIdentity: true,
        preflightIdentity: true,
        reviewIdentityAndIndependence: true,
        arbiterIdentity: true,
        rerunPolicy: true,
        thresholdsAndFindings: true,
        checksumsAndProvenance: true,
        playbackAndReproduction: true,
        deliveryContents: true,
      },
      status: "PASS",
      limitations: [],
      verifiedAt: "2026-07-29T15:15:00.000Z",
    };
    const finalPath = join(root, "final-verification.json");
    writeJson(finalPath, finalVerification);
    expectCode(
      "validate-final-verification.mjs",
      [finalPath],
      0,
      "final verifier accepts exact candidate, preflight, four reviews, and PASS arbiter bytes",
    );

    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const publicKeyPath = join(root, "trusted-publication-approver.pem");
    writeFileSync(
      publicKeyPath,
      publicKey.export({ type: "spki", format: "pem" }),
      "utf8",
    );
    const publicKeyFingerprint = shaBytes(publicKey.export({ type: "spki", format: "der" }));
    const approvalReceiptPath = join(root, "signed-publication-approval.json");
    const approvalSignaturePath = join(root, "signed-publication-approval.ed25519");
    const approvalReceipt = {
      schemaVersion: "1.0.0",
      receiptId: "PVA-PUBLICATION-001",
      signatureAlgorithm: "Ed25519",
      approverPublicKeySha256: publicKeyFingerprint,
      candidateId,
      candidateSha256: candidate.sha256,
      candidateBytes: statSync(candidatePath).size,
      arbiterDecisionSha256: sha(decisionPath),
      finalVerificationSha256: sha(finalPath),
      reviewerIdentity: "Synthetic Human Approver",
      reviewedAt: "2026-07-29T15:20:00.000Z",
      classification: "approved",
      watchThroughStatus: "completed",
      syntheticDataConfirmed: true,
      redactionNotes: "Synthetic fixture contains no personal or customer data.",
    };
    writeJson(approvalReceiptPath, approvalReceipt);
    writeFileSync(
      approvalSignaturePath,
      sign(null, readFileSync(approvalReceiptPath), privateKey),
    );
    const releaseEvidence = {
      schemaVersion: "2.0.0",
      candidateId,
      assetPath: "candidate.mp4",
      sha256: candidate.sha256,
      bytes: statSync(candidatePath).size,
      arbiterDecision: ref("release-decision.json"),
      finalVerification: ref("final-verification.json"),
      approvalReceipt: ref("signed-publication-approval.json"),
      approvalSignature: ref("signed-publication-approval.ed25519"),
    };
    const releasePath = join(root, "release-evidence.json");
    writeJson(releasePath, releaseEvidence);
    const publicationEnvironment = {
      ...executionEnvironment,
      AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY: publicKeyPath,
    };
    const unsignedEnvironment = { ...executionEnvironment };
    delete unsignedEnvironment.AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY;
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      1,
      "publication gate fails closed when no trusted approver public key is configured",
      { env: unsignedEnvironment },
    );
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      0,
      "publication gate accepts a trusted detached signature bound to the exact PASS chain",
      { env: publicationEnvironment },
    );
    const { publicKey: unrelatedPublicKey } = generateKeyPairSync("ed25519");
    const unrelatedPublicKeyPath = join(root, "unrelated-publication-approver.pem");
    writeFileSync(
      unrelatedPublicKeyPath,
      unrelatedPublicKey.export({ type: "spki", format: "pem" }),
      "utf8",
    );
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      1,
      "publication gate rejects a signature when a different trusted approver key is configured",
      {
        env: {
          ...executionEnvironment,
          AGENTHUB_PUBLICATION_APPROVER_PUBLIC_KEY: unrelatedPublicKeyPath,
        },
      },
    );
    const staleReceiptPath = join(root, "stale-publication-approval.json");
    writeJson(staleReceiptPath, {
      ...approvalReceipt,
      redactionNotes: "The receipt bytes changed after signing.",
    });
    const staleSignatureRelease = structuredClone(releaseEvidence);
    staleSignatureRelease.approvalReceipt = ref("stale-publication-approval.json");
    const staleSignatureReleasePath = join(root, "release-evidence-stale-signature.json");
    writeJson(staleSignatureReleasePath, staleSignatureRelease);
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", staleSignatureReleasePath],
      1,
      "publication gate rejects a stale signature after approval-receipt byte changes",
      { env: publicationEnvironment },
    );
    expectCode(
      "check-evidence-gate.mjs",
      [
        "--asset", candidatePath,
        "--classification", "approved",
        "--reviewed-by", "Jane Example",
        "--synthetic-data-confirmed",
      ],
      1,
      "publication gate rejects the former inline approval fast path",
      { env: publicationEnvironment },
    );

    const packagePath = join(root, "publication-bundle.json");
    const packageResult = spawnSync(process.execPath, [
      script("video-cli.mjs"),
      "package",
      "--repo", pluginDir,
      "--out", packagePath,
      "--decision", decisionPath,
      "--final-verification", finalPath,
      "--release-evidence", releasePath,
      candidatePath,
    ], { encoding: "utf8", env: publicationEnvironment });
    assert(packageResult.status === 0, "video-cli package accepts only a validated, signed PASS publication chain");
    if (packageResult.status !== 0) {
      console.error(packageResult.stdout);
      console.error(packageResult.stderr);
    } else {
      const bundle = loadJson(packagePath);
      assert(
        bundle.schemaVersion === "1.0.0" &&
          bundle.candidateId === candidateId &&
          bundle.files.length === 1 &&
          bundle.files[0].sha256 === sha(candidatePath),
        "video-cli package binds exact approved candidate bytes and gate files",
      );
    }

    const reviewPath = reports.get("story-experience").path;
    const originalReview = readFileSync(reviewPath);
    writeFileSync(reviewPath, Buffer.concat([originalReview, Buffer.from("\n")]));
    expectCode(
      "validate-final-verification.mjs",
      [finalPath],
      1,
      "final verifier rejects review-report byte tampering",
    );
    writeFileSync(reviewPath, originalReview);

    const preflightPath = join(root, "preflight-report.json");
    const originalPreflight = readFileSync(preflightPath);
    writeFileSync(preflightPath, Buffer.concat([originalPreflight, Buffer.from("\n")]));
    expectCode(
      "validate-final-verification.mjs",
      [finalPath],
      1,
      "final verifier rejects preflight-report byte tampering",
    );
    writeFileSync(preflightPath, originalPreflight);

    const missingFinal = structuredClone(finalVerification);
    missingFinal.preflight.artifactPath = "does-not-exist-preflight.json";
    const missingFinalPath = join(root, "final-verification-missing-reference.json");
    writeJson(missingFinalPath, missingFinal);
    expectCode(
      "validate-final-verification.mjs",
      [missingFinalPath],
      1,
      "final verifier rejects a nonexistent preflight reference",
    );

    const originalCandidate = readFileSync(candidatePath);
    writeFileSync(candidatePath, "tampered-product-video\n", "utf8");
    expectCode(
      "validate-final-verification.mjs",
      [finalPath],
      1,
      "final verifier rejects candidate byte tampering",
    );
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      1,
      "publication gate rejects candidate byte tampering",
      { env: publicationEnvironment },
    );
    writeFileSync(candidatePath, originalCandidate);

    const originalDecision = readFileSync(decisionPath);
    writeFileSync(decisionPath, Buffer.concat([originalDecision, Buffer.from("\n")]));
    expectCode(
      "validate-final-verification.mjs",
      [finalPath],
      1,
      "final verifier rejects arbiter-decision byte tampering",
    );
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      1,
      "publication gate rejects arbiter-decision byte tampering",
      { env: publicationEnvironment },
    );
    writeFileSync(decisionPath, originalDecision);

    const originalFinal = readFileSync(finalPath);
    writeFileSync(finalPath, Buffer.concat([originalFinal, Buffer.from("\n")]));
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      1,
      "publication gate rejects final-verification byte tampering",
      { env: publicationEnvironment },
    );
    writeFileSync(finalPath, originalFinal);

    const missingRelease = structuredClone(releaseEvidence);
    missingRelease.finalVerification.artifactPath = "does-not-exist-final-verification.json";
    const missingReleasePath = join(root, "release-evidence-missing-reference.json");
    writeJson(missingReleasePath, missingRelease);
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", missingReleasePath],
      1,
      "publication gate rejects a nonexistent final-verification reference",
      { env: publicationEnvironment },
    );

    const originalReceipt = readFileSync(approvalReceiptPath);
    const placeholderReceipt = structuredClone(approvalReceipt);
    placeholderReceipt.reviewerIdentity = "reviewer";
    writeJson(approvalReceiptPath, placeholderReceipt);
    writeFileSync(
      approvalSignaturePath,
      sign(null, readFileSync(approvalReceiptPath), privateKey),
    );
    const nonHumanRelease = structuredClone(releaseEvidence);
    nonHumanRelease.approvalReceipt = ref("signed-publication-approval.json");
    nonHumanRelease.approvalSignature = ref("signed-publication-approval.ed25519");
    const nonHumanReleasePath = join(root, "release-evidence-placeholder-human.json");
    writeJson(nonHumanReleasePath, nonHumanRelease);
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", nonHumanReleasePath],
      1,
      "publication gate rejects a correctly signed placeholder approver identity",
      { env: publicationEnvironment },
    );
    writeFileSync(approvalReceiptPath, originalReceipt);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

for (const schemaName of [
  "execution-receipt.schema.json",
  "execution-host-trust.schema.json",
  "video-finding.schema.json",
  "review-report.schema.json",
  "release-decision.schema.json",
  "final-verification.schema.json",
  "release-evidence.schema.json",
  "remediation-assignment.schema.json",
  "delivery-spec.schema.json",
  "deterministic-report.schema.json",
  "evidence-package.schema.json",
  "preflight-report.schema.json",
]) {
  const schema = loadSchema(join(schemaDir, schemaName));
  assert(schema.$schema === "https://json-schema.org/draft/2020-12/schema", `${schemaName} declares JSON Schema 2020-12`);
  assert(schema.additionalProperties === false, `${schemaName} fails closed on unknown root properties`);
}

schemaFixture("review-report.schema.json", "review-report.pass.json", true);
schemaFixture("review-report.schema.json", "review-report.finding.json", true);
schemaFixture("review-report.schema.json", "review-report.malformed-input.json", true);
schemaFixture("review-report.schema.json", "review-report.invalid.json", false);
schemaFixture("release-decision.schema.json", "release-decision.pass.json", true);
schemaFixture("release-decision.schema.json", "release-decision.remediate.json", true);
schemaFixture("release-decision.schema.json", "release-decision.invalid.json", false);
schemaFixture("final-verification.schema.json", "final-verification.pass.json", true);
schemaFixture("final-verification.schema.json", "final-verification.invalid.json", false);
schemaFixture("release-evidence.schema.json", "release-evidence.pass.json", true);
schemaFixture("release-evidence.schema.json", "release-evidence.invalid.json", false);
schemaFixture("remediation-assignment.schema.json", "remediation-assignment.pass.json", true);
schemaFixture("remediation-assignment.schema.json", "remediation-assignment.invalid.json", false);
schemaFixture("delivery-spec.schema.json", "delivery-spec.pass.json", true);
schemaFixture("delivery-spec.schema.json", "delivery-spec.invalid.json", false);
schemaFixture("deterministic-report.schema.json", "deterministic-report.pass.json", true);
schemaFixture("deterministic-report.schema.json", "deterministic-report.invalid.json", false);
schemaFixture("evidence-package.schema.json", "evidence-package.pass.json", true);
schemaFixture("evidence-package.schema.json", "evidence-package.invalid.json", false);
schemaFixture("preflight-report.schema.json", "preflight-report.pass.json", true);
schemaFixture("preflight-report.schema.json", "preflight-report.invalid.json", false);
schemaFixture("interactive-deep-dive.schema.json", "interactive-deep-dive.pass.json", true);
schemaFixture("interactive-deep-dive.schema.json", "interactive-deep-dive.invalid.json", false);

cli("validate-review-report.mjs", "review-report.invalid.json", 1);
cli("validate-release-decision.mjs", "release-decision.invalid.json", 1);
cli("validate-final-verification.mjs", "final-verification.invalid.json", 1);
cli("validate-remediation-assignment.mjs", "remediation-assignment.pass.json", 0);
cli("validate-remediation-assignment.mjs", "remediation-assignment.invalid.json", 1);
cli("validate-interactive-deep-dive.mjs", "interactive-deep-dive.pass.json", 0);
cli("validate-interactive-deep-dive.mjs", "interactive-deep-dive.invalid.json", 1);
screencastChoreographyIntegration();
executionReceiptIntegration();
preflightIntegration();
realMediaIntegration();
videoCliGateIntegration();
releaseDecisionIntegration();
publicationIntegration();
reviewDeliveryIntegration();

console.log(`\n${assertions} assertion(s): ${failures} failure(s).`);
process.exit(failures === 0 ? 0 : 1);
