# Repository scan

Run `node scripts/scan-repo.mjs <repo-path> [--json]` first. It is offline and read-only, and reports the measurable items below. Then check the judgment items by reading code. File each finding once, ranked, as a Linear issue labelled `from-execution`.

## Measured by the script

- Source files over 800 and over 1,500 lines (tracked files only; generated, vendored, lock, migration and snapshot files excluded).
- Missing lint, format or typecheck configuration for the stacks present.
- Source directories with no tests beside them or in a mirrored test tree.
- TODO, FIXME and HACK markers.
- Committed `.env` files and obvious secret-shaped strings.

## Judgment items

| Rank | Check |
| --- | --- |
| High | Tenant or user scoping missing from a query path; auth or role checks only in the UI |
| High | PHI or regulated data in logs, analytics, email through a non-BAA provider, or model prompts |
| High | Outbound calls with no timeout; unbounded retries or queues; swallowed exceptions |
| High | Schema changes without a migration; destructive migration without a backup step |
| Medium | Business rules inside controllers, routes, components or SQL strings |
| Medium | Two implementations of one concept (parallel services, duplicated validators) |
| Medium | Slow work on the request path that belongs in a worker |
| Medium | Demo or synthetic data not clearly separated from production paths |
| Low | Inconsistent file, folder or symbol naming against the dominant pattern |
| Low | Dead code, unused exports, stale feature flags |
| Low | Comments that explain confusing code instead of the code being simplified |

## Report

One table per repository: rank, finding, file and line, evidence, suggested owner issue. Keep the high items first. Do not fix during a scan.
