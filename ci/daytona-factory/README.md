# Daytona Build and Demo Factory

Open **Actions → Daytona Build and Demo Factory → Run workflow** in the private
AgentHub repository. Use `main` as the workflow branch, select an application and
enter the full source commit. The commit must be reachable from the app's
`main` branch or, for ABACare, `dev`.

```sh
gh workflow run daytona-factory.yml -R shmindmaster/agenthub --ref main \
  -f app=abacare -f sha=<full-commit-sha>
gh run list -R shmindmaster/agenthub -w daytona-factory.yml
gh run download <run-id> -R shmindmaster/agenthub
```

GitHub keeps one active run and queues up to 100 pending runs across all three
applications. The queue is hosted by GitHub, independent of the runner.
GitHub cancels requests beyond the queue limit. An interrupted run can be
rerun from its run page. Daytona workers carry the run ID and a hard lifetime.
A rerun cleans up workers left by that run before creating replacements.

Successful results include tests, a browser recording, a decoded MP4, and a
receipt with source and factory SHAs, verified file sizes and hashes, preview
revocation, and worker cleanup. Artifacts require authenticated read access to
the private repository and expire after 90 days. Failure logs expire after 14
days. A repeat request for the same app, source and factory revision reuses
an available, hash-verified artifact. Select **rebuild** to run it again.

ABACare exercises its synthetic voice approval and claim workflow. Empowera
runs its desktop film-path checks and records the synthetic approval outcome.
Revolva runs its rehearsal suite and records the synthetic enterprise-import
workflow. The signed previews expire in two minutes and are revoked during the
run. The Revolva signed preview is its built web shell. Its recorded workflow
uses the isolated authenticated rehearsal with a synthetic database.

The GitHub environment `daytona-factory` accepts only `main`. It holds a
Daytona sandbox write/delete key and an individual read-only SSH deploy key
for each source repository. Rotate the Daytona key before its expiration.
Workers receive an exact-SHA Git archive and synthetic fixture settings.
Production releases use the application repositories' existing workflows.
