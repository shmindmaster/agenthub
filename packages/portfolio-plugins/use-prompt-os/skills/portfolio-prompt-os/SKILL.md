---
name: portfolio-prompt-os
description: Route portfolio work to canonical reusable workflows maintained in the Notion Portfolio Prompt OS. Use for implementation, architecture, research, QA, release, security, marketing, branding, content, demo, or media work on any app in C:\Repos\shmindmaster — before reconstructing a workflow from memory. Identifies the app, fetches the Prompt Router, selects one Agent-Ready workflow, resolves its dependencies and tool adapters, and records the run.
---

# Portfolio Prompt OS

The single entry point for reusable portfolio workflows. Canonical prompts live in the **Notion Portfolio Prompt OS**, not in local files. This skill is the retrieval-and-routing contract; it does not itself contain the workflow bodies.

## Source-of-truth hierarchy

1. **Notion Prompt OS** — canonical for workflow/prompt bodies, routing, and app profiles.
2. **The repository and runtime** — authoritative for current implementation state.
3. **Local bootstrap files** (AGENTS.md / CLAUDE.md prepend) — thin pointers only; never a substitute for the canonical body.

Never reconstruct a canonical prompt from memory or a stale local copy. If Notion is unavailable, report the access blocker instead of improvising.

## Retrieval contract

1. **Identify** the current repository and app.
2. **Fetch the Apps record** for that app (execution profile + brand/creative profile) from the Notion Apps database.
3. **Fetch the canonical Prompt Router.**
4. **Query only agent-ready prompts first** using the live schema: Lifecycle = Canonical,
   Copy Ready = checked, Validation Status = Both, complete body, and no unresolved prerequisite.
5. **Select one primary prompt/workflow** appropriate to the task.
6. **Fetch dependencies from `Prerequisites` and explicit page mentions**, plus supporting tool
   adapters. The live `Calls` field is a numeric usage counter, not a dependency relation.
7. **Validate** required tools, resolved variables, approvals, and execution-host compatibility before acting.
8. **Execute** within the declared boundaries (side effects, approval gates, restricted-data rules).
9. **Record the run** in the Notion Prompt Runs / Evals database (agent, model, result, evidence URLs, output artifact).
10. **On Notion outage**, report the blocker — do not fabricate the workflow.

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
