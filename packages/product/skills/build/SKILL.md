---
name: build
description: Produces a tested implementation of a scoped product or UI change in the repository's own idiom. Use when asked to implement, fix or add a specified UI, frontend or workflow change. Not for deciding what to build; use design. Not for the final verdict; use verify.
---

# Build

## Workflow contract

1. Use the scoped design contract or an explicit small fix and the repository instructions.
2. Implement the smallest change, run the local checks, and hand the exact revision and evidence to `verify`.
3. Return the changed behavior, files, tests, and any remaining blockers.
4. If a requirement is blocked, preserve the current working path and record the missing dependency.

Step 3 of 4: ground, decide, build, prove. Start from a direct instruction or a contract; no earlier files are needed. For a one-line fix, decide and build are one step: write the test, make the fix, go to `verify`.

## Checklist

Copy this list and tick each item.

- [ ] Read the repository's instructions and `git status`. Find its build, test, lint and browser-test commands.
- [ ] If there is no contract, write the scope, expected behaviour and affected states in a few lines. If the behaviour is ambiguous, stop and use `design`.
- [ ] Write a test that fails for the missing behaviour. Run it and see it fail for the right reason.
- [ ] Make the simplest complete change, using the repository's own components, tokens and data patterns.
- [ ] Handle each state that applies: empty, loading, error, partial, offline, permission.
- [ ] Check keyboard, focus and narrow width. Keep the user's input after any failure.
- [ ] Run the focused test, then the broader checks.
- [ ] Report changed files, commands with their output, and remaining risks.

## Rules

- Do not write production code before the failing test because the change is small.
- Do not add a library or replace the design system to restyle one workflow.
- Do not touch unrelated work or use destructive git recovery to clear a conflict.
- Do not use real customer data or put secrets in code, tests or logs because a fixture is slow to make.
- Do not say "verified" or "done" because your tests passed. You built it, so the verdict belongs to someone else.

Next: `verify`, from a fresh context.

Read when applying the detailed patterns, accessibility. [Workflow detail](references/workflow-detail.md)
