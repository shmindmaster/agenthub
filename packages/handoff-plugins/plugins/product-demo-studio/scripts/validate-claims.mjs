#!/usr/bin/env node
// Validates a product-claim ledger (JSON or this plugin's simple YAML-object-list shape) against
// the shape documented in skills/product-demo-studio-render/SKILL.md.
// Usage: node validate-claims.mjs <path-to-product-claims.yaml>
import { readManifestList } from "./lib.mjs";

// The six claim readiness classes from the Universal Demo Production Standard (§12 Claim integrity).
const READINESS_CLASSES = ["live", "synthetic", "reference-recorded", "background", "human-gated", "not-published"];

// Legacy values are accepted with a deprecation warning and mapped onto the six classes, so older
// ledgers don't hard-break. Use the six classes above in new ledgers.
const LEGACY_ALIASES = {
  "api-backed": "live",
  "synthetic-demo": "synthetic",
  sandbox: "synthetic",
  "draft-only": "not-published",
  preview: "not-published",
  roadmap: "not-published",
  "review-ready": "human-gated",
  "provider-gated": "human-gated",
  "human-approval-required": "human-gated",
};

// Classes whose claims are not plainly live and need an explicit disclaimer or exclusion.
const NEEDS_DISCLOSURE = new Set(["reference-recorded", "background", "human-gated", "not-published"]);

// `scene`/`segment` is the location field; require one of the two rather than both.
const REQUIRED_FIELDS = ["id", "text", "audience", "source", "readiness", "environment"];

const manifestPath = process.argv[2];
if (!manifestPath) {
  console.error("Usage: node validate-claims.mjs <path-to-product-claims.yaml>");
  process.exit(1);
}

const claims = readManifestList(manifestPath, "claims");
if (!claims || claims.length === 0) {
  console.error(`No claims found in ${manifestPath} (expected a top-level "claims:" list).`);
  process.exit(1);
}

let errorCount = 0;
let warningCount = 0;
const seenIds = new Set();

for (const [index, claim] of claims.entries()) {
  const label = claim.id ?? `#${index}`;
  const missing = REQUIRED_FIELDS.filter((field) => claim[field] === undefined || claim[field] === "");
  if (missing.length > 0) {
    console.error(`[error] ${label}: missing required field(s): ${missing.join(", ")}`);
    errorCount++;
  }

  if (!claim.scene && !claim.segment) {
    console.error(`[error] ${label}: missing a location -- set "scene" or "segment".`);
    errorCount++;
  }

  if (claim.id) {
    if (seenIds.has(claim.id)) {
      console.error(`[error] ${label}: duplicate claim id.`);
      errorCount++;
    }
    seenIds.add(claim.id);
  }

  let readiness = claim.readiness;
  if (readiness && LEGACY_ALIASES[readiness]) {
    console.warn(
      `[warn] ${label}: readiness "${readiness}" is a legacy value; use "${LEGACY_ALIASES[readiness]}" ` +
        "(Universal Demo Production Standard §12).",
    );
    warningCount++;
    readiness = LEGACY_ALIASES[readiness];
  }
  if (readiness && !READINESS_CLASSES.includes(readiness)) {
    console.error(
      `[error] ${label}: readiness "${claim.readiness}" is not one of: ${READINESS_CLASSES.join(", ")}.`,
    );
    errorCount++;
  }

  const shown = claim.visibleInCapture === true || claim.visibleOnScreen === true;

  // "not-published" claims must not appear on screen in a release; block it.
  if (readiness === "not-published" && shown) {
    console.error(
      `[error] ${label}: readiness "not-published" but the claim is shown on screen -- exclude it, ` +
        "or change its readiness before release.",
    );
    errorCount++;
  }

  if (readiness && NEEDS_DISCLOSURE.has(readiness) && !claim.disclaimer) {
    console.warn(
      `[warn] ${label}: readiness "${readiness}" is not plainly live and usually needs a "disclaimer" ` +
        "(or describe it as background behavior) -- add one, or confirm the claim should be excluded/adjusted.",
    );
    warningCount++;
  }

  // Unverified claims block release (Standard §12: unsupported/overstated claims block release).
  // A verdict + correctionNotes documents a claim that was checked and adjusted rather than left open.
  if (claim.verified === false && !claim.verdict) {
    console.error(
      `[error] ${label}: verified is false with no "verdict" -- verify the claim, record a verdict with ` +
        "correction notes, or exclude it. An unverified claim blocks release.",
    );
    errorCount++;
  }

  if ((claim.visibleInCapture === false || claim.visibleOnScreen === false) && !claim.disclaimer) {
    console.warn(
      `[warn] ${label}: not shown on screen with no disclaimer -- a claim not shown should usually be ` +
        "described as background behavior or excluded, not narrated as if seen.",
    );
    warningCount++;
  }
}

console.log(`\n${claims.length} claim(s) checked: ${errorCount} error(s), ${warningCount} warning(s).`);
process.exit(errorCount > 0 ? 1 : 0);
