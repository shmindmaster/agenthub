---
name: design
description: Produces a testable acceptance contract with states, keyboard behaviour and the smallest slice. Use when a finding, feature idea, redesign, spec or AI feature needs deciding before code. Not for visual styling; use frontend-design. Not for an obvious fix; use build.
---

# Design

Step 2 of 4: ground, decide, build, prove. Turn one finding or idea into a contract someone else can test. Start from the request and the repository; no earlier files are needed.

## Checklist

Copy this list and tick each item.

- [ ] State the user, their situation, the outcome and the evidence, labelled Observed, Implemented, Reported, Assumed or Unknown.
- [ ] Choose the simplest thing that works, in this order: remove, simplify, combine, repair, add.
- [ ] Inspect the affected routes, components, data, permissions and tests, and reuse what exists.
- [ ] Cut to the smallest slice that delivers the outcome end to end. List what is out of scope.
- [ ] Write the target flow from entry to confirmation, including recovery.
- [ ] Fill in every state that applies: normal, empty, loading, partial, error, offline, permission, destructive, success, return later.
- [ ] Define keyboard use: tab order, focus on open and close, focus after errors, announcements.
- [ ] Write acceptance tests. Each names a starting state, an action and an observable result.
- [ ] Name one outcome metric, its baseline and its threshold, before anyone sees results.

Read when the feature uses AI, tools or autonomy: [agentic](../../references/agentic.md). Add its risk rating and failure behaviour to the contract.

## Example

Input: "Improve the invite form."

Output: "Email field validates on blur. A failed send keeps the typed email, moves focus to the error and announces it. Success returns focus to the Invite button. Acceptance: with an invalid email, pressing Send shows the error and focus lands on the field."

## Rules

- Do not specify a redesign as one slice because the pieces feel related. Ship one slice, then learn.
- Do not hide a deterministic action behind chat because a model could do it. Give it a control.
- Do not write "standard behaviour" for a state to save time. Define it.
- Do not prescribe a new library before checking what the repository has.
- Do not fill a gap with an invented requirement to finish the contract. Mark it Unknown and ask.

## Output

Return these sections, in order:

1. Outcome
2. Smallest slice
3. Target flow
4. States
5. Keyboard
6. Acceptance tests
7. Outcome metric

Save to `_product-experience/02-design.md` only when the user asks for a file. Then run `node ../../scripts/validate-artifact.mjs --type design <file>`, fix what it reports, and repeat until it passes.

Next: `build`.
