---
name: portfolio-prompt-os
description: Retrieve optional reusable workflow guidance from the Notion Portfolio Prompt OS after repository instructions, Linear outcomes, and GitHub state are understood. Use when a SHMindMaster task benefits from an existing implementation, QA, release, research, content, demo, or media workflow. Notion supports execution but does not override repository, tracker, code, or runtime authority.
---

# Portfolio Prompt OS

An optional retrieval path for reusable portfolio workflows. Notion stores reusable prompt bodies and examples, but it is not authoritative for current product direction, implementation, work status, or deployed state. This skill is the retrieval-and-routing contract; it does not itself contain workflow bodies.

## Source-of-truth hierarchy

1. **Repository `AGENTS.md` and code** — authoritative for repository behavior and current implementation.
2. **Linear, GitHub, and the runtime** — authoritative for outcomes/status, merged code/history, and deployed state respectively.
3. **Shwiki** — authoritative for shared portfolio guidance.
4. **Notion Prompt OS** — supporting library for reusable workflow bodies, examples, and execution records.

Never let a Notion workflow override current repository instructions or live delivery state. If Notion is unavailable, continue with repository-native guidance unless the requested task explicitly depends on a Notion-only workflow body.

## Retrieval contract

1. **Identify** the current repository and app; read its `AGENTS.md` first.
2. **Confirm current outcome and implementation state** in Linear, GitHub, and the repository as applicable.
3. **Fetch the Apps record** for that app (supporting execution profile + brand/creative profile) from the Notion Apps database.
4. **Fetch the Prompt Router.**
5. **Query only agent-ready prompts first** using the live schema: Lifecycle = Canonical,
   Copy Ready = checked, Validation Status = Both, complete body, and no unresolved prerequisite.
6. **Select one primary prompt/workflow** appropriate to the task.
7. **Fetch dependencies from `Prerequisites` and explicit page mentions**, plus supporting tool
   adapters. The live `Calls` field is a numeric usage counter, not a dependency relation.
8. **Validate** required tools, resolved variables, approvals, and execution-host compatibility before acting.
9. **Execute** within the declared boundaries (side effects, approval gates, restricted-data rules).
10. **Record the run** in the Notion Prompt Runs / Evals database when the workflow requires it.
11. **On Notion outage**, continue with repository-native guidance unless the requested workflow body exists only in Notion; never fabricate that body.

## What the router returns

For a task, the Prompt Router resolves: the primary prompt, prerequisites and explicit supporting
page mentions, supporting adapters, **excluded overlapping prompts**, required tools, approval
requirements, resolved variables, and execution-host compatibility.

## Demo and video sequencing

For any demo, screencast, or product-video request that includes product correction, first select
`Prepare Product for Demo — Product Experience Audit & Remediation`. Product Experience
Engineering owns audit, authorized remediation, validation, and the current revision-bound
`DEMO-READY` handoff. Select `Produce Demo Video v4` only after that handoff validates. Do not let
the video prompt absorb product-remediation ownership, and do not treat the older Demo Screencast
record as executable.

## Tool adapter lanes

Route creative/media steps to the owned adapters (each owns one lane — do not double up):
Playwright (product evidence), Remotion (programmatic motion), Descript (spoken content), Adobe (professional mastering), Canva (campaign assembly), Automated Media QA (validation). For multi-asset campaigns, hand off to the `portfolio-campaign-production` skill.

## Boundaries

- Honor each app's approval gates, required legal footer, approved-claim sources, and restricted-data rules from its Apps record.
- Never copy privileged/legal/discovery material or plaintext secrets into a prompt, run record, or generated artifact.
- Prefer the repo's own package manager and validation commands (read its AGENTS.md/CLAUDE.md).
