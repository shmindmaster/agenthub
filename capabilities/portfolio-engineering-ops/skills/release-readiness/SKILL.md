---
name: release-readiness
description: Run non-destructive release-readiness checks (tests, build, CI status, open blockers, doc/config drift) and report pass/fail evidence — never deploys. Use before a release or when asked "are we ready to ship".
disable-model-invocation: true
---

# Release readiness (non-destructive)

This skill NEVER deploys, migrates production data, or rotates
credentials — it only checks and reports. Production release stays an
explicit, separate operator action in the repo's native provider (Railway,
etc.) per this portfolio's standing policy.

Checklist (delegate the noisy parts to `test-runner`/`explorer` so full
logs stay out of the main session):
1. `git status` clean on the release branch; no unpushed local-only commits.
2. Real test/lint/build commands pass (from applicable repository
   instructions — never guessed).
3. `gh pr checks`/`gh run list` — CI green on the branch being released.
4. Open PRs with `blocked`/`do-not-merge`/`needs-human`/`devin-hold` labels
   or unresolved actionable review findings — these are blockers, list them.
5. Docs-drift spot check on anything the release specifically touches (use
   `docs-drift` if a claim looks stale).
6. Secrets/config sanity: no plaintext secret newly added to a tracked
   file; required env vars documented in `.env.example` if new ones were
   introduced.

Report: pass/fail per item with evidence, and a final go/no-go with the
specific remaining blockers if no-go. Do not soften a no-go into a
qualified go — state it plainly.
