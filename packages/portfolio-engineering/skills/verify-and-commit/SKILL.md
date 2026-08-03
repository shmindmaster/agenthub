---
name: verify-and-commit
description: Use when a non-trivial change is ready to commit and the diff, focused validation, secret exposure, generated artifacts, and commit boundary need verification.
disable-model-invocation: true
---

# Verify and commit

1. `git status` and `git diff` (staged + unstaged) — review everything
   that would be included, not just what you remember changing.
2. Determine the smallest sufficient validation for what actually changed
   (touched routes/contracts/DB behavior → broader checks; a single
   isolated file → focused check only). Use this repo's own commands from
   applicable repository instructions and package manifests — never invent
   one. If the executing host supports a test-verification subagent, delegate the run to a fresh
   context; otherwise run it directly. The
   worker must read the current instructions, manifests, diff, and requested
   validation scope before running anything and may not assume prior session
   context.
3. Secret/artifact check before staging: no `.env`, credential files, keys,
   or generated build output (`dist/`, `.next/`, coverage, node_modules) —
   these should already be gitignored; if `git status` shows one anyway,
   stop and ask rather than silently including it. gitleaks also runs
   automatically via the user-level `git commit` hook as a second layer.
4. Stage only files relevant to this change — never `git add -A`/`git add
   .` blind.
5. Write a commit message describing why, not just what (the diff already
   shows what). Match the repo's existing commit-message style/conventions;
   use a host-native commit-message helper only when the executing host's
   managed configuration provides one.
6. Only push if asked, or if the task's own instructions already authorized
   it (e.g. mid-way through `issue-to-pr`).
