#!/usr/bin/env node
// Validate evidence for a viewer-facing product demo before capture.
// Usage: node validate-demo-scenario.mjs <jobRoot>
import { existsSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { isAbsolute, join, relative, resolve } from "node:path";

const root = process.argv[2] && resolve(process.argv[2]);
if (!root || !existsSync(join(root, "job.json"))) {
  console.error("Usage: node validate-demo-scenario.mjs <jobRoot> (job.json required)");
  process.exit(1);
}
const json = (path) => JSON.parse(readFileSync(path, "utf8"));
const hash = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const withinRoot = (path) => {
  const rel = relative(root, path);
  return rel === "" || (!isAbsolute(rel) && rel !== ".." && !rel.startsWith("..\\") && !rel.startsWith("../"));
};
const fail = [];
const job = json(join(root, "job.json"));
const viewerFacing = job.intent !== "draft" && (job.kind === "product-screencast" || job.viewerFacing === true);
if (!viewerFacing) {
  console.log(JSON.stringify({ ok: true, skipped: true, reason: "not a viewer-facing product demo" }));
  process.exit(0);
}
const proofPath = join(root, "evidence", "demo-scenario-proof.json");
if (!existsSync(proofPath)) fail.push("missing evidence/demo-scenario-proof.json; do not record a viewer-facing product demo without source proof.");
let proof;
if (fail.length === 0) {
  proof = json(proofPath);
  for (const field of ["scenarioId", "persona", "problem", "hero", "outcome", "continuity", "source"]) {
    if (!proof[field] || (typeof proof[field] === "string" && proof[field].trim() === "")) fail.push(`scenario proof missing ${field}.`);
  }
  if (proof.synthetic !== true) fail.push("scenario proof must explicitly confirm synthetic=true.");
  const entities = proof.continuity?.entities;
  if (!Array.isArray(entities) || entities.length === 0 || entities.some((entity) => !entity?.type || !entity?.id)) {
    fail.push("continuity needs one or more generic entities with type and id.");
  }
  for (const field of ["segmentId", "beforeState", "action", "visibleResult"]) if (!proof.hero?.[field]) fail.push(`hero missing ${field}.`);
  if (!proof.outcome?.statement || !proof.outcome?.evidence) fail.push("outcome must name a statement and visible evidence.");
  const source = proof.source ?? {};
  if (source.kind !== "product-readiness-handoff" || source.status !== "DEMO-READY" || !source.path || !source.sha256 || !source.verifiedAt) {
    fail.push("source must be a DEMO-READY product-readiness-handoff with relative path, sha256, and verifiedAt.");
  } else {
    const sourcePath = resolve(root, source.path);
    if (!withinRoot(sourcePath)) fail.push("source.path must stay inside the external job workspace.");
    else if (!existsSync(sourcePath)) fail.push(`scenario source does not exist: ${source.path}.`);
    else if (hash(sourcePath) !== source.sha256) fail.push(`scenario source hash does not match: ${source.path}.`);
    else {
      const handoff = json(sourcePath);
      if (handoff.status !== "DEMO-READY" || handoff.workflow?.authenticated !== true || handoff.workflow?.actionResultObserved !== true ||
          !handoff.runtimeOutcome?.path || !handoff.runtimeOutcome?.sha256 || handoff.runtimeOutcome?.status !== "PASS") {
        fail.push("readiness handoff must prove an authenticated workflow and observed runtime outcome.");
      } else {
        const runtimePath = resolve(root, handoff.runtimeOutcome.path);
        if (!withinRoot(runtimePath) || !existsSync(runtimePath) || hash(runtimePath) !== handoff.runtimeOutcome.sha256) {
          fail.push("runtime outcome evidence is missing, outside the workspace, or hash-mismatched.");
        }
      }
    }
  }
  const storyboardPath = join(root, "story", "storyboard.json");
  if (!existsSync(storyboardPath)) fail.push("missing story/storyboard.json; scenario proof must bind to an explicit recording plan.");
  else {
    const board = json(storyboardPath);
    const episodes = Array.isArray(board) ? board : (board.episodes ?? [board]);
    const allowed = new Set((entities ?? []).map((entity) => `${entity.type}:${entity.id}`));
    for (const episode of episodes) {
      if (episode.scenarioId !== proof.scenarioId) fail.push(`storyboard scenarioId must equal source proof ${proof.scenarioId}.`);
      if (!episode.cta || String(episode.cta).trim() === "") fail.push("storyboard episode needs a concrete CTA.");
      const segments = episode.segments ?? episode.beats ?? [];
      if (!segments.some((segment) => segment.id === proof.hero.segmentId)) fail.push(`hero segment ${proof.hero.segmentId} is absent from storyboard.`);
      for (const segment of segments) {
        if (segment.scenarioId && segment.scenarioId !== proof.scenarioId) fail.push(`segment ${segment.id} switches to undeclared scenario ${segment.scenarioId}.`);
        for (const entity of segment.entityRefs ?? []) {
          if (!entity?.type || !entity?.id || !allowed.has(`${entity.type}:${entity.id}`)) fail.push(`segment ${segment.id} references an entity outside the proven scenario.`);
        }
      }
    }
  }
}
console.log(JSON.stringify({ ok: fail.length === 0, scenarioId: proof?.scenarioId ?? null, errors: fail }, null, 2));
process.exit(fail.length ? 1 : 0);
