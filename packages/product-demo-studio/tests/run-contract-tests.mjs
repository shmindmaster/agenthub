#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const testDir = dirname(fileURLToPath(import.meta.url));
const pluginDir = resolve(testDir, "..");
const schemaDir = join(pluginDir, "schemas");
const fixtureDir = join(testDir, "fixtures");
const schemaCache = new Map();
const STATE_CHANGING_INTERACTION_KINDS = new Set([
  "click", "double-click", "type", "scroll", "drag", "select", "keyboard",
]);
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
  if ((errors.length === 0) !== expectedValid) console.error(errors.join("\n"));
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

function externalWorkspaceIsolationIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-workspace-isolation-"));
  const repo = join(root, "product-repo");
  const workspace = join(root, "external-workspace");
  mkdirSync(repo, { recursive: true });
  try {
    let result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "scaffold-video-workspace.mjs"),
      "--repo", repo,
      "--product", "Fixture Product",
      "--workspace", join(repo, "studio"),
    ], { encoding: "utf8" });
    assert(result.status === 2, "video scaffold refuses a workspace inside the product repo");
    assert(!existsSync(join(repo, "studio")), "rejected scaffold leaves the product repo untouched");

    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "scaffold-video-workspace.mjs"),
      "--repo", repo,
      "--product", "Fixture Product",
      "--workspace", workspace,
    ], { encoding: "utf8" });
    assert(result.status === 0, "video scaffold creates an external workspace");
    assert(existsSync(join(workspace, "package.json")), "external workspace contains the lean Playwright capture package");
    assert(existsSync(join(workspace, "render.mjs")), "external workspace contains the thin finishing adapter");
    assert(!existsSync(join(repo, "apps")), "external scaffold creates no apps/videos folder in the product repo");
    assert(!existsSync(join(repo, "FixtureProduct_Video_Program")), "external scaffold creates no video-program folder in the product repo");
  } finally {
    rmSync(root, { recursive: true, force: true });
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

    const storyboardRejects = (name, mutate, message) => {
      const candidate = structuredClone(storyboard);
      mutate(candidate);
      const path = join(root, `storyboard.${name}.json`);
      writeJson(path, candidate);
      const validation = spawnSync(process.execPath, [
        join(pluginDir, "scripts", "validate-storyboard.mjs"), path,
      ], { encoding: "utf8" });
      assert(validation.status !== 0, message);
    };
    storyboardRejects("missing-interaction", (value) => delete value.segments[0].interaction,
      "storyboard validator rejects a missing interaction contract");
    storyboardRejects("missing-framing", (value) => delete value.segments[1].framing,
      "storyboard validator rejects a missing framing contract");
    storyboardRejects("real-time-text", (value) => {
      value.segments[2].pacing = {
        activity: "text-entry", treatment: "real-time", multiplier: 1, truthTreatment: "Raw typing",
      };
    }, "storyboard validator rejects real-time text entry");
    storyboardRejects("none-feedback", (value) => {
      value.segments[0].interaction.kind = "none";
      value.segments[0].interaction.target = "none";
      value.segments[0].interaction.clickCue = "none";
      value.segments[0].interaction.craft.feedbackType = "radial-pulse";
    }, "storyboard validator rejects feedback on a non-interactive hold");
    storyboardRejects("invalid-recompose", (value) => {
      value.segments[2].framing.zoom = {
        mode: "recompose", transitionMs: -1, changesInBeat: 1,
        holdThroughAction: false, pullBack: true, drift: false,
      };
    }, "storyboard validator rejects contradictory recompose zoom values");

    const capture = {
      scenario: "approval-exception",
      beat: "reveal",
      storyboardSegmentId: "reveal",
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
        deliveryFrame: { width: 1920, height: 1080 },
        deliveredCrop: { x: 760, y: 180, width: 1050, height: 591 },
        sourceFrame: { width: 3840, height: 2160 },
        smallDelivery: true,
        browserZoomPercent: 100,
      },
      interaction: {
        kind: "click",
        target: "exception-filter",
        cursor: {
          from: [1450, 780],
          to: [1520, 430],
          park: [1760, 930],
          durationMs: 500,
          easing: "eased-deceleration",
          scale: 1.75,
          settleBeforeActionMs: 250,
          holdAfterActionMs: 500,
        },
        cue: "visual",
        feedback: {
          type: "radial-pulse",
          durationMs: 350,
          brandColor: "#4F46E5",
          opacity: 0.35,
        },
        keystrokeOverlay: false,
        pacing: {
          activity: "meaningful-action",
          treatment: "real-time",
          multiplier: 1,
          truthTreatment: "The product interaction remains real-time.",
        },
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

    const hoverCapture = JSON.parse(JSON.stringify(capture));
    hoverCapture.beat = "hover-native-state";
    hoverCapture.interaction.kind = "hover";
    hoverCapture.interaction.cue = "none";
    hoverCapture.interaction.feedback = { type: "native-hover", durationMs: 0 };
    const hoverCapturePath = join(root, "capture.hover.json");
    writeFileSync(hoverCapturePath, `${JSON.stringify(hoverCapture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      hoverCapturePath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "capture validator accepts native hover feedback without an overlay");

    hoverCapture.interaction.feedback = { type: "radial-pulse", durationMs: 350 };
    const invalidHoverCapturePath = join(root, "capture.hover.invalid.json");
    writeFileSync(invalidHoverCapturePath, `${JSON.stringify(hoverCapture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      invalidHoverCapturePath,
    ], { encoding: "utf8" });
    assert(result.status !== 0, "capture validator rejects overlay feedback on hover");

    const keyboardCapture = JSON.parse(JSON.stringify(capture));
    keyboardCapture.beat = "shortcut-driven-state";
    keyboardCapture.interaction.kind = "keyboard";
    keyboardCapture.interaction.cue = "none";
    keyboardCapture.interaction.cursor = { park: [1760, 930] };
    keyboardCapture.interaction.feedback = { type: "keystroke-overlay", durationMs: 700 };
    keyboardCapture.interaction.keystrokeOverlay = true;
    const keyboardCapturePath = join(root, "capture.keyboard.json");
    writeFileSync(keyboardCapturePath, `${JSON.stringify(keyboardCapture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      keyboardCapturePath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "capture validator accepts a shortcut with a keystroke overlay");

    keyboardCapture.interaction.keystrokeOverlay = false;
    const invalidKeyboardCapturePath = join(root, "capture.keyboard.invalid.json");
    writeFileSync(invalidKeyboardCapturePath, `${JSON.stringify(keyboardCapture, null, 2)}\n`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"),
      invalidKeyboardCapturePath,
    ], { encoding: "utf8" });
    assert(result.status !== 0, "capture validator rejects a shortcut without a keystroke overlay");

    const captureRejects = (name, mutate, message) => {
      const candidate = structuredClone(capture);
      mutate(candidate);
      const path = join(root, `capture.${name}.json`);
      writeJson(path, candidate);
      const validation = spawnSync(process.execPath, [
        join(pluginDir, "scripts", "validate-capture-manifest.mjs"), path,
      ], { encoding: "utf8" });
      assert(validation.status !== 0, message);
    };
    captureRejects("coverage", (value) => value.captureSurface.plannedActiveRegionCoverage = 0.3,
      "capture validator rejects wasted screen space");
    captureRejects("pixel-density", (value) => value.captureSurface.deliveredCrop.width = 400,
      "capture validator derives and rejects insufficient effective delivery pixel density");
    captureRejects("browser-zoom", (value) => value.captureSurface.browserZoomPercent = 90,
      "capture validator rejects unsupported browser zoom values");
    captureRejects("click-cue", (value) => value.interaction.cue = "none",
      "capture validator rejects a missing click cue");
    captureRejects("feedback-duration", (value) => value.interaction.feedback.durationMs = 700,
      "capture validator rejects an invalid click-feedback duration");
    captureRejects("cursor-duration", (value) => value.interaction.cursor.durationMs = 900,
      "capture validator rejects an invalid pointer movement duration");
    captureRejects("bounded-wait", (value) => value.interaction.pacing = {
      activity: "bounded-wait", treatment: "speed-ramp", multiplier: 2, truthTreatment: "Accelerated wait",
    }, "capture validator rejects weak wait acceleration");
    captureRejects("premature-narration", (value) => value.interaction.narrationSync.spokenResultAtSeconds = 1.2,
      "capture validator rejects narration before the visible result");

    const desktopCapture = structuredClone(capture);
    desktopCapture.beat = "desktop-delivery";
    desktopCapture.captureSurface.smallDelivery = false;
    desktopCapture.interaction.cursor.scale = 1;
    const desktopCapturePath = join(root, "capture.desktop.json");
    writeJson(desktopCapturePath, desktopCapture);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-capture-manifest.mjs"), desktopCapturePath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "capture validator permits a native-size cursor for desktop delivery");

    const craftCaptures = storyboard.segments.map((segment) => {
      const value = structuredClone(capture);
      value.beat = segment.id;
      value.storyboardSegmentId = segment.id;
      value.captureSurface.irrelevantNavigation = segment.framing.irrelevantNavigation;
      value.captureSurface.plannedTreatment = segment.framing.deliveryTreatment;
      value.captureSurface.smallDelivery = segment.framing.smallDelivery;
      value.interaction.kind = segment.interaction.kind;
      value.interaction.target = segment.interaction.target;
      value.interaction.cue = segment.interaction.clickCue === "none" ? "none" : "visual";
      value.interaction.cursor = {
        from: [1450, 780],
        to: [1520, 430],
        park: [1760, 930],
        durationMs: segment.interaction.craft.cursorMoveMs,
        easing: segment.interaction.craft.cursorMotion,
        scale: segment.interaction.craft.cursorScale,
        settleBeforeActionMs: segment.interaction.craft.settleBeforeActionMs,
        holdAfterActionMs: segment.interaction.craft.holdAfterActionMs,
      };
      value.interaction.feedback = {
        type: segment.interaction.craft.feedbackType,
        durationMs: segment.interaction.craft.feedbackDurationMs,
        ...(segment.interaction.craft.feedbackColor ? { brandColor: segment.interaction.craft.feedbackColor } : {}),
        ...(segment.interaction.craft.feedbackOpacity !== undefined ? { opacity: segment.interaction.craft.feedbackOpacity } : {}),
      };
      value.interaction.keystrokeOverlay = segment.interaction.craft.keystrokeOverlay;
      value.interaction.pacing = segment.pacing;
      value.interaction.narrationSync = segment.interaction.narrationSync;
      return value;
    });
    const craftCapturePath = join(root, "captures.json");
    writeJson(craftCapturePath, craftCaptures);
    const captureEvidencePath = join(root, "capture-evidence.json");
    writeJson(captureEvidencePath, {
      candidateId: "synthetic-guided-screencast",
      sourceFrame: { width: 3840, height: 2160 },
      beats: storyboard.segments.map((segment) => ({
        episodeId: storyboard.episodeId,
        storyboardSegmentId: segment.id,
        ...segment.interaction.narrationSync,
        cutAtSeconds: segment.interaction.narrationSync.resultVisibleAtSeconds + 1.4,
      })),
    });
    const rawCapturePath = join(root, "raw-capture.png");
    result = spawnSync("ffmpeg", [
      "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=3840x2160",
      "-frames:v", "1", "-y", rawCapturePath,
    ], { encoding: "utf8" });
    if (result.status !== 0) throw new Error(`could not create raw capture fixture: ${result.stderr}`);
    const mediaPath = join(root, "candidate.mp4");
    generateRealCandidate(mediaPath);
    const renderTimingPath = join(root, "render-timing.json");
    writeJson(renderTimingPath, bindRenderTimingFrameHashes(
      buildRenderTimingDocument("synthetic-guided-screencast", storyboard),
      mediaPath,
    ));
    const craftReportPath = join(root, "craft-contract-validation.json");
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", renderTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", mediaPath,
      "--media-artifact-id", "media",
      "--out", craftReportPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "craft-contract reporter accepts and binds valid storyboard/capture inputs");
    if (result.status !== 0) console.error(result.stderr || result.stdout);
    const craftReport = loadJson(craftReportPath);
    const deterministicSchemaPath = join(schemaDir, "deterministic-report.schema.json");
    const deterministicSchema = loadSchema(deterministicSchemaPath);
    const craftErrors = [];
    validate(deterministicSchema, craftReport, "$", deterministicSchemaPath, deterministicSchema, craftErrors);
    assert(craftErrors.length === 0, "craft-contract report conforms to deterministic-report.schema.json");
    assert(craftReport.measurements.length === storyboard.segments.length && craftReport.measurements[0].resultHoldToCutSeconds > 1,
      "craft-contract report emits evidence-bound per-beat result-hold timing");
    assert(craftReport.sourceGeometry.width === 3840 && craftReport.sourceGeometry.height === 2160,
      "craft-contract report probes and binds raw capture geometry");
    assert(craftReport.renderMeasurements.length === storyboard.segments.length && craftReport.mediaProbe.durationSeconds === 23,
      "craft-contract report binds the rendered timeline to the exact final media bytes");
    const renderMeasurementByBeat = new Map(
      craftReport.renderMeasurements.map((measurement) => [measurement.beatId, measurement]),
    );
    assert(renderMeasurementByBeat.get("approval-exception.before")?.stateChangeRequired === false,
      "craft-contract reporter does not demand a causal state change for pointer movement");
    assert(renderMeasurementByBeat.get("approval-exception.reveal")?.stateChangeRequired === true,
      "craft-contract reporter requires a causal state change for a meaningful click");

    const partialCapturePath = join(root, "captures.partial.json");
    writeJson(partialCapturePath, craftCaptures.slice(1));
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", partialCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", renderTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", mediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.partial.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "craft-contract reporter rejects partial storyboard capture coverage");

    const mismatchedEvidence = loadJson(captureEvidencePath);
    mismatchedEvidence.beats[0].actionAtSeconds = 1.2;
    const mismatchedEvidencePath = join(root, "capture-evidence.mismatched.json");
    writeJson(mismatchedEvidencePath, mismatchedEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", mismatchedEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", renderTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", mediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.mismatched.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "craft-contract reporter rejects timing drift across storyboard, manifest, and capture evidence");

    const compressedRenderTiming = bindRenderTimingFrameHashes(
      buildRenderTimingDocument("synthetic-guided-screencast", storyboard),
      mediaPath,
    );
    compressedRenderTiming.beats[1].startsAtSeconds = 5;
    const compressedRenderTimingPath = join(root, "render-timing.compressed.json");
    writeJson(compressedRenderTimingPath, compressedRenderTiming);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", compressedRenderTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", mediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.compressed.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "craft-contract reporter rejects a final render timeline compressed away from its storyboard");

    const unstableEndCard = bindRenderTimingFrameHashes(
      buildRenderTimingDocument("synthetic-guided-screencast", storyboard),
      mediaPath,
    );
    unstableEndCard.beats.at(-1).stableFromSeconds = 20.5;
    const unstableEndCardPath = join(root, "render-timing.unstable-end-card.json");
    writeJson(unstableEndCardPath, unstableEndCard);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", unstableEndCardPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", mediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.unstable-end-card.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "craft-contract reporter rejects an end card with less than three seconds of stable hold");

    const alteredMediaPath = join(root, "candidate-altered.mp4");
    result = spawnSync("ffmpeg", [
      "-v", "error",
      "-f", "lavfi", "-i", "color=c=black:size=320x180:rate=30",
      "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000",
      "-t", "23",
      "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-c:a", "aac", "-ac", "2", "-ar", "48000",
      "-movflags", "+faststart", "-y", alteredMediaPath,
    ], { encoding: "utf8" });
    if (result.status !== 0) throw new Error(`could not create altered media fixture: ${result.stderr}`);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", renderTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", alteredMediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.altered-media.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1, "craft-contract reporter rejects altered encoded media when nominal timing JSON is unchanged");

    const freshlyBoundStaticTimingPath = join(root, "render-timing.static-fresh-hashes.json");
    writeJson(freshlyBoundStaticTimingPath, bindRenderTimingFrameHashes(
      buildRenderTimingDocument("synthetic-guided-screencast", storyboard),
      alteredMediaPath,
    ));
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", freshlyBoundStaticTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", alteredMediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.static-fresh-hashes.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1 && (result.stderr || result.stdout).includes("meaningful visible state change"),
      "craft-contract reporter rejects a static render even when its frame hashes are freshly rebound");

    const briefMotionMediaPath = join(root, "candidate-brief-end-card-motion.mp4");
    result = spawnSync("ffmpeg", [
      "-v", "error",
      "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=30:duration=20",
      "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000",
      "-t", "23",
      "-vf", "tpad=stop_mode=clone:stop_duration=3,drawbox=x=12:y=12:w=36:h=36:color=white:t=fill:enable='between(t,21.10,21.24)'",
      "-c:v", "libx264", "-pix_fmt", "yuv420p",
      "-c:a", "aac", "-ac", "2", "-ar", "48000",
      "-movflags", "+faststart", "-y", briefMotionMediaPath,
    ], { encoding: "utf8" });
    if (result.status !== 0) throw new Error(`could not create brief end-card motion fixture: ${result.stderr}`);
    const briefMotionTimingPath = join(root, "render-timing.brief-end-card-motion.json");
    writeJson(briefMotionTimingPath, bindRenderTimingFrameHashes(
      buildRenderTimingDocument("synthetic-guided-screencast", storyboard),
      briefMotionMediaPath,
    ));
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
      "--candidate-id", "synthetic-guided-screencast",
      "--storyboard", storyboardPath,
      "--storyboard-artifact-id", "storyboard",
      "--capture-manifest", craftCapturePath,
      "--capture-artifact-id", "capture-manifest",
      "--capture-evidence", captureEvidencePath,
      "--capture-evidence-artifact-id", "capture-evidence",
      "--raw-capture", rawCapturePath,
      "--raw-capture-artifact-id", "raw-capture",
      "--render-timing", briefMotionTimingPath,
      "--render-timing-artifact-id", "render-timing",
      "--media", briefMotionMediaPath,
      "--media-artifact-id", "media",
      "--out", join(root, "craft-contract-validation.brief-end-card-motion.json"),
    ], { encoding: "utf8" });
    assert(result.status === 1 && (result.stderr || result.stdout).includes("final end card changes"),
      "craft-contract reporter inspects every rendered hold frame and rejects brief localized end-card motion");
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

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function createExecutionRecords(root) {
  let sequence = 0;
  const recordReceipt = ({
    baseDir = root,
    role,
    domain,
    contextId,
    candidateId,
    startedAt,
    completedAt,
    issuedAt = completedAt,
    inputArtifactSha256,
    resultPayloadSha256,
  }) => {
    sequence += 1;
    const slug = `${role}-${String(sequence).padStart(3, "0")}`;
    const receiptPath = join(baseDir, `execution-receipt-${slug}.json`);
    const receipt = {
      schemaVersion: "1.0.0",
      receiptId: `PVE-${role.replaceAll("-", "").toUpperCase()}-${String(sequence).padStart(3, "0")}`,
      immutable: true,
      role,
      ...(domain ? { domain } : {}),
      contextId,
      candidateId,
      hostId: "synthetic-contract-host",
      mechanism: "container-read-only-mount",
      readOnly: true,
      writeTools: [],
      permittedReadOnlyTools: ["filesystem-read", "media-inspect", "checksum"],
      startedAt,
      completedAt,
      issuedAt,
      ...(inputArtifactSha256 ? { inputArtifactSha256 } : {}),
      ...(resultPayloadSha256 ? { resultPayloadSha256 } : {}),
    };
    writeJson(receiptPath, receipt);
    const reference = (path) => ({
      artifactPath: path.replaceAll("\\", "/").split("/").at(-1),
      sha256: sha(path),
      bytes: statSync(path).size,
    });
    return {
      receipt: reference(receiptPath),
    };
  };
  return {
    environment: { ...process.env },
    recordReceipt,
  };
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function createReviewIntegrity(root, reviewDomain, executionRecords) {
  const modelId = "synthetic-independent-reviewer-v1";
  const canonicalRubricPath = join(
    pluginDir,
    "pipeline",
    "product-demo-studio",
    "references",
    "killer-demo-playbook.md",
  );
  const canonicalRubric = {
    artifactPath: canonicalRubricPath,
    sha256: sha(canonicalRubricPath),
  };
  const expected = new Map([
    ["buried-hero", "FAIL"],
    ["feature-rung", "FAIL"],
    ["no-hold", "FAIL"],
    ["dead-wait", "FAIL"],
    ["three-heroes", "FAIL"],
    ["clean-pass", "PASS"],
  ]);
  const fixtures = [...expected].map(([id, verdict]) => {
    const evidencePath = join(root, `calibration-evidence-${reviewDomain}-${id}.json`);
    writeJson(evidencePath, {
      fixtureId: id,
      reviewDomain,
      expectedVerdict: verdict,
      synthetic: true,
    });
    const candidateId = `calibration-${reviewDomain.replaceAll("-", "")}-${id}`;
    const contextId = `calibration-${reviewDomain}-${id}-context`;
    const reportPath = join(root, `calibration-review-${reviewDomain}-${id}.json`);
    const passed = verdict === "PASS";
    const checks = [{
      id: id === "clean-pass" ? "clean-control" : `detect-${id}`,
      passed,
      evidence: [{ artifactPath: evidencePath, sha256: sha(evidencePath) }],
    }];
    const reportPayload = {
      schemaVersion: "1.0.0",
      fixtureId: id,
      candidateId,
      reviewDomain,
      modelId,
      contextId,
      startedAt: "2026-07-29T14:50:00.000Z",
      completedAt: "2026-07-29T14:51:00.000Z",
      checks,
      verdict,
    };
    writeJson(reportPath, {
      ...reportPayload,
      executionReceipt: executionRecords.recordReceipt({
        role: "reviewer",
        domain: reviewDomain,
        contextId,
        candidateId,
        startedAt: "2026-07-29T14:50:00.000Z",
        completedAt: "2026-07-29T14:51:00.000Z",
        inputArtifactSha256: sha(evidencePath),
        resultPayloadSha256: shaBytes(Buffer.from(JSON.stringify(reportPayload))),
      }),
    });
    return {
      id,
      expectedVerdict: verdict,
      reviewReport: { artifactPath: reportPath, sha256: sha(reportPath) },
    };
  });
  const calibrationPath = join(root, `reviewer-calibration-${reviewDomain}.json`);
  writeJson(calibrationPath, {
    schemaVersion: "1.0.0",
    status: "PASS",
    pluginVersion: "1.8.5",
    reviewDomain,
    modelId,
    canonicalRubric,
    verticalOverlay: null,
    inputContractVersion: "review-report.schema/1.0.0",
    completedAt: "2026-07-29T14:55:00.000Z",
    fixtures,
  });
  return {
    canonicalRubric,
    verticalOverlay: null,
    calibrationRecord: { artifactPath: calibrationPath, sha256: sha(calibrationPath) },
    modelId,
    generatorReasoningReceived: false,
    priorReviewsReceived: false,
  };
}

function reviewerCalibrationIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-reviewer-calibration-"));
  try {
    const executionRecords = createExecutionRecords(root);
    const integrity = createReviewIntegrity(root, "story-experience", executionRecords);
    let result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-reviewer-calibration.mjs"),
      integrity.calibrationRecord.artifactPath,
    ], { encoding: "utf8", env: executionRecords.environment });
    assert(result.status === 0, "reviewer calibration validator accepts all known-bad rejections and the clean pass");

    const calibration = loadJson(integrity.calibrationRecord.artifactPath);
    const buried = calibration.fixtures.find((fixture) => fixture.id === "buried-hero");
    const buriedReport = loadJson(buried.reviewReport.artifactPath);
    buriedReport.checks[0].passed = true;
    buriedReport.verdict = "PASS";
    writeJson(buried.reviewReport.artifactPath, buriedReport);
    buried.reviewReport.sha256 = sha(buried.reviewReport.artifactPath);
    writeJson(integrity.calibrationRecord.artifactPath, calibration);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "validate-reviewer-calibration.mjs"),
      integrity.calibrationRecord.artifactPath,
    ], { encoding: "utf8", env: executionRecords.environment });
    assert(result.status !== 0, "reviewer calibration validator rejects a known-bad fixture that passes");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function mediaAccelerationIntegration() {
  const root = mkdtempSync(join(tmpdir(), "product-demo-media-acceleration-"));
  try {
    const detectorSource = readFileSync(
      join(pluginDir, "scripts", "detect-media-acceleration.mjs"),
      "utf8",
    );
    assert(detectorSource.includes("D:\\\\Local-AI"), "media acceleration detector defaults to the Local-AI capability root on Windows");
    assert(detectorSource.includes("LOCAL_AI_ROOT"), "media acceleration detector permits a configured Local-AI capability root");
    const manifestPath = join(root, "media-acceleration.json");
    const result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "detect-media-acceleration.mjs"),
      "--out", manifestPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "media acceleration detector emits a deterministic GPU-or-CPU selection manifest");
    const manifest = loadJson(manifestPath);
    const schema = loadSchema(join(schemaDir, "media-acceleration.schema.json"));
    const errors = [];
    validate(schema, manifest, "$", join(schemaDir, "media-acceleration.schema.json"), schema, errors);
    assert(errors.length === 0, "media acceleration manifest conforms to the canonical schema");
    assert(
      manifest.mode !== "gpu-preferred" || manifest.nvidia.available === true,
      "GPU-preferred mode is emitted only when a compatible NVIDIA device is detected",
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function generateRealCandidate(videoPath) {
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-f", "lavfi",
    "-i", "testsrc2=size=320x180:rate=30:duration=20",
    "-f", "lavfi",
    "-i", "sine=frequency=1000:sample_rate=48000",
    "-t", "23",
    "-vf", "tpad=stop_mode=clone:stop_duration=3",
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

function buildRenderTimingDocument(candidateId, storyboard, durationSeconds = 23, fps = 30) {
  return {
    schemaVersion: "1.0.0",
    candidateId,
    episodeId: storyboard.episodeId,
    durationSeconds,
    fps,
    status: "PASS",
    beats: storyboard.segments.map((segment, index) => ({
      episodeId: storyboard.episodeId,
      storyboardSegmentId: segment.id,
      startsAtSeconds: segment.timelineStartSeconds,
      endsAtSeconds: storyboard.segments[index + 1]?.timelineStartSeconds ?? durationSeconds,
      actionAtSeconds: segment.timelineStartSeconds + segment.interaction.narrationSync.actionAtSeconds,
      resultVisibleAtSeconds: segment.timelineStartSeconds + segment.interaction.narrationSync.resultVisibleAtSeconds,
      ...(segment.endCard ? {
        stableFromSeconds: segment.timelineStartSeconds + segment.interaction.narrationSync.resultVisibleAtSeconds + 0.7,
      } : {}),
    })),
  };
}

function decodedFrameHash(mediaPath, seconds) {
  const result = spawnSync("ffmpeg", [
    "-v", "error",
    "-ss", Number(seconds).toFixed(6),
    "-i", mediaPath,
    "-frames:v", "1",
    "-an",
    "-pix_fmt", "rgb24",
    "-f", "rawvideo",
    "-",
  ], { encoding: null, maxBuffer: 64 * 1024 * 1024 });
  if (result.status !== 0 || !Buffer.isBuffer(result.stdout) || result.stdout.length === 0) {
    throw new Error(`could not decode frame at ${seconds}s: ${Buffer.from(result.stderr ?? "").toString("utf8")}`);
  }
  return shaBytes(result.stdout);
}

function materializeEditorialAudit(root, candidate, {
  fileName = "editorial-audit.json",
  auditId = "PVEA-SYNTHETIC-001",
  contextId = "orchestrator-editorial-context",
  startedAt = "2026-07-29T22:00:00.000Z",
  completedAt = "2026-07-29T22:00:30.000Z",
} = {}) {
  const candidatePath = isAbsolute(candidate.artifactPath)
    ? candidate.artifactPath
    : join(root, candidate.artifactPath);
  const durationSeconds = Number(spawnSync("ffprobe", [
    "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", candidatePath,
  ], { encoding: "utf8" }).stdout.trim());
  const phases = [
    "opening-promise", "transitions-and-focus", "hero-before-action-result",
    "screen-cleanliness", "responsive-legibility", "cta-and-impact", "stable-final-hold",
  ];
  const timestamps = [0.5, 3, 8, 12, 16, 19.5, Math.max(0, durationSeconds - 0.1)];
  const auditPath = join(root, fileName);
  writeJson(auditPath, {
    schemaVersion: "1.0.0",
    auditId,
    candidate,
    auditor: { role: "orchestrator", contextId },
    fullPlayback: { continuous: true, mediaDurationSeconds: durationSeconds, startedAt, completedAt },
    phaseChecks: phases.map((phase, index) => ({
      phase,
      passed: true,
      evidence: [{
        kind: "frame-timestamp",
        candidateSha256: candidate.sha256,
        timestampSeconds: timestamps[index],
        frameSha256: decodedFrameHash(candidatePath, timestamps[index]),
      }],
    })),
    findings: [],
    status: "PASS",
    generatedAt: completedAt,
  });
  return {
    path: auditPath,
    reference: { artifactPath: fileName, sha256: sha(auditPath), bytes: statSync(auditPath).size },
  };
}

function materializeCandidateAudioApproval(root, candidate, executionRecords, {
  fileStem = "candidate-audio",
  reportId = "PVAR-SYNTHETIC-001",
  adjudicationId = "PVAA-SYNTHETIC-001",
  contextId = "isolated-audio-adjudicator-context",
  startedAt = "2026-07-29T22:00:00.000Z",
  completedAt = "2026-07-29T22:00:30.000Z",
  adjudicatedAt = "2026-07-29T22:01:00.000Z",
} = {}) {
  const candidatePath = isAbsolute(candidate.artifactPath)
    ? candidate.artifactPath
    : join(root, candidate.artifactPath);
  const sampleRateHz = 16000;
  const channels = 1;
  const decoded = spawnSync("ffmpeg", [
    "-v", "error", "-i", candidatePath,
    "-map", "0:a:0", "-vn", "-sn", "-dn",
    "-ac", String(channels), "-ar", String(sampleRateHz),
    "-acodec", "pcm_s16le", "-f", "s16le", "-",
  ], { encoding: null, maxBuffer: 64 * 1024 * 1024 });
  if (decoded.status !== 0 || !Buffer.isBuffer(decoded.stdout) || decoded.stdout.length === 0) {
    throw new Error(`could not decode candidate audio: ${Buffer.from(decoded.stderr ?? "").toString("utf8")}`);
  }
  const samplesPerChannel = decoded.stdout.length / (channels * 2);
  assert(Number.isInteger(samplesPerChannel), "synthetic candidate decode has an integral s16le sample count");

  const decodedAudioPath = join(root, `${fileStem}-program-16k-mono-s16.wav`);
  const decodedWav = spawnSync("ffmpeg", [
    "-v", "error", "-i", candidatePath, "-map", "0:a:0", "-vn",
    "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-y", decodedAudioPath,
  ], { encoding: "utf8" });
  if (decodedWav.status !== 0) throw new Error(`could not materialize listener PCM: ${decodedWav.stderr}`);

  const model = {
    id: "synthetic-local-audio-model",
    revision: "synthetic-revision-001",
  };
  const modelReceiptPath = join(root, `${fileStem}-model-receipt.json`);
  const modelReceipt = {
    schemaVersion: "1.0.0",
    modelId: model.id,
    revision: model.revision,
    license: "synthetic-test",
    artifacts: [{ path: "synthetic-model.safetensors", bytes: 1, sha256: "1".repeat(64) }],
    installedAt: "2026-07-28T22:00:00.000Z",
  };
  writeJson(modelReceiptPath, modelReceipt);
  model.receiptSha256 = shaBytes(Buffer.from(canonicalJson(modelReceipt), "utf8"));
  const rawResponsePath = join(root, `${fileStem}-raw-response.txt`);
  writeFileSync(rawResponsePath, "CHECK|full-program|PASS\nCHECK|pronunciation|PASS\nCHECK|delivery-and-pacing|PASS\nCHECK|artifacts-and-discontinuities|PASS\nSUMMARY|Synthetic full-program pass.\n", "utf8");
  const knownGoodAudioPath = join(root, `${fileStem}-known-good.wav`);
  const knownBadAudioPath = join(root, `${fileStem}-known-bad.wav`);
  for (const [audioPath, frequency] of [[knownGoodAudioPath, 440], [knownBadAudioPath, 220]]) {
    const generated = spawnSync("ffmpeg", [
      "-v", "error", "-f", "lavfi", "-i", `sine=frequency=${frequency}:duration=0.1`,
      "-c:a", "pcm_s16le", "-y", audioPath,
    ], { encoding: "utf8" });
    if (generated.status !== 0) throw new Error(`could not generate synthetic calibration audio: ${generated.stderr}`);
  }
  const knownGoodResponsePath = join(root, `${fileStem}-known-good-response.json`);
  const knownBadResponsePath = join(root, `${fileStem}-known-bad-response.json`);
  writeJson(knownGoodResponsePath, { expected: "PASS", observed: "PASS" });
  writeJson(knownBadResponsePath, { expected: "FAIL", observed: "FAIL" });
  const artifactRef = (absolutePath) => ({
    artifactPath: absolutePath,
    sha256: sha(absolutePath),
    bytes: statSync(absolutePath).size,
  });

  const nativeReportFileName = `${fileStem}-local-ai-listen-report.json`;
  const nativeReportPath = join(root, nativeReportFileName);
  const ffmpegPath = spawnSync("where.exe", ["ffmpeg"], { encoding: "utf8" }).stdout.trim().split(/\r?\n/)[0];
  const checks = [
    ["full-program", "Every decoded candidate audio sample was analyzed."],
    ["pronunciation", "Names, acronyms, and pronunciation-risk words passed local audio perception."],
    ["delivery-and-pacing", "Delivery, pauses, and pacing passed local audio perception."],
    ["artifacts-and-discontinuities", "No skipped words, leaks, clicks, truncation, or discontinuities were detected."],
  ].map(([id, notes]) => ({ id, passed: true, notes }));
  writeJson(nativeReportPath, {
    schemaVersion: "1.0.0",
    reportId: `LAPR-${candidate.sha256.slice(0, 16)}`,
    status: "PASS",
    candidate,
    decodedAudio: {
      ...artifactRef(decodedAudioPath),
      sampleRate: sampleRateHz,
      channels,
      bitsPerSample: 16,
      sampleCount: samplesPerChannel,
      durationSeconds: samplesPerChannel / sampleRateHz,
      coverage: {
        startSample: 0,
        endSampleExclusive: samplesPerChannel,
        expectedSamples: samplesPerChannel,
        continuous: true,
      },
      sourceAudioStream: { index: 1, codec_type: "audio", codec_name: "aac" },
      sourceProbe: { duration: String(samplesPerChannel / sampleRateHz) },
      decoder: {
        ffmpegPath,
        ffmpegSha256: sha(ffmpegPath),
        version: "synthetic-test",
        commandSha256: "2".repeat(64),
      },
    },
    model: {
      ...model,
      license: "synthetic-test",
      torch: "synthetic-test",
      transformers: "synthetic-test",
      device: "synthetic-test-device",
      peakVramBytes: 1,
    },
    request: {
      promptVersion: "product-video-audio-perception-v1",
      promptSha256: "3".repeat(64),
      transcript: null,
      pronunciationManifest: null,
      generation: { doSample: false, seed: 0, maxNewTokens: 1000 },
      modelResponse: artifactRef(rawResponsePath),
    },
    execution: {
      startedAt,
      completedAt,
      durationSeconds: 30,
      localFilesOnly: true,
      remoteInputs: false,
    },
    checks,
    findings: [],
    summary: "Synthetic full-program pass.",
    generatedAt: completedAt,
  });

  const materializeCalibrationNativeReport = ({ caseName, audioPath, responsePath, status, completedAt: caseCompletedAt }) => {
    const caseCandidate = {
      candidateId: `${fileStem}-${caseName}-fixture`,
      ...artifactRef(audioPath),
      sourceRevision: "synthetic-audio-calibration-v1",
      renderProvenanceId: `${fileStem}-${caseName}-fixture-v1`,
    };
    const caseDecodedPath = join(root, `${fileStem}-${caseName}-program-16k-mono-s16.wav`);
    const caseDecoded = spawnSync("ffmpeg", [
      "-v", "error", "-i", audioPath, "-map", "0:a:0", "-vn",
      "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-y", caseDecodedPath,
    ], { encoding: "utf8" });
    if (caseDecoded.status !== 0) throw new Error(`could not materialize ${caseName} listener PCM: ${caseDecoded.stderr}`);
    const caseRaw = spawnSync("ffmpeg", [
      "-v", "error", "-i", audioPath, "-map", "0:a:0", "-vn", "-sn", "-dn",
      "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le", "-f", "s16le", "-",
    ], { encoding: null, maxBuffer: 16 * 1024 * 1024 });
    if (caseRaw.status !== 0 || !Buffer.isBuffer(caseRaw.stdout) || caseRaw.stdout.length === 0) {
      throw new Error(`could not decode ${caseName} calibration audio`);
    }
    const caseSamples = caseRaw.stdout.length / 2;
    const caseChecks = checks.map((check) => ({ ...check }));
    const caseFindings = [];
    if (status === "FAIL") {
      caseChecks[3] = { ...caseChecks[3], passed: false, notes: "Synthetic discontinuity correctly detected." };
      caseFindings.push({
        id: "PVF-AUDIO-CALIBRATION-BAD-001",
        checkId: "artifacts-and-discontinuities",
        severity: "BLOCKER",
        startSeconds: 0,
        endSeconds: 0.1,
        description: "Synthetic known-bad artifact detected.",
      });
    }
    const caseReportPath = join(root, `${fileStem}-${caseName}-local-ai-listen-report.json`);
    writeJson(caseReportPath, {
      schemaVersion: "1.0.0",
      reportId: `LAPR-${caseCandidate.sha256.slice(0, 16)}`,
      status,
      candidate: caseCandidate,
      decodedAudio: {
        ...artifactRef(caseDecodedPath),
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        sampleCount: caseSamples,
        durationSeconds: caseSamples / 16000,
        coverage: {
          startSample: 0,
          endSampleExclusive: caseSamples,
          expectedSamples: caseSamples,
          continuous: true,
        },
        sourceAudioStream: { index: 0, codec_type: "audio", codec_name: "pcm_s16le" },
        sourceProbe: { duration: String(caseSamples / 16000) },
        decoder: {
          ffmpegPath,
          ffmpegSha256: sha(ffmpegPath),
          version: "synthetic-test",
          commandSha256: "2".repeat(64),
        },
      },
      model: {
        ...model,
        license: "synthetic-test",
        torch: "synthetic-test",
        transformers: "synthetic-test",
        device: "synthetic-test-device",
        peakVramBytes: 1,
      },
      request: {
        promptVersion: "product-video-audio-perception-v1",
        promptSha256: "3".repeat(64),
        transcript: null,
        pronunciationManifest: null,
        generation: { doSample: false, seed: 0, maxNewTokens: 1000 },
        modelResponse: artifactRef(responsePath),
      },
      execution: {
        startedAt: new Date(Date.parse(caseCompletedAt) - 30_000).toISOString(),
        completedAt: caseCompletedAt,
        durationSeconds: 30,
        localFilesOnly: true,
        remoteInputs: false,
      },
      checks: caseChecks,
      findings: caseFindings,
      summary: status === "PASS" ? "Synthetic known-good fixture passed." : "Synthetic known-bad fixture failed as expected.",
      generatedAt: caseCompletedAt,
    });
    return { path: caseReportPath, reference: artifactRef(caseReportPath) };
  };
  const knownGoodNativeReport = materializeCalibrationNativeReport({
    caseName: "known-good",
    audioPath: knownGoodAudioPath,
    responsePath: knownGoodResponsePath,
    status: "PASS",
    completedAt: "2026-07-29T13:59:00.000Z",
  });
  const knownBadNativeReport = materializeCalibrationNativeReport({
    caseName: "known-bad",
    audioPath: knownBadAudioPath,
    responsePath: knownBadResponsePath,
    status: "FAIL",
    completedAt: "2026-07-29T14:00:00.000Z",
  });

  const reportFileName = `${fileStem}-perception-report.json`;
  const reportPath = join(root, reportFileName);
  writeJson(reportPath, {
    schemaVersion: "1.1.0",
    reportId,
    candidate,
    listener: {
      kind: "local-audio-model",
      controlPlane: "ai.ps1",
      command: "listen",
      localOnly: true,
      report: artifactRef(nativeReportPath),
      modelReceipt: artifactRef(modelReceiptPath),
    },
    calibration: {
      calibrationId: "PVAC-SYNTHETIC-001",
      promptVersion: "product-video-audio-perception-v1",
      promptSha256: "3".repeat(64),
      model,
      evaluatedAt: "2026-07-29T14:00:00.000Z",
      validUntil: "2026-08-05T14:00:00.000Z",
      knownGood: {
        caseId: "known-good-001",
        audio: artifactRef(knownGoodAudioPath),
        nativeReport: knownGoodNativeReport.reference,
        rawResponse: artifactRef(knownGoodResponsePath),
        expectedStatus: "PASS",
        observedStatus: "PASS",
      },
      knownBad: {
        caseId: "known-bad-001",
        audio: artifactRef(knownBadAudioPath),
        nativeReport: knownBadNativeReport.reference,
        rawResponse: artifactRef(knownBadResponsePath),
        expectedStatus: "FAIL",
        observedStatus: "FAIL",
      },
    },
    status: "PASS",
    generatedAt: completedAt,
  });
  const perceptionReference = {
    artifactPath: reportFileName,
    sha256: sha(reportPath),
    bytes: statSync(reportPath).size,
  };

  const adjudicationFileName = `${fileStem}-adjudication.json`;
  const adjudicationPath = join(root, adjudicationFileName);
  writeJson(adjudicationPath, {
    schemaVersion: "1.0.0",
    adjudicationId,
    candidate,
    perceptionReport: perceptionReference,
    reviewer: {
      role: "audio-captions-sync-reviewer",
      contextId,
      readOnly: true,
      independent: true,
      executionReceipt: executionRecords.recordReceipt({
        role: "reviewer",
        domain: "audio-captions-synchronization",
        contextId,
        candidateId: candidate.candidateId,
        startedAt: completedAt,
        completedAt: adjudicatedAt,
        issuedAt: adjudicatedAt,
      }),
    },
    checks: [
      ["candidate-binding", "The report binds the exact encoded candidate bytes."],
      ["decoded-sample-coverage", "Every decoded sample is covered exactly once."],
      ["model-provenance", "Local model id, revision, hash, and receipt are bound."],
      ["prompt-and-raw-response", "Prompt version and raw response bytes are bound."],
      ["calibration", "Fresh known-good and known-bad calibration evidence passed."],
      ["audio-criteria", "All four full-program audio criteria passed."],
    ].map(([id, notes]) => ({ id, passed: true, notes })),
    findings: [],
    status: "PASS",
    generatedAt: adjudicatedAt,
  });
  const adjudicationReference = {
    artifactPath: adjudicationFileName,
    sha256: sha(adjudicationPath),
    bytes: statSync(adjudicationPath).size,
  };
  return {
    nativeReport: { path: nativeReportPath, reference: artifactRef(nativeReportPath) },
    knownGoodNativeReport,
    knownBadNativeReport,
    report: { path: reportPath, reference: perceptionReference },
    adjudication: { path: adjudicationPath, reference: adjudicationReference },
    reference: { perceptionReport: perceptionReference, adjudication: adjudicationReference },
  };
}

function bindRenderTimingFrameHashes(renderTiming, mediaPath) {
  for (const beat of renderTiming.beats) {
    const endSampleAt = Math.max(beat.startsAtSeconds, beat.endsAtSeconds - (1 / renderTiming.fps));
    beat.frameHashes = {
      start: decodedFrameHash(mediaPath, beat.startsAtSeconds),
      action: decodedFrameHash(mediaPath, beat.actionAtSeconds),
      result: decodedFrameHash(mediaPath, beat.resultVisibleAtSeconds),
      end: decodedFrameHash(mediaPath, endSampleAt),
    };
  }
  return renderTiming;
}

function buildCanonicalCraftArtifacts(root, candidateId, storyboard, addArtifact, media) {
  const baseCapture = {
    scenario: "approval-exception",
    beat: "reveal",
    storyboardSegmentId: "reveal",
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
      deliveryFrame: { width: 1920, height: 1080 },
      deliveredCrop: { x: 760, y: 180, width: 1050, height: 591 },
      sourceFrame: { width: 3840, height: 2160 },
      smallDelivery: true,
      browserZoomPercent: 100,
    },
    interaction: {
      kind: "click",
      target: "exception-filter",
      cursor: {
        from: [1450, 780], to: [1520, 430], park: [1760, 930],
        durationMs: 500, easing: "eased-deceleration", scale: 1.75,
        settleBeforeActionMs: 250, holdAfterActionMs: 500,
      },
      cue: "visual",
      feedback: { type: "radial-pulse", durationMs: 350, brandColor: "#4F46E5", opacity: 0.35 },
      keystrokeOverlay: false,
      pacing: { activity: "meaningful-action", treatment: "real-time", multiplier: 1, truthTreatment: "The product interaction remains real-time." },
      narrationSync: { cursorLeadSeconds: 0.35, actionAtSeconds: 1.1, resultVisibleAtSeconds: 1.8, spokenResultAtSeconds: 2.0 },
    },
  };
  const captures = storyboard.segments.map((segment) => {
    const value = structuredClone(baseCapture);
    value.beat = segment.id;
    value.storyboardSegmentId = segment.id;
    value.captureSurface.irrelevantNavigation = segment.framing.irrelevantNavigation;
    value.captureSurface.plannedTreatment = segment.framing.deliveryTreatment;
    value.captureSurface.smallDelivery = segment.framing.smallDelivery;
    value.interaction.kind = segment.interaction.kind;
    value.interaction.target = segment.interaction.target;
    value.interaction.cue = segment.interaction.clickCue === "none" ? "none" : "visual";
    value.interaction.cursor = {
      from: [1450, 780], to: [1520, 430], park: [1760, 930],
      durationMs: segment.interaction.craft.cursorMoveMs,
      easing: segment.interaction.craft.cursorMotion,
      scale: segment.interaction.craft.cursorScale,
      settleBeforeActionMs: segment.interaction.craft.settleBeforeActionMs,
      holdAfterActionMs: segment.interaction.craft.holdAfterActionMs,
    };
    value.interaction.feedback = {
      type: segment.interaction.craft.feedbackType,
      durationMs: segment.interaction.craft.feedbackDurationMs,
      ...(segment.interaction.craft.feedbackColor ? { brandColor: segment.interaction.craft.feedbackColor } : {}),
      ...(segment.interaction.craft.feedbackOpacity !== undefined ? { opacity: segment.interaction.craft.feedbackOpacity } : {}),
    };
    value.interaction.keystrokeOverlay = segment.interaction.craft.keystrokeOverlay;
    value.interaction.pacing = segment.pacing;
    value.interaction.narrationSync = segment.interaction.narrationSync;
    return value;
  });
  const captureManifest = addArtifact("capture-manifest", "capture-manifest", "capture-manifest.json", "application/json", captures);
  const captureEvidence = addArtifact("capture-evidence", "capture-evidence", "capture-evidence.json", "application/json", {
    candidateId,
    sourceFrame: { width: 3840, height: 2160 },
    beats: storyboard.segments.map((segment) => ({
      episodeId: storyboard.episodeId,
      storyboardSegmentId: segment.id,
      ...segment.interaction.narrationSync,
      cutAtSeconds: segment.interaction.narrationSync.resultVisibleAtSeconds + 1.4,
    })),
  });
  const rawCapturePath = join(root, "raw-capture.png");
  const rawResult = spawnSync("ffmpeg", [
    "-v", "error", "-f", "lavfi", "-i", "color=c=black:size=3840x2160", "-frames:v", "1", "-y", rawCapturePath,
  ], { encoding: "utf8" });
  if (rawResult.status !== 0) throw new Error(`could not create raw capture fixture: ${rawResult.stderr || rawResult.stdout}`);
  const rawCapture = addArtifact("raw-capture", "raw-capture", "raw-capture.png", "image/png", null, { existing: true });
  const renderTiming = addArtifact(
    "render-timing",
    "render-timing",
    "render-timing.json",
    "application/json",
    bindRenderTimingFrameHashes(buildRenderTimingDocument(candidateId, storyboard), join(root, media.artifactPath)),
  );
  return { captureManifest, captureEvidence, rawCapture, renderTiming, media };
}

function materializeCanonicalCraftReport(root, candidateId, storyboardArtifact, craftArtifacts, media) {
  const outPath = join(root, "craftContractValidation.json");
  const result = spawnSync(process.execPath, [
    join(pluginDir, "scripts", "validate-craft-contracts.mjs"),
    "--candidate-id", candidateId,
    "--storyboard", join(root, storyboardArtifact.artifactPath),
    "--storyboard-artifact-id", storyboardArtifact.artifactId,
    "--capture-manifest", join(root, craftArtifacts.captureManifest.artifactPath),
    "--capture-artifact-id", craftArtifacts.captureManifest.artifactId,
    "--capture-evidence", join(root, craftArtifacts.captureEvidence.artifactPath),
    "--capture-evidence-artifact-id", craftArtifacts.captureEvidence.artifactId,
    "--raw-capture", join(root, craftArtifacts.rawCapture.artifactPath),
    "--raw-capture-artifact-id", craftArtifacts.rawCapture.artifactId,
    "--render-timing", join(root, craftArtifacts.renderTiming.artifactPath),
    "--render-timing-artifact-id", craftArtifacts.renderTiming.artifactId,
    "--media", join(root, media.artifactPath),
    "--media-artifact-id", media.artifactId,
    "--out", outPath,
  ], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`canonical craft fixture failed: ${result.stderr || result.stdout}`);
  }
  return { outPath, report: loadJson(outPath) };
}

function buildScriptArtifacts(candidateId, addArtifact) {
  const script = addArtifact("script", "script", "script.json", "application/json", { candidateId });
  const truthSheet = addArtifact("truth-sheet", "truth-sheet", "truth-sheet.json", "application/json", { candidateId });
  const claimLedger = addArtifact("claim-ledger", "claim-ledger", "claim-ledger.json", "application/json", { candidateId });
  return { script, truthSheet, claimLedger };
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
  const acceleration = addArtifact("acceleration-manifest", "manifest", "media-acceleration.json", "application/json", {
    schemaVersion: "1.0.0",
    detectedAt: "2026-07-29T21:58:00.000Z",
    mode: "cpu-fallback",
    nvidia: { available: false, name: null, driverVersion: null, cudaVersion: null, memoryMiB: null },
    ffmpeg: { available: true, nvencEncoders: [], usableNvencEncoders: [] },
    inference: { engine: null, available: false, cudaUsable: false, detail: "Synthetic CPU fixture." },
    selection: { videoEncoder: "libx264", mediaInferenceDevice: "cpu" },
    fallbackReason: "Synthetic portable contract fixture intentionally exercises deterministic CPU fallback.",
  });
  const storyboardDocument = loadJson(join(pluginDir, "scripts", "storyboard.example.json"));
  const storyboardArtifact = addArtifact("storyboard", "storyboard", "storyboard.json", "application/json", storyboardDocument);
  const craftArtifacts = buildCanonicalCraftArtifacts(root, candidateId, storyboardDocument, addArtifact, media);
  const captureManifestArtifact = craftArtifacts.captureManifest;
  const captureEvidenceArtifact = craftArtifacts.captureEvidence;
  const rawCaptureArtifact = craftArtifacts.rawCapture;
  const renderTimingArtifact = craftArtifacts.renderTiming;
  buildScriptArtifacts(candidateId, addArtifact);
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
    craftContractValidation: ["storyboard-craft-contract", "capture-manifest-craft-contract", "beat-timing-deltas", "rendered-story-contract"],
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
    craftContractValidation: "product-demo-studio-craft-contract-validator",
  };
  const canonicalCraft = materializeCanonicalCraftReport(root, candidateId, storyboardArtifact, craftArtifacts, media);
  const reports = {};
  for (const [reportType, checkIds] of Object.entries(reportChecks)) {
    const report = reportType === "craftContractValidation" ? canonicalCraft.report : {
      schemaVersion: "1.0.0",
      candidateId,
      reportType,
      status: "PASS",
      generator: {
        tool: reportGenerators[reportType],
        version: "1.0.0",
        command: `synthetic-fixture ${reportType} --input ${media.sha256}`,
      },
      inputs: (reportType === "craftContractValidation"
        ? [storyboardArtifact, captureManifestArtifact, captureEvidenceArtifact, rawCaptureArtifact, renderTimingArtifact, media]
        : [media]
      ).map((artifact) => ({ artifactId: artifact.artifactId, sha256: artifact.sha256 })),
      checks: checkIds.map((id) => ({
        id,
        passed: true,
        evidenceArtifactIds: reportType === "craftContractValidation"
          ? (id === "storyboard-craft-contract"
            ? [storyboardArtifact.artifactId]
            : id === "capture-manifest-craft-contract"
              ? [captureManifestArtifact.artifactId, captureEvidenceArtifact.artifactId, rawCaptureArtifact.artifactId]
              : id === "beat-timing-deltas"
                ? [storyboardArtifact.artifactId, captureManifestArtifact.artifactId, captureEvidenceArtifact.artifactId, rawCaptureArtifact.artifactId]
                : [storyboardArtifact.artifactId, renderTimingArtifact.artifactId, media.artifactId])
          : [media.artifactId],
      })),
      ...(reportType === "craftContractValidation" ? {
        measurements: storyboardDocument.segments.map((segment) => ({
          beatId: `${storyboardDocument.episodeId}.${segment.id}`,
          cursorLeadSeconds: segment.interaction.narrationSync.cursorLeadSeconds,
          actionToResultSeconds: segment.interaction.narrationSync.resultVisibleAtSeconds - segment.interaction.narrationSync.actionAtSeconds,
          resultToSpokenSeconds: segment.interaction.narrationSync.spokenResultAtSeconds - segment.interaction.narrationSync.resultVisibleAtSeconds,
          resultHoldToCutSeconds: 1.4,
          evidenceArtifactIds: [captureEvidenceArtifact.artifactId],
        })),
        sourceGeometry: {
          width: 3840,
          height: 2160,
          rawCaptureArtifactId: rawCaptureArtifact.artifactId,
          probe: "ffprobe",
        },
        renderMeasurements: storyboardDocument.segments.map((segment) => ({
          beatId: `${storyboardDocument.episodeId}.${segment.id}`,
          startDeltaSeconds: 0,
          actionDeltaSeconds: 0,
          resultDeltaSeconds: 0,
          endDeltaSeconds: 0,
          resultHoldSeconds: (storyboardDocument.segments[storyboardDocument.segments.indexOf(segment) + 1]?.timelineStartSeconds ?? 23)
            - (segment.timelineStartSeconds + segment.interaction.narrationSync.resultVisibleAtSeconds),
          stableHoldSeconds: segment.endCard ? 3 : null,
          frameHashesVerified: true,
          stateChangeRequired: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind),
          stateChangeVerified: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? true : null,
          stateChangeMeanAbsoluteDifference: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? 10 : null,
          stateChangePixelRatio: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? 0.1 : null,
          stateChangeMeanThreshold: 0.5,
          stateChangePixelRatioThreshold: 0.001,
          stableFrameSampleCount: segment.endCard ? 8 : 0,
          stableFramesStable: segment.endCard ? true : null,
          stableFrameMaxMeanAbsoluteDifference: segment.endCard ? 0 : null,
          stableFrameMaxChangedPixelRatio: segment.endCard ? 0 : null,
          stableFrameThreshold: segment.endCard ? 1 : null,
          stableFrameChangedPixelRatioThreshold: segment.endCard ? 0.0005 : null,
          evidenceArtifactIds: [renderTimingArtifact.artifactId, media.artifactId],
        })),
        mediaProbe: {
          durationSeconds: 23,
          fps: 30,
          width: 320,
          height: 180,
          mediaArtifactId: media.artifactId,
          probe: "ffprobe",
        },
      } : {}),
      summary: { total: checkIds.length, passed: checkIds.length, failed: 0 },
      generatedAt,
    };
    const artifact = addArtifact(
      `report-${reportType}`,
      "report",
      `${reportType}.json`,
      "application/json",
      reportType === "craftContractValidation" ? null : report,
      { existing: reportType === "craftContractValidation" },
    );
    reports[reportType] = {
      artifactId: artifact.artifactId,
      artifactPath: artifact.artifactPath,
      sha256: artifact.sha256,
      candidateId,
      reportType,
      status: "PASS",
      generatedAt: report.generatedAt,
    };
  }
  const evidencePackage = {
    schemaVersion: "1.0.0",
    candidate: { candidateId, immutable: true, mediaArtifactId: media.artifactId },
    provenance: {
      source: { repository: "https://example.invalid/synthetic.git", revision: "0123456789abcdef", dirty: false },
      build: { buildId: "synthetic-build", manifest: { artifactId: build.artifactId, artifactPath: build.artifactPath, sha256: build.sha256 } },
      configuration: { manifest: { artifactId: config.artifactId, artifactPath: config.artifactPath, sha256: config.sha256 } },
      capture: {
        captureId: "synthetic-capture-001",
        command: "playwright synthetic-final-capture",
        rawCapture: { artifactId: rawCaptureArtifact.artifactId, artifactPath: rawCaptureArtifact.artifactPath, sha256: rawCaptureArtifact.sha256 },
        startedAt: "2026-07-29T21:55:00.000Z",
        completedAt: "2026-07-29T21:58:00.000Z",
      },
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
        accelerationManifest: {
          artifactId: acceleration.artifactId,
          artifactPath: acceleration.artifactPath,
          sha256: acceleration.sha256,
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
  ], { encoding: "utf8", env: process.env });
  if (result.status !== 0) {
    throw new Error(`Canonical fixture preflight failed: ${result.stderr || result.stdout}`);
  }
  return {
    candidatePath,
    evidencePath,
    preflightPath,
    environment: { ...process.env },
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
    const records = createExecutionRecords(root);
    const bundle = records.recordReceipt({
      role: "reviewer",
      domain: "story-experience",
      contextId: "isolated-receipt-context",
      candidateId: "synthetic-receipt-candidate",
      startedAt: "2026-07-29T20:00:00.000Z",
      completedAt: "2026-07-29T20:05:00.000Z",
    });
    const receiptPath = join(root, bundle.receipt.artifactPath);
    const validator = join(pluginDir, "scripts", "validate-execution-receipt.mjs");
    const run = (receipt = receiptPath) =>
      spawnSync(process.execPath, [validator, receipt], { encoding: "utf8" });

    assert(run().status === 0, "execution receipt accepts a valid read-only host record");

    const originalReceipt = readFileSync(receiptPath);
    const receiptDocument = JSON.parse(originalReceipt.toString("utf8"));
    const rewriteReceipt = (changes) => {
      writeJson(receiptPath, { ...receiptDocument, ...changes });
    };

    rewriteReceipt({ readOnly: false });
    assert(run().status === 1, "execution receipt rejects a writable reviewer context");

    rewriteReceipt({ writeTools: ["filesystem-write"] });
    assert(run().status === 1, "execution receipt rejects write tools");

    rewriteReceipt({ mechanism: "prompt-only" });
    assert(run().status === 1, "execution receipt rejects unsupported isolation mechanisms");

    rewriteReceipt({ permittedReadOnlyTools: ["filesystem-read", "shell"] });
    assert(run().status === 1, "execution receipt rejects non-read-only tool classes");
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
    const acceleration = addArtifact("acceleration-manifest", "manifest", "media-acceleration.json", "application/json", {
      schemaVersion: "1.0.0",
      detectedAt: "2026-07-29T21:58:00.000Z",
      mode: "cpu-fallback",
      nvidia: { available: false, name: null, driverVersion: null, cudaVersion: null, memoryMiB: null },
      ffmpeg: { available: true, nvencEncoders: [], usableNvencEncoders: [] },
      inference: { engine: null, available: false, cudaUsable: false, detail: "Synthetic CPU fixture." },
      selection: { videoEncoder: "libx264", mediaInferenceDevice: "cpu" },
      fallbackReason: "Synthetic portable contract fixture intentionally exercises deterministic CPU fallback.",
    });
    const storyboardDocument = loadJson(join(pluginDir, "scripts", "storyboard.example.json"));
    const storyboardArtifact = addArtifact("storyboard", "storyboard", "storyboard.json", "application/json", storyboardDocument);
    const craftArtifacts = buildCanonicalCraftArtifacts(root, candidateId, storyboardDocument, addArtifact, media);
    const captureManifestArtifact = craftArtifacts.captureManifest;
    const captureEvidenceArtifact = craftArtifacts.captureEvidence;
    const rawCaptureArtifact = craftArtifacts.rawCapture;
    const renderTimingArtifact = craftArtifacts.renderTiming;
    buildScriptArtifacts(candidateId, addArtifact);
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
      craftContractValidation: ["storyboard-craft-contract", "capture-manifest-craft-contract", "beat-timing-deltas", "rendered-story-contract"],
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
      craftContractValidation: "product-demo-studio-craft-contract-validator",
    };
    const canonicalCraft = materializeCanonicalCraftReport(root, candidateId, storyboardArtifact, craftArtifacts, media);
    const reports = {};
    for (const [reportType, checkIds] of Object.entries(reportChecks)) {
      const report = reportType === "craftContractValidation" ? canonicalCraft.report : {
        schemaVersion: "1.0.0",
        candidateId,
        reportType,
        status: "PASS",
        generator: {
          tool: reportGenerators[reportType],
          version: "1.0.0",
          command: `node synthetic-${reportType}-extractor.mjs`,
        },
        inputs: (reportType === "craftContractValidation"
          ? [storyboardArtifact, captureManifestArtifact, captureEvidenceArtifact, rawCaptureArtifact, renderTimingArtifact, media]
          : [media]
        ).map((artifact) => ({ artifactId: artifact.artifactId, sha256: artifact.sha256 })),
        checks: checkIds.map((id) => ({
          id,
          passed: true,
          evidenceArtifactIds: reportType === "craftContractValidation"
            ? (id === "storyboard-craft-contract"
              ? [storyboardArtifact.artifactId]
              : id === "capture-manifest-craft-contract"
                ? [captureManifestArtifact.artifactId, captureEvidenceArtifact.artifactId, rawCaptureArtifact.artifactId]
                : id === "beat-timing-deltas"
                  ? [storyboardArtifact.artifactId, captureManifestArtifact.artifactId, captureEvidenceArtifact.artifactId, rawCaptureArtifact.artifactId]
                  : [storyboardArtifact.artifactId, renderTimingArtifact.artifactId, media.artifactId])
            : [media.artifactId],
        })),
        ...(reportType === "craftContractValidation" ? {
          measurements: storyboardDocument.segments.map((segment) => ({
            beatId: `${storyboardDocument.episodeId}.${segment.id}`,
            cursorLeadSeconds: segment.interaction.narrationSync.cursorLeadSeconds,
            actionToResultSeconds: segment.interaction.narrationSync.resultVisibleAtSeconds - segment.interaction.narrationSync.actionAtSeconds,
            resultToSpokenSeconds: segment.interaction.narrationSync.spokenResultAtSeconds - segment.interaction.narrationSync.resultVisibleAtSeconds,
            resultHoldToCutSeconds: 1.4,
            evidenceArtifactIds: [captureEvidenceArtifact.artifactId],
          })),
          sourceGeometry: {
            width: 3840,
            height: 2160,
            rawCaptureArtifactId: rawCaptureArtifact.artifactId,
            probe: "ffprobe",
          },
          renderMeasurements: storyboardDocument.segments.map((segment) => ({
            beatId: `${storyboardDocument.episodeId}.${segment.id}`,
            startDeltaSeconds: 0,
            actionDeltaSeconds: 0,
            resultDeltaSeconds: 0,
            endDeltaSeconds: 0,
            resultHoldSeconds: (storyboardDocument.segments[storyboardDocument.segments.indexOf(segment) + 1]?.timelineStartSeconds ?? 23)
              - (segment.timelineStartSeconds + segment.interaction.narrationSync.resultVisibleAtSeconds),
            stableHoldSeconds: segment.endCard ? 3 : null,
            frameHashesVerified: true,
            stateChangeRequired: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind),
            stateChangeVerified: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? true : null,
            stateChangeMeanAbsoluteDifference: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? 10 : null,
            stateChangePixelRatio: STATE_CHANGING_INTERACTION_KINDS.has(segment.interaction.kind) ? 0.1 : null,
            stateChangeMeanThreshold: 0.5,
            stateChangePixelRatioThreshold: 0.001,
            stableFrameSampleCount: segment.endCard ? 8 : 0,
            stableFramesStable: segment.endCard ? true : null,
            stableFrameMaxMeanAbsoluteDifference: segment.endCard ? 0 : null,
            stableFrameMaxChangedPixelRatio: segment.endCard ? 0 : null,
            stableFrameThreshold: segment.endCard ? 1 : null,
            stableFrameChangedPixelRatioThreshold: segment.endCard ? 0.0005 : null,
            evidenceArtifactIds: [renderTimingArtifact.artifactId, media.artifactId],
          })),
          mediaProbe: {
            durationSeconds: 23,
            fps: 30,
            width: 320,
            height: 180,
            mediaArtifactId: media.artifactId,
            probe: "ffprobe",
          },
        } : {}),
        summary: { total: checkIds.length, passed: checkIds.length, failed: 0 },
        generatedAt,
      };
      const artifact = addArtifact(
        `report-${reportType}`,
        "report",
        `${reportType}.json`,
        "application/json",
        reportType === "craftContractValidation" ? null : report,
        { existing: reportType === "craftContractValidation" },
      );
      reports[reportType] = {
        artifactId: artifact.artifactId,
        artifactPath: artifact.artifactPath,
        sha256: artifact.sha256,
        candidateId,
        reportType,
        status: "PASS",
        generatedAt: report.generatedAt,
      };
    }
    const evidencePackage = {
      schemaVersion: "1.0.0",
      candidate: { candidateId, immutable: true, mediaArtifactId: media.artifactId },
      provenance: {
        source: { repository: "https://example.invalid/synthetic.git", revision: "0123456789abcdef", dirty: false },
        build: { buildId: "synthetic-build", manifest: { artifactId: build.artifactId, artifactPath: build.artifactPath, sha256: build.sha256 } },
        configuration: { manifest: { artifactId: config.artifactId, artifactPath: config.artifactPath, sha256: config.sha256 } },
        capture: {
          captureId: "synthetic-capture-001",
          command: "playwright synthetic-final-capture",
          rawCapture: { artifactId: rawCaptureArtifact.artifactId, artifactPath: rawCaptureArtifact.artifactPath, sha256: rawCaptureArtifact.sha256 },
          startedAt: "2026-07-29T21:55:00.000Z",
          completedAt: "2026-07-29T21:58:00.000Z",
        },
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
          accelerationManifest: {
            artifactId: acceleration.artifactId,
            artifactPath: acceleration.artifactPath,
            sha256: acceleration.sha256,
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
    ], { encoding: "utf8", env: process.env });
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

    const captureManifestPath = join(root, captureManifestArtifact.artifactPath);
    const craftReportPath = join(root, reports.craftContractValidation.artifactPath);
    const originalCaptureManifest = readFileSync(captureManifestPath);
    const originalCraftReport = readFileSync(craftReportPath);
    const partialCapture = loadJson(captureManifestPath);
    partialCapture.pop();
    writeJson(captureManifestPath, partialCapture);
    const forgedCraftEvidence = structuredClone(evidencePackage);
    const forgedCaptureArtifact = forgedCraftEvidence.artifacts.find((artifact) => artifact.artifactId === captureManifestArtifact.artifactId);
    forgedCaptureArtifact.sha256 = sha(captureManifestPath);
    forgedCaptureArtifact.bytes = statSync(captureManifestPath).size;
    const forgedCraftReport = loadJson(craftReportPath);
    forgedCraftReport.inputs.find((input) => input.artifactId === captureManifestArtifact.artifactId).sha256 = forgedCaptureArtifact.sha256;
    writeJson(craftReportPath, forgedCraftReport);
    const forgedCraftReportArtifact = forgedCraftEvidence.artifacts.find((artifact) => artifact.artifactId === reports.craftContractValidation.artifactId);
    forgedCraftReportArtifact.sha256 = sha(craftReportPath);
    forgedCraftReportArtifact.bytes = statSync(craftReportPath).size;
    forgedCraftEvidence.reports.craftContractValidation.sha256 = forgedCraftReportArtifact.sha256;
    writeJson(evidencePath, forgedCraftEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"), "--evidence-package", evidencePath, "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight reruns the canonical craft validator and rejects a forged PASS report");
    writeFileSync(captureManifestPath, originalCaptureManifest);
    writeFileSync(craftReportPath, originalCraftReport);
    writeJson(evidencePath, evidencePackage);

    const measurementForgery = loadJson(craftReportPath);
    measurementForgery.renderMeasurements[0].startDeltaSeconds = 0.01;
    writeJson(craftReportPath, measurementForgery);
    const measurementForgeryEvidence = structuredClone(evidencePackage);
    const measurementForgeryArtifact = measurementForgeryEvidence.artifacts.find(
      (artifact) => artifact.artifactId === reports.craftContractValidation.artifactId,
    );
    measurementForgeryArtifact.sha256 = sha(craftReportPath);
    measurementForgeryArtifact.bytes = statSync(craftReportPath).size;
    measurementForgeryEvidence.reports.craftContractValidation.sha256 = measurementForgeryArtifact.sha256;
    writeJson(evidencePath, measurementForgeryEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"), "--evidence-package", evidencePath, "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight rejects forged craft measurements even when all canonical inputs are unchanged");
    writeFileSync(craftReportPath, originalCraftReport);
    writeJson(evidencePath, evidencePackage);

    const generatorForgery = loadJson(craftReportPath);
    generatorForgery.generator.version = "99.0.0-forged";
    writeJson(craftReportPath, generatorForgery);
    const generatorForgeryEvidence = structuredClone(evidencePackage);
    const generatorForgeryArtifact = generatorForgeryEvidence.artifacts.find(
      (artifact) => artifact.artifactId === reports.craftContractValidation.artifactId,
    );
    generatorForgeryArtifact.sha256 = sha(craftReportPath);
    generatorForgeryArtifact.bytes = statSync(craftReportPath).size;
    generatorForgeryEvidence.reports.craftContractValidation.sha256 = generatorForgeryArtifact.sha256;
    writeJson(evidencePath, generatorForgeryEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"), "--evidence-package", evidencePath, "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight rejects forged craft generator provenance when canonical inputs are unchanged");
    writeFileSync(craftReportPath, originalCraftReport);
    writeJson(evidencePath, evidencePackage);

    const accelerationPath = join(root, acceleration.artifactPath);
    const originalAcceleration = readFileSync(accelerationPath);
    const inconsistentAcceleration = loadJson(accelerationPath);
    inconsistentAcceleration.mode = "gpu-preferred";
    inconsistentAcceleration.nvidia.available = true;
    inconsistentAcceleration.ffmpeg.nvencEncoders = ["h264_nvenc"];
    inconsistentAcceleration.ffmpeg.usableNvencEncoders = ["h264_nvenc"];
    inconsistentAcceleration.selection.videoEncoder = "libx264";
    writeJson(accelerationPath, inconsistentAcceleration);
    const inconsistentAccelerationEvidence = structuredClone(evidencePackage);
    const inconsistentAccelerationArtifact = inconsistentAccelerationEvidence.artifacts.find((artifact) => artifact.artifactId === acceleration.artifactId);
    inconsistentAccelerationArtifact.sha256 = sha(accelerationPath);
    inconsistentAccelerationArtifact.bytes = statSync(accelerationPath).size;
    inconsistentAccelerationEvidence.provenance.render.accelerationManifest.sha256 = inconsistentAccelerationArtifact.sha256;
    writeJson(evidencePath, inconsistentAccelerationEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"), "--evidence-package", evidencePath, "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight rejects GPU-preferred mode when the selected execution paths are CPU-only");
    writeFileSync(accelerationPath, originalAcceleration);
    writeJson(evidencePath, evidencePackage);

    const missingCraftEvidence = structuredClone(evidencePackage);
    delete missingCraftEvidence.reports.craftContractValidation;
    writeJson(evidencePath, missingCraftEvidence);
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"),
      "--evidence-package", evidencePath,
      "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight fails closed when craft-contract validation is absent");
    writeJson(evidencePath, evidencePackage);

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
    ], { encoding: "utf8", env: process.env });
    assert(result.status === 1, "preflight rejects an unregistered deterministic-report generator even when hashes match");
    writeFileSync(asrPath, originalAsr);
    writeJson(evidencePath, evidencePackage);

    writeFileSync(join(root, media.artifactPath), "tampered", "utf8");
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "preflight.mjs"),
      "--evidence-package", evidencePath,
      "--out", preflightPath,
    ], { encoding: "utf8", env: process.env });
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

    const captionsPath = join(root, "captions.srt");
    const captionedVideoPath = join(root, "candidate-captioned.mp4");
    writeFileSync(captionsPath, "1\n00:00:00,100 --> 00:00:01,500\nSynthetic caption.\n", "utf8");
    result = spawnSync("ffmpeg", [
      "-v", "error",
      "-i", videoPath,
      "-i", captionsPath,
      "-map", "0:v",
      "-map", "0:a",
      "-map", "1:0",
      "-c:v", "copy",
      "-c:a", "copy",
      "-c:s", "mov_text",
      "-movflags", "+faststart",
      "-y",
      captionedVideoPath,
    ], { encoding: "utf8" });
    assert(result.status === 0, "FFmpeg generates the embedded-caption real-media fixture");

    const captionedEvidenceDir = join(root, "technical-captioned");
    result = spawnSync(process.execPath, [
      join(pluginDir, "scripts", "technical-checks.mjs"),
      "--video", captionedVideoPath,
      "--out", captionedEvidenceDir,
      "--report-only",
      "--json",
    ], { encoding: "utf8" });
    assert(result.status === 0, "technical checks accept valid media with an embedded subtitle stream");
    if (result.status === 0) {
      const captionedTechnical = loadJson(join(captionedEvidenceDir, "technical-report.json"));
      assert(
        captionedTechnical.pass === true &&
          captionedTechnical.checks.decodeIntegrity.status === "ok" &&
          captionedTechnical.checks.subtitleIntegrity.status === "ok" &&
          captionedTechnical.checks.subtitleIntegrity.streams === 1,
        "embedded subtitles are validated separately without corrupting the A/V decode gate",
      );
    }
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
    const executionRecords = createExecutionRecords(root);

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
            executionReceipt: executionRecords.recordReceipt({
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
          reviewIntegrity: createReviewIntegrity(root, domain, executionRecords),
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
    const editorialAudit = materializeEditorialAudit(root, candidate, {
      auditId: "PVEA-SYNTHETIC-RELEASE-001",
    });
    const editorialAuditPath = editorialAudit.path;
    const candidateAudioApproval = materializeCandidateAudioApproval(root, candidate, executionRecords, {
      fileStem: "release-candidate-audio",
      reportId: "PVAR-SYNTHETIC-RELEASE-001",
      adjudicationId: "PVAA-SYNTHETIC-RELEASE-001",
    });
    const decisionBase = {
      schemaVersion: "1.0.0",
      decisionId: "PVD-SYNTHETIC-RELEASE-001",
      candidate,
      arbiter: {
        contextId: "isolated-arbiter-context",
        readOnly: true,
        executionReceipt: executionRecords.recordReceipt({
          role: "arbiter",
          contextId: "isolated-arbiter-context",
          candidateId: candidate.candidateId,
          startedAt: "2026-07-29T22:02:00.000Z",
          completedAt: "2026-07-29T22:03:00.000Z",
        }),
      },
      policy: policyReference,
      preflight: { artifactPath: "preflight-report.json", sha256: sha(preflightPath) },
      editorialAudit: editorialAudit.reference,
      candidateAudioApproval: candidateAudioApproval.reference,
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
        env: { ...executionRecords.environment, ...passingEvidence.environment },
      });
    };

    let result = run(decisionBase);
    assert(result.status === 0, "release validator accepts a fully materialized PASS decision");
    if (result.status !== 0) {
      console.error(result.stdout);
      console.error(result.stderr);
    }

    const missingEditorialAudit = structuredClone(decisionBase);
    delete missingEditorialAudit.editorialAudit;
    result = run(missingEditorialAudit);
    assert(result.status === 1, "release validator rejects PASS without the candidate-bound orchestrator editorial audit");

    const staleEditorialAudit = structuredClone(decisionBase);
    const originalEditorialAudit = readFileSync(editorialAuditPath);
    const staleAuditDocument = loadJson(editorialAuditPath);
    staleAuditDocument.candidate.sha256 = "0".repeat(64);
    writeJson(editorialAuditPath, staleAuditDocument);
    staleEditorialAudit.editorialAudit.sha256 = sha(editorialAuditPath);
    staleEditorialAudit.editorialAudit.bytes = statSync(editorialAuditPath).size;
    result = run(staleEditorialAudit);
    assert(result.status === 1, "release validator rejects an editorial audit bound to different candidate bytes");
    writeFileSync(editorialAuditPath, originalEditorialAudit);

    const forgedPhaseEvidence = structuredClone(decisionBase);
    const forgedPhaseAudit = loadJson(editorialAuditPath);
    forgedPhaseAudit.phaseChecks[0].evidence[0].frameSha256 = "0".repeat(64);
    writeJson(editorialAuditPath, forgedPhaseAudit);
    forgedPhaseEvidence.editorialAudit.sha256 = sha(editorialAuditPath);
    forgedPhaseEvidence.editorialAudit.bytes = statSync(editorialAuditPath).size;
    result = run(forgedPhaseEvidence);
    assert(result.status === 1, "release validator rejects editorial phase evidence that does not match the decoded candidate frame");
    writeFileSync(editorialAuditPath, originalEditorialAudit);

    const missingAudioApproval = structuredClone(decisionBase);
    delete missingAudioApproval.candidateAudioApproval;
    result = run(missingAudioApproval);
    assert(result.status === 1, "release validator rejects PASS without local full-program audio perception and adjudication");

    const perceptionPath = candidateAudioApproval.report.path;
    const originalPerceptionReport = readFileSync(perceptionPath);
    const stalePerceptionDecision = structuredClone(decisionBase);
    const stalePerceptionReport = loadJson(perceptionPath);
    stalePerceptionReport.candidate.sha256 = "0".repeat(64);
    writeJson(perceptionPath, stalePerceptionReport);
    stalePerceptionDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    stalePerceptionDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(stalePerceptionDecision);
    assert(result.status === 1, "release validator rejects an audio-perception report bound to different candidate bytes");
    writeFileSync(perceptionPath, originalPerceptionReport);

    const incompleteCoverageDecision = structuredClone(decisionBase);
    const nativeReportPath = candidateAudioApproval.nativeReport.path;
    const originalNativeReport = readFileSync(nativeReportPath);
    const incompleteCoverageNativeReport = loadJson(nativeReportPath);
    incompleteCoverageNativeReport.decodedAudio.coverage.startSample = 1;
    writeJson(nativeReportPath, incompleteCoverageNativeReport);
    const incompleteCoverageReport = loadJson(perceptionPath);
    incompleteCoverageReport.listener.report.sha256 = sha(nativeReportPath);
    incompleteCoverageReport.listener.report.bytes = statSync(nativeReportPath).size;
    writeJson(perceptionPath, incompleteCoverageReport);
    incompleteCoverageDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    incompleteCoverageDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(incompleteCoverageDecision);
    assert(result.status === 1, "release validator rejects native decoded sample coverage that does not start at zero");
    writeFileSync(nativeReportPath, originalNativeReport);
    writeFileSync(perceptionPath, originalPerceptionReport);

    const remoteListenerDecision = structuredClone(decisionBase);
    const remoteListenerReport = loadJson(perceptionPath);
    remoteListenerReport.listener.kind = "human";
    remoteListenerReport.listener.localOnly = false;
    writeJson(perceptionPath, remoteListenerReport);
    remoteListenerDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    remoteListenerDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(remoteListenerDecision);
    assert(result.status === 1, "release validator rejects human or non-local listener labeling");
    writeFileSync(perceptionPath, originalPerceptionReport);

    const staleCalibrationDecision = structuredClone(decisionBase);
    const staleCalibrationReport = loadJson(perceptionPath);
    staleCalibrationReport.calibration.validUntil = "2026-07-29T21:59:59.000Z";
    writeJson(perceptionPath, staleCalibrationReport);
    staleCalibrationDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    staleCalibrationDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(staleCalibrationDecision);
    assert(result.status === 1, "release validator rejects stale audio-model calibration");
    writeFileSync(perceptionPath, originalPerceptionReport);

    const reusedCandidateReportDecision = structuredClone(decisionBase);
    const reusedCandidateReport = loadJson(perceptionPath);
    reusedCandidateReport.calibration.knownGood.nativeReport = reusedCandidateReport.listener.report;
    writeJson(perceptionPath, reusedCandidateReport);
    reusedCandidateReportDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    reusedCandidateReportDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(reusedCandidateReportDecision);
    assert(result.status === 1, "release validator rejects the candidate native report reused as independent known-good calibration");
    writeFileSync(perceptionPath, originalPerceptionReport);

    const missingKnownBadNativeDecision = structuredClone(decisionBase);
    const missingKnownBadNative = loadJson(perceptionPath);
    delete missingKnownBadNative.calibration.knownBad.nativeReport;
    writeJson(perceptionPath, missingKnownBadNative);
    missingKnownBadNativeDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    missingKnownBadNativeDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(missingKnownBadNativeDecision);
    assert(result.status === 1, "release validator rejects calibration without a known-bad native listen report");
    writeFileSync(perceptionPath, originalPerceptionReport);

    const knownGoodNativePath = candidateAudioApproval.knownGoodNativeReport.path;
    const originalKnownGoodNative = readFileSync(knownGoodNativePath);
    const wrongCalibrationPromptDecision = structuredClone(decisionBase);
    const wrongCalibrationPromptNative = loadJson(knownGoodNativePath);
    wrongCalibrationPromptNative.request.promptSha256 = "9".repeat(64);
    writeJson(knownGoodNativePath, wrongCalibrationPromptNative);
    const wrongCalibrationPromptReport = loadJson(perceptionPath);
    wrongCalibrationPromptReport.calibration.knownGood.nativeReport.sha256 = sha(knownGoodNativePath);
    wrongCalibrationPromptReport.calibration.knownGood.nativeReport.bytes = statSync(knownGoodNativePath).size;
    writeJson(perceptionPath, wrongCalibrationPromptReport);
    wrongCalibrationPromptDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    wrongCalibrationPromptDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(wrongCalibrationPromptDecision);
    assert(result.status === 1, "release validator rejects known-good calibration with different prompt provenance");
    writeFileSync(knownGoodNativePath, originalKnownGoodNative);
    writeFileSync(perceptionPath, originalPerceptionReport);

    const knownBadNativePath = candidateAudioApproval.knownBadNativeReport.path;
    const originalKnownBadNative = readFileSync(knownBadNativePath);
    const wrongCalibrationModelDecision = structuredClone(decisionBase);
    const wrongCalibrationModelNative = loadJson(knownBadNativePath);
    wrongCalibrationModelNative.model.revision = "different-model-revision";
    writeJson(knownBadNativePath, wrongCalibrationModelNative);
    const wrongCalibrationModelReport = loadJson(perceptionPath);
    wrongCalibrationModelReport.calibration.knownBad.nativeReport.sha256 = sha(knownBadNativePath);
    wrongCalibrationModelReport.calibration.knownBad.nativeReport.bytes = statSync(knownBadNativePath).size;
    writeJson(perceptionPath, wrongCalibrationModelReport);
    wrongCalibrationModelDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    wrongCalibrationModelDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(wrongCalibrationModelDecision);
    assert(result.status === 1, "release validator rejects known-bad calibration with different model provenance");
    writeFileSync(knownBadNativePath, originalKnownBadNative);
    writeFileSync(perceptionPath, originalPerceptionReport);

    const incompleteCalibrationDecodeDecision = structuredClone(decisionBase);
    const incompleteCalibrationDecodeNative = loadJson(knownGoodNativePath);
    incompleteCalibrationDecodeNative.decodedAudio.coverage.startSample = 1;
    writeJson(knownGoodNativePath, incompleteCalibrationDecodeNative);
    const incompleteCalibrationDecodeReport = loadJson(perceptionPath);
    incompleteCalibrationDecodeReport.calibration.knownGood.nativeReport.sha256 = sha(knownGoodNativePath);
    incompleteCalibrationDecodeReport.calibration.knownGood.nativeReport.bytes = statSync(knownGoodNativePath).size;
    writeJson(perceptionPath, incompleteCalibrationDecodeReport);
    incompleteCalibrationDecodeDecision.candidateAudioApproval.perceptionReport.sha256 = sha(perceptionPath);
    incompleteCalibrationDecodeDecision.candidateAudioApproval.perceptionReport.bytes = statSync(perceptionPath).size;
    result = run(incompleteCalibrationDecodeDecision);
    assert(result.status === 1, "release validator rejects known-good calibration without complete decoded sample provenance");
    writeFileSync(knownGoodNativePath, originalKnownGoodNative);
    writeFileSync(perceptionPath, originalPerceptionReport);

    const rawResponsePath = join(root, "release-candidate-audio-raw-response.txt");
    const originalRawResponse = readFileSync(rawResponsePath);
    writeFileSync(rawResponsePath, Buffer.concat([originalRawResponse, Buffer.from("\n")]), { flag: "w" });
    result = run(decisionBase);
    assert(result.status === 1, "release validator rejects raw local-model response byte tampering");
    writeFileSync(rawResponsePath, originalRawResponse);

    const adjudicationPath = candidateAudioApproval.adjudication.path;
    const originalAdjudication = readFileSync(adjudicationPath);
    const writableAdjudicationDecision = structuredClone(decisionBase);
    const writableAdjudication = loadJson(adjudicationPath);
    writableAdjudication.reviewer.readOnly = false;
    writeJson(adjudicationPath, writableAdjudication);
    writableAdjudicationDecision.candidateAudioApproval.adjudication.sha256 = sha(adjudicationPath);
    writableAdjudicationDecision.candidateAudioApproval.adjudication.bytes = statSync(adjudicationPath).size;
    result = run(writableAdjudicationDecision);
    assert(result.status === 1, "release validator rejects audio-perception adjudication from a writable reviewer context");
    writeFileSync(adjudicationPath, originalAdjudication);

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
      attempt: 1,
      findingFamilyFingerprint: shaBytes(Buffer.from(JSON.stringify([{
        category: "audio-captions-synchronization",
        fixClassification: "narration-audio",
      }]))),
      priorDecisions: [],
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
    const relabeledFamily = structuredClone(remediate);
    relabeledFamily.remediationPlan.findingFamilyFingerprint = "0".repeat(64);
    result = run(relabeledFamily);
    assert(result.status === 1, "release validator rejects a caller-renamed remediation family fingerprint");

    const thirdAutomatedAttempt = structuredClone(remediate);
    thirdAutomatedAttempt.remediationPlan.attempt = 3;
    result = run(thirdAutomatedAttempt);
    assert(result.status === 1, "release validator rejects attempt three without two immutable prior decision records");
    const relabeledSecondAttempt = structuredClone(remediate);
    relabeledSecondAttempt.remediationPlan.attempt = 2;
    result = run(relabeledSecondAttempt);
    assert(result.status === 1, "release validator rejects attempt two without an immutable prior decision lineage");

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
        executionReceipt: executionRecords.recordReceipt({
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
    failedPreflight.summary = { total: 20, passed: 19, failed: 1 };
    failedPreflight.status = "FAIL";
    failedPreflight.readyForIndependentReview = false;
    writeJson(failedPreflightPath, failedPreflight);
    const earlyPipelineBlocked = {
      schemaVersion: "1.0.0",
      decisionId: "PVD-SYNTHETIC-RELEASE-005",
      arbiter: {
        contextId: "isolated-pipeline-blocker-arbiter",
        readOnly: true,
        executionReceipt: executionRecords.recordReceipt({
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
    const executionRecords = createExecutionRecords(root);
    executionEnvironment = executionRecords.environment;
    const candidateId = "synthetic-publication-candidate-001";
    const passingEvidence = buildPassingEvidence(root, candidateId);
    executionEnvironment = { ...executionEnvironment, ...passingEvidence.environment };
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
          executionReceipt: executionRecords.recordReceipt({
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
        reviewIntegrity: createReviewIntegrity(root, domain, executionRecords),
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
    const generatorReasoningLeak = structuredClone(storyReport);
    generatorReasoningLeak.reviewIntegrity.generatorReasoningReceived = true;
    runInvalidReview(
      generatorReasoningLeak,
      "review validator rejects generator reasoning in an independent reviewer context",
    );
    const calibrationReferenceTamper = structuredClone(storyReport);
    calibrationReferenceTamper.reviewIntegrity.calibrationRecord.sha256 = "0".repeat(64);
    runInvalidReview(
      calibrationReferenceTamper,
      "review validator rejects reviewer-calibration checksum tampering",
    );
    const wrongContext = structuredClone(storyReport);
    wrongContext.reviewer.contextId = "different-review-context";
    runInvalidReview(wrongContext, "review validator rejects a receipt for a different context");
    const wrongCandidate = structuredClone(storyReport);
    wrongCandidate.candidate.candidateId = "different-candidate";
    runInvalidReview(wrongCandidate, "review validator rejects a receipt for a different candidate");
    const wrongDomain = structuredClone(storyReport);
    wrongDomain.reviewer.executionReceipt = executionRecords.recordReceipt({
      role: "reviewer",
      domain: "screen-accuracy-compliance",
      contextId: storyReport.reviewer.contextId,
      candidateId,
      startedAt: "2026-07-29T15:00:00.000Z",
      completedAt: "2026-07-29T15:05:00.000Z",
    });
    runInvalidReview(wrongDomain, "review validator rejects a receipt for a different review domain");
    const wrongRole = structuredClone(storyReport);
    wrongRole.reviewer.executionReceipt = executionRecords.recordReceipt({
      role: "arbiter",
      contextId: storyReport.reviewer.contextId,
      candidateId,
      startedAt: "2026-07-29T15:00:00.000Z",
      completedAt: "2026-07-29T15:05:00.000Z",
    });
    runInvalidReview(wrongRole, "review validator rejects a receipt for a different execution role");

    const decision = loadJson(join(fixtureDir, "release-decision.pass.json"));
    const policyPath = join(pluginDir, "policy", "product-video-policy.json");
    decision.candidate = candidateWithBytes;
    decision.arbiter.contextId = "isolated-publication-arbiter-context";
    decision.arbiter.executionReceipt = executionRecords.recordReceipt({
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
    const publicationEditorialAudit = materializeEditorialAudit(root, candidateWithBytes, {
      auditId: "PVEA-PUBLICATION-001",
      contextId: "orchestrator-publication-editorial-context",
      startedAt: "2026-07-29T15:04:00.000Z",
      completedAt: "2026-07-29T15:04:30.000Z",
    });
    decision.editorialAudit = publicationEditorialAudit.reference;
    const publicationAudioApproval = materializeCandidateAudioApproval(root, candidateWithBytes, executionRecords, {
      fileStem: "publication-candidate-audio",
      reportId: "PVAR-PUBLICATION-001",
      adjudicationId: "PVAA-PUBLICATION-001",
      contextId: "isolated-publication-audio-adjudicator-context",
      startedAt: "2026-07-29T15:03:30.000Z",
      completedAt: "2026-07-29T15:04:00.000Z",
      adjudicatedAt: "2026-07-29T15:04:30.000Z",
    });
    decision.candidateAudioApproval = publicationAudioApproval.reference;
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
        executionReceipt: executionRecords.recordReceipt({
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
        audioPerceptionApproval: true,
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

    const releaseEvidence = {
      schemaVersion: "3.0.0",
      candidateId,
      assetPath: "candidate.mp4",
      sha256: candidate.sha256,
      bytes: statSync(candidatePath).size,
      arbiterDecision: ref("release-decision.json"),
      finalVerification: ref("final-verification.json"),
    };
    const releasePath = join(root, "release-evidence.json");
    writeJson(releasePath, releaseEvidence);
    const publicationEnvironment = { ...executionEnvironment };
    expectCode(
      "check-evidence-gate.mjs",
      ["--manifest", releasePath],
      0,
      "automated release gate accepts the exact candidate and PASS review chain",
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
    assert(packageResult.status === 0, "video-cli package accepts only a validated PASS publication chain");
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

  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

{
  const policy = loadJson(join(pluginDir, "policy", "product-video-policy.json"));
  const ownerVoice = policy.ownerVoiceProductionPolicy;
  assert(ownerVoice?.canonicalTextMutationAllowed === false, "owner voice keeps canonical script text immutable");
  assert(ownerVoice?.phoneticRespellingAllowed === false, "owner voice forbids phonetic input respelling");
  assert(ownerVoice?.pronunciationRiskManifestRequired === true, "owner voice requires a pronunciation-risk manifest");
  assert(ownerVoice?.asrAloneMayApprovePronunciation === false, "ASR alone cannot approve owner-voice pronunciation");
  assert(ownerVoice?.properNounHomophoneStressAndAccentAudioPerceptionRequired === true, "ambiguous pronunciation requires local audio perception");
  assert(ownerVoice?.referenceAudio?.fullIclRequired === true && ownerVoice.referenceAudio.exactTranscriptRequired === true, "owner voice requires full ICL with an exact transcript");
  assert(ownerVoice?.segmentation?.arbitraryCharacterBlocksAllowed === false && ownerVoice.segmentation.timeStretchAllowed === false, "owner voice forbids arbitrary character chunks and time stretching");
  assert(ownerVoice?.postProcessing?.individualDynamicCompressionAllowed === false && ownerVoice.postProcessing.finalProgramTransparentTruePeakLimiterAllowed === true, "owner voice preserves raw takes while allowing transparent final mastering");
  assert(ownerVoice?.acceptance?.dualSpeakerIdentityGateRequired === true && ownerVoice.acceptance.audioPerceptionRequired === true,
    "owner voice requires dual identity scoring and local full-program audio perception");
  assert(ownerVoice?.acceptance?.listenerKind === "local-audio-model" &&
    ownerVoice.acceptance.audioPerceptionRoute === "ai.ps1 listen" &&
    ownerVoice.acceptance.localOnlyExecutionRequired === true &&
    ownerVoice.acceptance.humanPlaybackClaimAllowed === false &&
    ownerVoice.acceptance.ownerApprovalRequired === false,
    "owner-voice approval is system-owned, local-only, and never mislabeled as human playback");

  const narrationSkill = readFileSync(join(pluginDir, "pipeline", "product-demo-studio-narration", "SKILL.md"), "utf8");
  for (const requiredText of ["pronunciation-risk manifest", "resume", "canonical script", "ASR is a content check", "transparent true-peak limiter", "never time-stretch"]) {
    assert(narrationSkill.includes(requiredText), `narration skill documents ${requiredText}`);
  }
}

for (const schemaName of [
  "calibration-review-result.schema.json",
  "execution-receipt.schema.json",
  "video-finding.schema.json",
  "reviewer-calibration.schema.json",
  "review-report.schema.json",
  "release-decision.schema.json",
  "final-verification.schema.json",
  "release-evidence.schema.json",
  "remediation-assignment.schema.json",
  "delivery-spec.schema.json",
  "media-acceleration.schema.json",
  "deterministic-report.schema.json",
  "candidate-audio-perception-report.schema.json",
  "local-ai-listen-report.schema.json",
  "audio-perception-adjudication.schema.json",
  "editorial-audit.schema.json",
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
schemaFixture("reviewer-calibration.schema.json", "reviewer-calibration.pass.json", true);
schemaFixture("reviewer-calibration.schema.json", "reviewer-calibration.invalid.json", false);
schemaFixture("release-decision.schema.json", "release-decision.pass.json", true);
schemaFixture("release-decision.schema.json", "release-decision.remediate.json", true);
schemaFixture("release-decision.schema.json", "release-decision.invalid.json", false);
schemaFixture("candidate-audio-perception-report.schema.json", "candidate-audio-perception-report.pass.json", true);
schemaFixture("candidate-audio-perception-report.schema.json", "candidate-audio-perception-report.invalid.json", false);
schemaFixture("local-ai-listen-report.schema.json", "local-ai-listen-report.pass.json", true);
schemaFixture("local-ai-listen-report.schema.json", "local-ai-listen-report.invalid.json", false);
schemaFixture("audio-perception-adjudication.schema.json", "audio-perception-adjudication.pass.json", true);
schemaFixture("audio-perception-adjudication.schema.json", "audio-perception-adjudication.invalid.json", false);
schemaFixture("editorial-audit.schema.json", "editorial-audit.pass.json", true);
schemaFixture("editorial-audit.schema.json", "editorial-audit.invalid.json", false);
{
  const schemaPath = join(schemaDir, "release-decision.schema.json");
  const schema = loadSchema(schemaPath);
  const thirdAttempt = loadJson(join(fixtureDir, "release-decision.remediate.json"));
  thirdAttempt.remediationPlan.attempt = 3;
  thirdAttempt.remediationPlan.priorDecisions = [
    { artifactPath: "decisions/remediate-001.json", sha256: "1".repeat(64) },
    { artifactPath: "decisions/remediate-002.json", sha256: "2".repeat(64) },
  ];
  const errors = [];
  validate(schema, thirdAttempt, "$", schemaPath, schema, errors);
  if (errors.length) console.error(errors.join("\n"));
  assert(errors.length === 0, "release-decision schema permits attempt three with complete prior-decision lineage");
}
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
cli("validate-reviewer-calibration.mjs", "reviewer-calibration.invalid.json", 1);
cli("validate-release-decision.mjs", "release-decision.invalid.json", 1);
cli("validate-final-verification.mjs", "final-verification.invalid.json", 1);
cli("validate-remediation-assignment.mjs", "remediation-assignment.pass.json", 0);
cli("validate-remediation-assignment.mjs", "remediation-assignment.invalid.json", 1);
cli("validate-interactive-deep-dive.mjs", "interactive-deep-dive.pass.json", 0);
cli("validate-interactive-deep-dive.mjs", "interactive-deep-dive.invalid.json", 1);
externalWorkspaceIsolationIntegration();
screencastChoreographyIntegration();
reviewerCalibrationIntegration();
mediaAccelerationIntegration();
executionReceiptIntegration();
preflightIntegration();
realMediaIntegration();
videoCliGateIntegration();
releaseDecisionIntegration();
publicationIntegration();
reviewDeliveryIntegration();

console.log(`\n${assertions} assertion(s): ${failures} failure(s).`);
process.exit(failures === 0 ? 0 : 1);
