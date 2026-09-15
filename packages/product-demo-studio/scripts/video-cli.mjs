#!/usr/bin/env node
// Single verb-based entry point for the product-demo-studio pipeline. Always invoked from the
// plugin against a target repo (`--repo <path>`) -- never installed into that repo.
//
// Usage: node video-cli.mjs <verb> --repo <path> [verb-specific options]
//
// Verbs: inventory | discover | readiness | storyboard | claims | reset | capture | voice |
//        render-proxy | frames | preflight | audio-perception | review | validate-review | arbitrate |
//        validate-decision | validate-assignment | qa | revise | render-candidate |
//        package-review | package | all
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { detectPackageManager, detectVideoConvention, readJson } from "./lib.mjs";

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const verb = args[0];
const rest = args.slice(1);

function flag(name, fromArgs = rest) {
  const i = fromArgs.indexOf(name);
  return i !== -1 ? fromArgs[i + 1] : undefined;
}

function runNode(scriptName, scriptArgs) {
  const result = spawnSync(process.execPath, [join(scriptsDir, scriptName), ...scriptArgs], {
    stdio: "inherit",
  });
  return result.status ?? 1;
}

/** Strip a --repo <value> pair out of an arg list, so it can be safely re-prepended once. */
function withoutRepoFlag(argList) {
  const out = [];
  for (let i = 0; i < argList.length; i++) {
    if (argList[i] === "--repo") {
      i++; // also skip its value
      continue;
    }
    out.push(argList[i]);
  }
  return out;
}

function withoutNamedValueFlags(argList, names) {
  const out = [];
  for (let i = 0; i < argList.length; i++) {
    if (names.has(argList[i])) {
      i++;
      continue;
    }
    out.push(argList[i]);
  }
  return out;
}

function requireRepo() {
  const repoPath = flag("--repo");
  if (!repoPath || !existsSync(repoPath)) {
    console.error(`Missing or invalid --repo <path> for the "${verb}" verb.`);
    process.exit(1);
  }
  return repoPath;
}

/** Find and run the package.json script under `dir` whose name best matches `keyword`. */
function runMatchingScript(dir, keyword, { list = false, explicitName } = {}) {
  const pkgPath = join(dir, "package.json");
  if (!existsSync(pkgPath)) {
    console.error(`No package.json at ${dir}.`);
    return 1;
  }
  const pkg = readJson(pkgPath);
  const matches = Object.keys(pkg.scripts ?? {}).filter((name) => name.includes(keyword));

  if (list || matches.length === 0) {
    console.log(`Scripts in ${pkgPath} matching "${keyword}":`);
    for (const name of matches) console.log(`  - ${name}: ${pkg.scripts[name]}`);
    if (matches.length === 0) {
      console.log(
        `(none found) -- this repo may not have a "${keyword}" step yet, or uses a different name. ` +
          "See the corresponding skill for how to add one, or run it manually.",
      );
      return list ? 0 : 1;
    }
    if (list) return 0;
  }

  const scriptName = explicitName ?? (matches.length === 1 ? matches[0] : undefined);
  if (!scriptName) {
    console.error(`Multiple "${keyword}" scripts exist -- pass --script to pick one. Available: ${matches.join(", ")}`);
    return 1;
  }
  if (!matches.includes(scriptName)) {
    console.error(`"${scriptName}" is not a "${keyword}" script in ${pkgPath}. Available: ${matches.join(", ")}`);
    return 1;
  }

  const packageManager = detectPackageManager(dir);
  console.log(`Running "${packageManager} run ${scriptName}" in ${dir} ...`);
  const result = spawnSync(packageManager, ["run", scriptName], {
    cwd: dir,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  return result.status ?? 1;
}

const VERBS = {
  inventory(repoPath) {
    return runNode("repo-registry.mjs", ["--repo", repoPath]);
  },

  discover(repoPath) {
    const signals = [
      ["AGENTS.md", "agent instructions"],
      ["README.md", "repo readme"],
      ["docs", "docs directory"],
      ["media", "media directory"],
      ["apps/videos", "video workspace"],
      ["playwright.config.ts", "Playwright config"],
      ["e2e", "e2e test directory"],
      ["tests/e2e", "e2e test directory"],
    ];
    console.log(`Discovery scan of ${repoPath}:`);
    for (const [relPath, label] of signals) {
      const full = join(repoPath, relPath);
      console.log(`  - ${label}: ${existsSync(full) ? full : "not found"}`);
    }
    console.log(`\nAlso run: node ${join(scriptsDir, "repo-registry.mjs")} --repo ${repoPath}`);
    return 0;
  },

  claims() {
    const manifestPath = flag("--claims");
    if (!manifestPath) {
      console.error('The "claims" verb needs --claims <path-to-product-claims.yaml>.');
      return 1;
    }
    return runNode("validate-claims.mjs", [manifestPath]);
  },

  readiness() {
    const manifestPath = flag("--readiness");
    if (!manifestPath) {
      console.error('The "readiness" verb needs --readiness <path-to-readiness.json>.');
      return 1;
    }
    return runNode("validate-demo-readiness.mjs", [manifestPath]);
  },

  storyboard() {
    const manifestPath = flag("--storyboard");
    if (!manifestPath) {
      console.error('The "storyboard" verb needs --storyboard <path-to-storyboard.json>.');
      return 1;
    }
    return runNode("validate-storyboard.mjs", [manifestPath]);
  },

  reset(repoPath) {
    const detection = detectVideoConvention(repoPath);
    const dir = detection.remotionDir ?? repoPath;
    return runMatchingScript(dir, "reset", { list: rest.includes("--list"), explicitName: flag("--script") });
  },

  capture(repoPath) {
    const detection = detectVideoConvention(repoPath);
    const dir = detection.remotionDir ?? repoPath;
    return runMatchingScript(dir, "capture", { list: rest.includes("--list"), explicitName: flag("--script") });
  },

  voice() {
    return runNode("generate-narration.mjs", rest);
  },

  "render-proxy"(repoPath) {
    return runNode("render-videos.mjs", ["--repo", repoPath, ...withoutRepoFlag(rest)]);
  },

  "render-candidate"(repoPath) {
    return runNode("render-videos.mjs", ["--repo", repoPath, ...withoutRepoFlag(rest)]);
  },

  "package-review"(repoPath) {
    return runNode("package-review.mjs", ["--repo", repoPath, ...withoutRepoFlag(rest)]);
  },

  "render-final"() {
    console.error(
      'The "render-final" verb was removed because a post-verification rerender invalidates the accepted bytes. ' +
        "Use `render-candidate` before evidence generation, independent review, arbitration, final verification, " +
        "and automated acceptance. Any later media change creates a new candidate and restarts those checks.",
    );
    return 2;
  },

  frames() {
    return runNode("technical-checks.mjs", rest);
  },

  preflight() {
    const evidencePackage = flag("--evidence-package");
    const outPath = flag("--out");
    if (!evidencePackage || !outPath) {
      console.error('Usage: video-cli.mjs preflight --evidence-package <package.json> --out <report.json>');
      return 1;
    }
    return runNode("preflight.mjs", ["--evidence-package", evidencePackage, "--out", outPath]);
  },

  "audio-perception"() {
    const candidatePath = flag("--candidate");
    const outPath = flag("--out");
    const candidateId = flag("--candidate-id");
    const sourceRevision = flag("--source-revision");
    const renderProvenanceId = flag("--render-provenance-id");
    const transcript = flag("--transcript");
    const pronunciationManifest = flag("--pronunciation-manifest");
    if (!candidatePath || !outPath || !candidateId || !sourceRevision || !renderProvenanceId) {
      console.error(
        "Usage: video-cli.mjs audio-perception --candidate <encoded-video> --out <native-listen-report.json> " +
        "--candidate-id <id> --source-revision <revision> --render-provenance-id <id> " +
        "[--transcript <path>] [--pronunciation-manifest <path>]",
      );
      return 1;
    }
    const absoluteCandidate = resolve(candidatePath);
    const absoluteOut = resolve(outPath);
    if (!existsSync(absoluteCandidate)) {
      console.error(`Candidate does not exist: ${absoluteCandidate}`);
      return 1;
    }
    const localAiRoot = process.env.LOCAL_AI_ROOT || "D:\\Local-AI";
    const controlPlane = join(localAiRoot, "ai.ps1");
    if (!existsSync(controlPlane)) {
      console.error(`Local-AI control plane does not exist: ${controlPlane}`);
      return 1;
    }
    const command = [
      "$ErrorActionPreference = 'Stop'",
      "$listenArgs = @('listen', $env:PDS_AUDIO_CANDIDATE, '--output', $env:PDS_AUDIO_REPORT, '--candidate-id', $env:PDS_AUDIO_CANDIDATE_ID, '--source-revision', $env:PDS_AUDIO_SOURCE_REVISION, '--render-provenance-id', $env:PDS_AUDIO_RENDER_PROVENANCE_ID)",
      "if ($env:PDS_AUDIO_TRANSCRIPT) { $listenArgs += @('--transcript', $env:PDS_AUDIO_TRANSCRIPT) }",
      "if ($env:PDS_AUDIO_PRONUNCIATION_MANIFEST) { $listenArgs += @('--pronunciation-manifest', $env:PDS_AUDIO_PRONUNCIATION_MANIFEST) }",
      "& $env:PDS_LOCAL_AI_CONTROL @listenArgs",
    ].join("; ");
    const result = spawnSync("pwsh", ["-NoProfile", "-Command", command], {
      stdio: "inherit",
      env: {
        ...process.env,
        PDS_LOCAL_AI_CONTROL: controlPlane,
        PDS_AUDIO_CANDIDATE: absoluteCandidate,
        PDS_AUDIO_REPORT: absoluteOut,
        PDS_AUDIO_CANDIDATE_ID: candidateId,
        PDS_AUDIO_SOURCE_REVISION: sourceRevision,
        PDS_AUDIO_RENDER_PROVENANCE_ID: renderProvenanceId,
        PDS_AUDIO_TRANSCRIPT: transcript ? resolve(transcript) : "",
        PDS_AUDIO_PRONUNCIATION_MANIFEST: pronunciationManifest ? resolve(pronunciationManifest) : "",
      },
    });
    if ((result.status ?? 1) !== 0) return result.status ?? 1;
    if (!existsSync(absoluteOut)) {
      console.error(`ai.ps1 listen exited successfully but did not create the report: ${absoluteOut}`);
      return 1;
    }
    console.log(`Wrote immutable native ai.ps1 listen report: ${absoluteOut}`);
    return 0;
  },

  review() {
    console.error(
      'The "review" verb is dispatch guidance, not a release gate, and intentionally exits nonzero.\n' +
      "Dispatch four isolated read-only reviewers against the same immutable candidate and evidence package:\n" +
        "  - agents/story-experience-reviewer.agent.md\n" +
        "  - agents/screen-accuracy-compliance-reviewer.agent.md\n" +
        "  - agents/audio-captions-sync-reviewer.agent.md\n" +
        "  - agents/technical-frame-integrity-reviewer.agent.md\n" +
        "The audio reviewer also adjudicates the immutable ai.ps1 listen report using schemas/audio-perception-adjudication.schema.json. " +
        "Each domain output must conform to schemas/review-report.schema.json. If host capacity is lower than " +
        "four, use fresh isolated waves; never collapse the domains.",
    );
    return 2;
  },

  "validate-review"() {
    const reportPath = flag("--report") ?? rest.find((arg) => !arg.startsWith("--"));
    if (!reportPath) {
      console.error("Usage: video-cli.mjs validate-review --report <review-report.json>");
      return 1;
    }
    return runNode("validate-review-report.mjs", [reportPath]);
  },

  arbitrate() {
    console.error(
      'The "arbitrate" verb is dispatch guidance, not a release gate, and intentionally exits nonzero.\n' +
      "After preflight, local audio perception, its isolated read-only adjudication, and exactly four schema-valid reviews, dispatch agents/release-arbiter.agent.md " +
        "in a fresh read-only context. Validate its output with `validate-decision`.",
    );
    return 2;
  },

  "validate-decision"() {
    const decisionPath = flag("--decision") ?? rest.find((arg) => !arg.startsWith("--"));
    if (!decisionPath) {
      console.error("Usage: video-cli.mjs validate-decision --decision <release-decision.json>");
      return 1;
    }
    return runNode("validate-release-decision.mjs", [decisionPath]);
  },

  "validate-assignment"() {
    const assignmentPath = flag("--assignment") ?? rest.find((arg) => !arg.startsWith("--"));
    if (!assignmentPath) {
      console.error("Usage: video-cli.mjs validate-assignment --assignment <remediation-assignment.json>");
      return 1;
    }
    return runNode("validate-remediation-assignment.mjs", [assignmentPath]);
  },

  qa() {
    const evidencePackage = flag("--evidence-package");
    const preflightOut = flag("--preflight-out");
    const status = evidencePackage && preflightOut
      ? runNode("preflight.mjs", ["--evidence-package", evidencePackage, "--out", preflightOut])
      : runNode("technical-checks.mjs", rest);
    if (status !== 0) return status;
    console.error(
      "\nDeterministic checks passed, but QA is not complete. This orchestration verb intentionally " +
        "exits nonzero until independent outputs are validated. Resolve PRODUCT_DEMO_STUDIO_ROOT and run four independent " +
        "read-only reviewer passes from agents/:\n" +
        "  - story-experience-reviewer.md\n" +
        "  - screen-accuracy-compliance-reviewer.md\n" +
        "  - audio-captions-sync-reviewer.md\n" +
        "  - technical-frame-integrity-reviewer.md\n" +
        "Validate every report, then dispatch release-arbiter.md in a fresh read-only context. " +
        "See product-demo-studio-qa for the immutable evidence, remediation, rerender, and mandatory terminal independent reviewer/verifier loop.",
    );
    return 2;
  },

  revise() {
    console.error(
      'The "revise" verb is guidance, not proof of remediation, and intentionally exits nonzero. ' +
        "Applying a review-loop revision means editing the " +
        "actual composition, capture manifest, or claim ledger (selected external finisher / " +
        "-capture / -render), then re-running `render-proxy` and `qa`. See product-demo-studio-qa's " +
        "\"apply, rerender, repeat\" step.",
    );
    return 2;
  },

  package(repoPath) {
    const outPath = flag("--out");
    const decisionPath = flag("--decision");
    const finalVerificationPath = flag("--final-verification");
    const releaseEvidencePath = flag("--release-evidence");
    const files = withoutRepoFlag(withoutNamedValueFlags(rest, new Set([
      "--out",
      "--decision",
      "--final-verification",
      "--release-evidence",
    ]))).filter((a) => !a.startsWith("--"));
    if (files.length === 0 || !outPath || !decisionPath || !finalVerificationPath || !releaseEvidencePath) {
      console.error(
        "Usage: video-cli.mjs package --repo <path> --out <bundle.json> " +
          "--decision <release-decision.json> --final-verification <final-verification.json> " +
          "--release-evidence <release-evidence.json> <approved-file...>",
      );
      return 1;
    }
    for (const requiredPath of [decisionPath, finalVerificationPath, releaseEvidencePath, ...files]) {
      if (!existsSync(requiredPath)) {
        console.error(`Required package input does not exist: ${requiredPath}`);
        return 1;
      }
    }
    for (const [script, scriptArgs, path] of [
      ["validate-release-decision.mjs", [decisionPath], decisionPath],
      ["validate-final-verification.mjs", [finalVerificationPath], finalVerificationPath],
      ["check-evidence-gate.mjs", ["--manifest", releaseEvidencePath], releaseEvidencePath],
    ]) {
      const status = runNode(script, scriptArgs);
      if (status !== 0) {
        console.error(`Packaging blocked because ${script} rejected ${path}.`);
        return status;
      }
    }
    const decision = readJson(resolve(decisionPath));
    if (decision.decision !== "PASS") {
      console.error(`Packaging requires an arbiter PASS; received ${decision.decision ?? "<missing>"}.`);
      return 1;
    }
    const entries = files.map((file) => {
      const absolutePath = resolve(file);
      const bytes = readFileSync(absolutePath);
      return {
        path: absolutePath,
        bytes: bytes.length,
        sha256: createHash("sha256").update(bytes).digest("hex"),
      };
    });
    writeFileSync(outPath, `${JSON.stringify({
      schemaVersion: "1.0.0",
      candidateId: decision.candidate?.candidateId ?? null,
      generatedFrom: resolve(repoPath),
      gates: {
        releaseDecision: resolve(decisionPath),
        finalVerification: resolve(finalVerificationPath),
        releaseEvidence: resolve(releaseEvidencePath),
      },
      files: entries,
    }, null, 2)}\n`);
    console.log(`Wrote deliverable checksum bundle: ${outPath} (${entries.length} file(s))`);
    return 0;
  },

  all(repoPath) {
    console.error(
      'The "all" verb is an orchestration checklist, not a release gate, and intentionally exits nonzero.\n' +
        `The full pipeline for ${repoPath} is not a single mechanical command -- composing, ` +
        "assessing, narrating, and reviewing a video need real judgment at each stage. Run these in order, " +
        "reading each result before moving to the next:\n\n" +
        `  1. inventory     node video-cli.mjs inventory --repo ${repoPath}\n` +
        "  2. (candidates)  product-demo-studio + product-demo-studio-render -- propose focused episodes\n" +
        "  3. readiness     node video-cli.mjs readiness --readiness <readiness.json>\n" +
        "     FAIL          stop that episode and deliver <WORK_DIR>/feedback; do not render it\n" +
        "  4. storyboard    node video-cli.mjs storyboard --storyboard <storyboard.json>\n" +
        "  5. claims        node video-cli.mjs claims --claims <product-claims.yaml>\n" +
        `  6. voice         node video-cli.mjs voice --script <path> --out <dir>\n` +
        `  7. capture       node video-cli.mjs capture --repo ${repoPath}\n` +
        "  8. (compose)     selected external finisher; official Remotion plugin only if justified\n" +
        `  9. render-proxy  node video-cli.mjs render-proxy --repo ${repoPath} (draft iteration only)\n` +
        `  10. render-candidate node video-cli.mjs render-candidate --repo ${repoPath}\n` +
        "      Freeze the candidate bytes. Every later media/source change creates a new candidate.\n" +
        "  11. evidence-package build immutable evidence-package.json from that exact candidate\n" +
        "  12. preflight     node video-cli.mjs preflight --evidence-package <package.json> --out <preflight.json>\n" +
        "  13. audio-perception node video-cli.mjs audio-perception --candidate <candidate> --out <native-listen-report.json> --candidate-id <id> --source-revision <revision> --render-provenance-id <id>\n" +
        "      Run the same command independently for known-good and known-bad calibration audio; envelope all three distinct immutable native reports with the shared local model receipt and prompt provenance.\n" +
        "  14. review        dispatch four isolated reviewers; the audio reviewer also adjudicates the audio report\n" +
        "  15. arbitrate     dispatch a fresh release arbiter; validate its decision\n" +
        "  16. remediate     if required, use least-privilege assignments and restart at step 9\n" +
        "  17. final-verifier dispatch the mandatory terminal independent reviewer/verifier in a fresh read-only context against the unchanged candidate\n" +
        `  18. package-review node video-cli.mjs package-review --repo ${repoPath} ` +
          "--delivery-registry <AgentHub>/registry/product-video-delivery.json " +
          "--decision <decision.json> --final-verification <final.json> [--artifact <review-file> ...]\n" +
        "      This creates an immutable review-only package in the product's configured private OneDrive folder.\n" +
        `  19. package       node video-cli.mjs package --repo ${repoPath} --out bundle.json ` +
          "--decision <decision.json> --final-verification <final.json> " +
          "--release-evidence <release-evidence.json> <accepted-file...>\n" +
        "No render or edit is allowed after verification; any change restarts at render-candidate.",
    );
    return 2;
  },
};

if (!verb || !VERBS[verb]) {
  console.error(`Usage: node video-cli.mjs <verb> --repo <path> [options]\nVerbs: ${Object.keys(VERBS).join(" | ")}`);
  process.exit(1);
}

const repoPath = [
  "readiness", "storyboard", "claims", "voice", "frames", "preflight", "audio-perception", "review",
  "validate-review", "arbitrate", "validate-decision", "validate-assignment", "qa", "revise",
].includes(verb)
  ? flag("--repo")
  : requireRepo();
process.exit(VERBS[verb](repoPath));
