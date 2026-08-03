#!/usr/bin/env node
// Build the worthiness fixture catalog and one expected demo-readiness sheet per
// fixture, in the shape `validate-demo-readiness.mjs` already accepts.
//
// These fixtures are running applications, not rendered masters. The worthiness
// assessment walks a live product, so a video fixture cannot exercise it — the
// two calibration sets are not interchangeable.
//
// Usage: node build-worthiness-fixtures.mjs [--apps <dir>] [--out <dir>]

import { writeFileSync, mkdirSync, readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const arg = (f, d) => {
  const i = argv.indexOf(f);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : d;
};
const APPS = resolve(arg("--apps", join(here, "..", "fixtures", "worthiness", "apps")));
const OUT = resolve(arg("--out", join(here, "..", "fixtures", "worthiness")));

const CRITERIA = [
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

const BASE_EVIDENCE = {
  "single-clear-outcome": "frame:reconciliation-complete",
  "fast-to-value": "timing:value-at-00:02",
  "clean-believable-states": "frame:success-state",
  "visual-stability": "trace:no-layout-shift",
  "legibility": "frame:result-headline-at-product-scale",
  "bounded-feedback-rich-waits": "timing:progress-1.9s",
  "discoverable-primary-action": "frame:reconcile-button",
  "deterministic-resettable": "trace:second-walk-identical",
  "visible-guardrail": "frame:human-approval-required",
  "hero-moment-exists": "frame:127-of-127-matched",
  "polish-baseline": "contact-sheet:northwind-ledger",
};

const FIXTURES = {
  "clean-pass": {
    verdict: "PASS",
    workflow: "Reconcile December invoices against the bank feed",
    fails: {},
    planted: "None. Determinate progress, ~1.9s wait, legible result, visible human-approval guardrail.",
    captureFixes: [],
    measured: "result at 1896ms with a determinate progress bar",
  },

  "dead-wait": {
    verdict: "FAIL",
    workflow: "Reconcile December invoices against the bank feed",
    fails: {
      "bounded-feedback-rich-waits": {
        classification: "product-fix-required",
        severity: "blocks",
        evidence: "timing:6398ms-no-feedback-after-reconcile",
        finding: "6.4s elapses after Reconcile with no spinner, progress indicator, or state change.",
        viewerImpact:
          "The viewer watches a frozen screen for six seconds and concludes the product is slow. Cutting the wait does not help — it leaves a cut where a result should have appeared.",
        fix: "Add a determinate progress indicator to the Reconcile action.",
      },
    },
    planted: "Identical to clean-pass with every progress affordance removed.",
    captureFixes: [],
    measured: "result at 6398ms with no visible feedback",
    shortestPath:
      "Add the determinate progress indicator to the Reconcile action. That single fix moves this episode from FAIL to PASS.",
  },

  illegible: {
    verdict: "CONDITIONAL",
    workflow: "Reconcile December invoices and review the column breakdown",
    fails: {
      legibility: {
        classification: "capture-fixable",
        severity: "degrades",
        evidence: "frame:results-grid-9px",
        finding: "Results render at 9px across 12 columns; the headline figure is 10px at low contrast.",
        fix: "Punch in to 2.0x on the results region at capture. No product change required.",
      },
    },
    planted: "Results at 9px in a 12-column grid; key figure 10px, low contrast.",
    captureFixes: ["Punch in to 2.0x on the results region for the payoff beat."],
    measured: "result at 847ms; body text 9px, headline 10px",
  },

  unstable: {
    verdict: "FAIL",
    workflow: "Reconcile December invoices against the bank feed",
    fails: {
      "visual-stability": {
        classification: "product-fix-required",
        severity: "blocks",
        evidence: "trace:banner-injected-at-900ms",
        finding:
          "A banner injects 900ms after load and shifts all content down. The results table overflows its card and clips the final column.",
        viewerImpact:
          "Content jumps under the cursor mid-shot and the payoff column is clipped out of frame, so the result the video is built around is never fully visible.",
        fix: "Reserve layout space for the freeze banner before first paint; constrain the results table to its container with horizontal scroll.",
      },
    },
    planted: "Post-load banner injection shifts content; results table overflows and clips.",
    captureFixes: [],
    measured: "layout shift at 900ms; table width 1500px inside a 940px container",
    shortestPath:
      "Reserve the banner space before first paint, then constrain the results table. The first fix alone moves the episode to CONDITIONAL; both move it to PASS.",
  },

  "no-hero": {
    verdict: "FAIL",
    workflow: "Update notification preferences and save",
    fails: {
      "hero-moment-exists": {
        classification: "product-fix-required",
        severity: "blocks",
        evidence: "frame:preferences-saved",
        finding:
          "The flow is clean, fast, legible, stable and has a visible guardrail. It contains no reveal worth building a video around — saving a form is the product working as specified.",
        viewerImpact:
          "There is no moment where a viewer leans in. The video would be accurate and forgettable — the exact defect the two-outcome model exists to prevent.",
        fix: "This workflow is not demo-worthy. Select a different flow, or add a capability to this one that produces a result a viewer would not expect.",
      },
    },
    planted: "Nothing is broken. There is simply nothing worth filming.",
    captureFixes: [],
    measured: "result at 67ms; no state change a viewer would find surprising",
    shortestPath:
      "No product fix makes this workflow demo-worthy. Select a different flow, or add a capability with a genuine reveal.",
    heroOverride: "Preferences saved",
  },
};

const ENVIRONMENT = "synthetic-fixture";
const REVISION = "0000000000000000";
const PERSONA = "controller";
const PERMISSIONS = ["ledger:read", "ledger:reconcile"];

const sha256 = (p) => createHash("sha256").update(readFileSync(p)).digest("hex");

function treeHash(dir) {
  const h = createHash("sha256");
  const walk = (d, prefix = "") => {
    for (const name of readdirSync(d).sort()) {
      const full = join(d, name);
      if (statSync(full).isDirectory()) walk(full, `${prefix}${name}/`);
      else h.update(`${prefix}${name}\u0000`).update(readFileSync(full));
    }
  };
  walk(dir);
  return h.digest("hex");
}

if (!existsSync(APPS)) {
  console.error(`Fixture apps not found at ${APPS}`);
  process.exit(2);
}

mkdirSync(OUT, { recursive: true });
const entries = [];

for (const [id, spec] of Object.entries(FIXTURES)) {
  const appDir = join(APPS, id);
  if (!existsSync(appDir)) {
    console.error(`missing app: ${appDir}`);
    process.exit(2);
  }

  const criteria = CRITERIA.map((c) => {
    const f = spec.fails[c];
    return f
      ? { id: c, passed: false, evidence: [f.evidence], classification: f.classification }
      : {
          id: c,
          passed: true,
          evidence: [c === "hero-moment-exists" && spec.heroOverride ? `frame:${spec.heroOverride.toLowerCase().replace(/\s+/g, "-")}` : BASE_EVIDENCE[c]],
        };
  });

  // The upstream handoff always says DEMO-READY with all eleven criteria passing.
  // That is deliberate: these fixtures test whether the video-side assessment
  // will independently disagree with an upstream PROCEED. A fixture where the
  // handoff already flagged the defect would prove nothing.
  const handoff = {
    assessmentOwner: "product-experience-engineering",
    assessedRevision: REVISION,
    assessedEnvironment: ENVIRONMENT,
    workflow: spec.workflow,
    persona: PERSONA,
    permissions: [...PERMISSIONS],
    heroMoment: spec.heroOverride ?? "127 of 127 ledger lines matched in one action.",
    handoffPath: "_product-experience/07-demo-readiness-handoff.md",
    afterVerdict: "DEMO-READY",
    handoffDecision: "PROCEED",
    seedProfile: {
      fixture: `synthetic-${id}`,
      seedCommand: `node scripts/serve-worthiness-fixtures.mjs # serves ${id}`,
      resetCommand: "reload the page; fixtures are stateless and served no-store",
    },
    criteria: CRITERIA.map((c) => ({ id: c, passed: true, evidence: [BASE_EVIDENCE[c]] })),
  };

  const readiness = {
    episodeId: `calibration-${id}`,
    workflow: spec.workflow,
    assessedEnvironment: ENVIRONMENT,
    assessedRevision: REVISION,
    persona: PERSONA,
    permissions: [...PERMISSIONS],
    verdict: spec.verdict,
    productExperienceHandoff: handoff,
    criteria,
    captureFixes: spec.captureFixes,
    productFixes: Object.entries(spec.fails)
      .filter(([, f]) => f.classification === "product-fix-required")
      .map(([criterion, f]) => ({
        id: `PVF-CAL-${id.toUpperCase().replace(/[^A-Z0-9]/g, "")}-001`,
        principle: criterion,
        observedBehavior: f.finding,
        viewerImpact: f.viewerImpact,
        suggestedFix: f.fix,
        evidence: [f.evidence],
        severity: f.severity,
      })),
  };

  if (spec.verdict === "FAIL") {
    readiness.feedbackPath = `evidence/calibration/${id}/product-readiness-feedback.md`;
    readiness.shortestPathToReady = spec.shortestPath;
  }

  const readinessPath = join(OUT, `${id}.expected-readiness.json`);
  writeFileSync(readinessPath, JSON.stringify(readiness, null, 2) + "\n");

  entries.push({
    id,
    urlPath: `/${id}/`,
    expectedVerdict: spec.verdict,
    plantedDefect: spec.planted,
    measured: spec.measured,
    mustTrip: Object.entries(spec.fails).map(([criterion, f]) => ({
      criterion,
      classification: f.classification,
      severity: f.severity,
      finding: f.finding,
      suggestedFix: f.fix,
    })),
    app: { artifactPath: `fixtures/worthiness/apps/${id}/index.html`, sha256: sha256(join(appDir, "index.html")) },
    expectedReadiness: { artifactPath: `fixtures/worthiness/${id}.expected-readiness.json`, sha256: sha256(readinessPath) },
  });

  console.log(`${id.padEnd(12)} ${spec.verdict.padEnd(11)} ${Object.keys(spec.fails)[0] ?? "-"}`);
}

writeFileSync(
  join(OUT, "catalog.json"),
  JSON.stringify(
    {
      schemaVersion: "1.0.0",
      set: "worthiness",
      note: "Worthiness calibration fixtures are running applications, not rendered masters. The assessment walks a live product, so a video fixture cannot exercise it. Serve with scripts/serve-worthiness-fixtures.mjs.",
      criterionVocabulary: CRITERIA,
      servePort: 8977,
      treeSha256: treeHash(APPS),
      fixtures: entries,
    },
    null,
    2,
  ) + "\n",
);
console.log(`\ncatalog: ${join(OUT, "catalog.json")}`);
