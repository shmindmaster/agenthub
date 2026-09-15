---
name: design-agentic-experiences
description: Use when an application includes AI-generated, AI-assisted, tool-using, or autonomous behavior that requires clear capability boundaries, user control, progress, approval, provenance, correction, and recovery.
---

# Design Agentic Experiences

## Overview

Design AI behavior as a transparent interaction contract. Match autonomy to consequence and preserve user comprehension, control, and recovery.

## Standalone execution

Start from the requested AI capability, affected user outcome, repository evidence, and available model/tool constraints. Prior workflow or specification artifacts are optional; generate the required agentic contract as part of the current design or implementation record. Follow [artifact contracts](../../references/artifact-contracts.md).

## Workflow

1. Define the user outcome and why AI is preferable to deterministic interaction.
2. Specify the agent's capabilities, inputs, tools, data boundaries, uncertainty, and prohibited actions.
3. Choose the autonomy level for each action based on consequence, reversibility, and confidence.
4. Design intent capture, assumptions, plan preview, progress, interruption, approval, result review, provenance, correction, retry, rollback, and handoff.
5. Define partial-success, stale-context, tool-failure, permission, timeout, and unsafe-request behavior.
6. Make state and control perceivable by keyboard and assistive technology; avoid motion-only or color-only status.
7. Define evaluations for task success, factuality, action correctness, user control, recovery, latency perception, and trust calibration.
8. Add the agentic contract to the workflow design or implementation specification.

## Reference routing

Load `02` from `../../references/product-experience-system/`, then add `01`, `04`, `05`, or `07` according to the artifact being produced. Follow [artifact contracts](../../references/artifact-contracts.md).

## Autonomy test

| Consequence and reversibility | Default interaction |
|---|---|
| Low consequence, easily reversible | Act with visible status and undo |
| Moderate consequence or ambiguity | Preview plan and allow correction |
| High consequence, external effect, or hard to reverse | Require explicit, informed approval |
| Prohibited or unsupported | Refuse clearly and offer safe alternatives |

## Common mistakes

- Do not hide deterministic product actions behind chat.
- Do not ask for blanket approval disconnected from the exact action.
- Do not present model confidence as factual certainty.
- Do not erase prior user input after a failed agent step.

## Example request

"Design this AI-assisted review flow so users understand, control, and can recover from every consequential action."
