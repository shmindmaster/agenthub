---
name: verify
description: Produces an independent Pass, Fail or Blocked verdict with command evidence and outcome metrics. Use when a built change or workflow needs verifying, QA, sign-off or a ship decision, or asks whether it worked. Not for assessing a whole app; use audit.
---

# Verify

## Workflow contract

1. Use the acceptance contract, candidate revision and independent evidence source.
2. Exercise normal, failure and permission paths against the candidate, then hand a passing journey to `demo` if requested.
3. Return a Pass, Fail or Blocked verdict with evidence for each criterion.
4. If the candidate revision, role or environment is unproven, mark the affected criterion Blocked.

Step 4 of 4: ground, decide, build, prove. Start from the request, the diff and the running app; no earlier files are needed.

The builder never issues the verdict. If this context wrote the change, start `product:reviewer`, or a new session on a host without subagents.

Use the repository's Playwright, axe and Lighthouse. If one is missing, mark its check Blocked.

## Checklist

Copy this list and tick each item. Report the command and its output for every check.

- [ ] Take the acceptance tests from the contract, or derive them from the request and label them Assumed.
- [ ] Record the environment: revision, viewports, synthetic accounts, permissions.
- [ ] Read when a journey needs a session: [authenticated acceptance](../../references/authenticated-acceptance.md). Prove sign-in, each role and denial backend-side.
- [ ] Run the repository's type, lint, test and build commands.
- [ ] Drive each in-scope journey with Playwright, using role locators and ARIA snapshots. Capture console and network output.
- [ ] Run axe, then test by hand with keyboard, zoom and a screen reader. Axe finds about 57% of issues.
- [ ] Compare visuals with `toHaveScreenshot`: animations disabled, dynamic content masked, fixed viewports. A reviewer approves every baseline diff.
- [ ] Measure with Lighthouse and a trace, plus field data: LCP 2.5 s, INP 200 ms, CLS 0.1 or below.
- [ ] Compare outcome metrics with their thresholds.

## Rules

- Do not fix what you find because it is small. Report it with reproduction steps.
- Do not infer runtime behaviour from code because the app is hard to start. That check is Blocked.
- Do not claim causality from an uncontrolled before-and-after comparison because the number moved.

## Output

Return these sections, in order:

1. Environment
2. Checks, with commands and output
3. Defects, with reproduction steps
4. Outcome metrics
5. Verdict

Save to `_product-experience/05-verify.md` only when asked. Then run `node ../../scripts/validate-artifact.mjs --type verify <file>` and repeat until it passes.

Next: `build` on Fail, `demo` when a Pass is headed for a recording.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
