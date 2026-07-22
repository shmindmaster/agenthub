#!/usr/bin/env node
// Single verb-based entry point for the product-demo-studio pipeline. Always invoked from the
// plugin against a target repo (`--repo <path>`) -- never installed into that repo.
//
// Usage: node video-cli.mjs <verb> --repo <path> [verb-specific options]
//
// Verbs: inventory | discover | readiness | storyboard | claims | reset | capture | voice |
//        render-proxy | frames | qa | revise | render-final | package | all
import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
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

  "render-final"(repoPath) {
    return runNode("render-videos.mjs", ["--repo", repoPath, ...withoutRepoFlag(rest)]);
  },

  frames() {
    return runNode("technical-checks.mjs", rest);
  },

  qa() {
    const status = runNode("technical-checks.mjs", rest);
    if (status !== 0) return status;
    console.log(
      "\nTechnical checks complete. Resolve PRODUCT_DEMO_STUDIO_ROOT and run five independent " +
        "read-only reviewer passes from agents/:\n" +
        "  - product-truth-reviewer.md\n" +
        "  - story-reviewer.md\n" +
        "  - visual-reviewer.md\n" +
        "  - audio-reviewer.md\n" +
        "  - technical-reviewer.md\n" +
        "Use packaged named agents when available; otherwise create equivalent reviewer/subagents " +
        "from these files, or five isolated passes when subagents are unavailable.\n" +
        "Give each the proxy video path, the frames/contact-sheet output above, the technical " +
        "report, the render/capture manifests, and the product-claim ledger. See " +
        "product-demo-studio-qa for the full loop and the revision JSON shape.",
    );
    return status;
  },

  revise() {
    console.log(
      "This verb is guidance, not automation -- applying a review-loop revision means editing the " +
        "actual composition, capture manifest, or claim ledger (product-demo-studio-remotion / " +
        "-capture / -render), then re-running `render-proxy` and `qa`. See product-demo-studio-qa's " +
        "\"apply, rerender, repeat\" step.",
    );
    return 0;
  },

  package(repoPath) {
    const outPath = flag("--out");
    const withoutOut = (() => {
      const out = [];
      for (let i = 0; i < rest.length; i++) {
        if (rest[i] === "--out") { i++; continue; }
        out.push(rest[i]);
      }
      return out;
    })();
    const files = withoutRepoFlag(withoutOut).filter((a) => !a.startsWith("--"));
    if (files.length === 0 || !outPath) {
      console.error('Usage: video-cli.mjs package --repo <path> --out <bundle.json> <file...>');
      return 1;
    }
    const entries = files.map((file) => {
      if (!existsSync(file)) {
        console.error(`File not found, skipping: ${file}`);
        return null;
      }
      return { path: file, sha256: createHash("sha256").update(readFileSync(file)).digest("hex") };
    }).filter(Boolean);
    writeFileSync(outPath, JSON.stringify({ generatedFrom: repoPath, files: entries }, null, 2));
    console.log(`Wrote deliverable checksum bundle: ${outPath} (${entries.length} file(s))`);
    return 0;
  },

  all(repoPath) {
    console.log(
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
        "  8. (compose)     product-demo-studio-remotion skill\n" +
        `  9. render-proxy  node video-cli.mjs render-proxy --repo ${repoPath}\n` +
        `  10. qa            node video-cli.mjs qa --video <proxy.mp4> --out <qa-dir>\n` +
        "  11. (revise, repeat 9-10; route late product UX failures to feedback)\n" +
        `  12. render-final  node video-cli.mjs render-final --repo ${repoPath}\n` +
        `  13. package       node video-cli.mjs package --repo ${repoPath} --out bundle.json <files...>\n` +
        "  14. (evidence gate + optional Descript finish) product-demo-studio-render, product-demo-studio-descript",
    );
    return 0;
  },
};

if (!verb || !VERBS[verb]) {
  console.error(`Usage: node video-cli.mjs <verb> --repo <path> [options]\nVerbs: ${Object.keys(VERBS).join(" | ")}`);
  process.exit(1);
}

const repoPath = ["readiness", "storyboard", "claims", "voice", "frames", "qa", "revise"].includes(verb)
  ? flag("--repo")
  : requireRepo();
process.exit(VERBS[verb](repoPath));
