---
name: engineer
description: Applies portfolio engineering rules to code changes, refactors, reviews and repo scans. Use when reviewing code against portfolio rules, splitting a large file, planning a refactor or layer boundary, or scanning a repo for quality problems. Not for UX review; use audit.
---
# Engineer

Runs standalone: start from the bare repository; no earlier files are needed. The scan requires Node.

## Rules for every code change

1. Preserve behavior. Keep behavior changes, refactors and cleanup in separate commits.
2. Leave touched code clearer: precise names, one term per concept, no hidden side effects, no boolean-flag parameters.
3. Prefer deep modules. Split by ownership and change reason, never only to cut line count. Reject wrappers that hide nothing.
4. New or changed source files stay under 800 lines; a file already over 800 lines must not grow; over 1,500 lines needs a split plan in the PR.
5. Treat code without trustworthy tests as risky: characterize its current behavior with a test before changing it.
6. Bound every outbound call, retry, queue, pool, payload and result set. Retry only safe, transient failures, with backoff.
7. Business rules never import frameworks, ORM rows, HTTP requests or vendor SDKs. Translate at the edge.
8. Validate input at trust boundaries. Enforce tenant scoping in the data access path, not only in the UI.
9. Fail visibly: explicit errors, structured logs with correlation ids, no swallowed exceptions, no secrets in logs.
10. Follow the repository's dominant structure and naming. File one issue for an inconsistency instead of a drive-by rename.

## Checklist

- [ ] Read the repository's instructions and `git status`.
- [ ] Run `node scripts/scan-repo.mjs <repo>` from this skill's directory for size, tooling, test and secret signals.
- [ ] Read only the reference the task needs (table below).
- [ ] For a large file, pick the one with the highest change risk, add characterization tests, and extract one owned concept per PR with a stable interface.
- [ ] Rank review or scan findings high (security, data loss, tenant leak, production failure), medium (behavior risk, missing tests, boundary violation) or low (naming, size, style), citing the rule number or reference.
- [ ] State before and after line counts and the tests run.

## References

Read when the task matches its row.

| Task | Reference |
| --- | --- |
| Splitting a large file, reducing complexity, designing an interface | `references/a-philosophy-of-software-design.md` |
| Changing poorly tested code, risky refactor | `references/untested-code.md` |
| Timeouts, retries, jobs, deploys, health, degraded modes | `references/release-it.md` |
| Naming, functions, comments, everyday readability | `references/clean-code.md` |
| Layers, dependency direction, monorepo boundaries | `references/clean-architecture.md` |
| PostgreSQL schemas, migrations, queues, consistency, caching | `references/designing-data-intensive-applications.md` |
| Domain names, module boundaries, bounded contexts | `references/domain-driven-design-distilled.md` |
| Scanning a repository for common problems | `references/repo-scan.md` |

Book-derived references are adapted from ciembor/agent-rules-books (MIT, commit 893a88a); see `references/LICENSE-agent-rules-books.txt`.

Next: `verify`, once the change is built.
