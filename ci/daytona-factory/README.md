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

```sh
# Section 8 journeys with recordings, and the mechanism probes:
gh workflow run daytona-factory.yml -R shmindmaster/agenthub --ref main \
  -f app=revolva -f sha=<full-commit-sha> -f suite=journey
gh workflow run daytona-factory.yml -R shmindmaster/agenthub --ref main \
  -f app=empowera -f sha=<full-commit-sha> -f probe=fail   # or probe=hang, then cancel
```

## Budget and lifetime controls

[`budget.json`](./budget.json) holds the pilot defaults and `factory.py` refuses
to load a policy that loosens them: one concurrent worker, zero GPU, a
30-minute lifetime that includes setup and evidence export, and one retry only
for a transient worker-creation error. Before any metered launch the workflow
reserves the worst case (largest allowed worker for the whole lifetime, times
the retry) for this run and every started attempt of every run created since
`DAYTONA_PILOT_BATCH_START`. GitHub keeps a run's creation time across reruns,
so a rerun of a run created before the batch start is refused; dispatch a fresh
run instead.
The reservation must fit the smaller of $10 and 10% of
`DAYTONA_ELIGIBLE_CREDITS_USD`. `DAYTONA_CASH_FALLBACK_DISABLED` must be
`true` (auto top-up checked off) or `unreachable-under-cap` (auto top-up not
verified, but the cap stays below the attested credits). The receipt records
which one applied and never claims a disabled fallback that was not checked. The owner sets these three variables on the `daytona-factory`
environment after checking the Daytona wallet; a missing value refuses the
launch. Workers are checked for GPU and for CPU, memory and disk above the
policy limits after creation, and their TTL never outlives the job deadline.

## Evidence, failure and cleanup

Every run writes `receipt.json`, including failed and cancelled runs: status,
source, factory and lockfile hashes, toolchain, worker IDs, resources, start,
end and per-worker seconds, cache key and hit, budget reservation, estimated
cost, and the size and SHA-256 of every exported file. Evidence is copied off
the worker before it is deleted. Every evidence check and download is bounded
by the export window and stops `teardown_reserve_seconds` before the deadline,
so a stalled transfer cannot block deletion or the receipt. A run clears
earlier evidence from its output directory first, and the receipt hashes only
files this attempt exported, so a failed export never passes on an earlier
run's copy. A cancelled run keeps only `tests.log`
because the runner is killed seconds later. Only a passed, unprobed receipt
can be reused. The separate `cleanup` job runs after success, failure or
cancellation, deletes and counts every worker labeled with the run, and fails
if any outlived its job. A Daytona sandbox that is already destroying
no longer counts as a live worker. The cancellation signal is tracked
separately because the Daytona SDK re-raises an interrupt as `DaytonaError`.
The Daytona provider has no package cache: every worker starts from its
snapshot, and the reusable layer is the hash-verified artifact.
The workflow installs Daytona SDK 2.x with its v0 extra
(`daytona[v0-sdk]==2.0.0`, which bundles the 0.231.1 v0 client) and the
provider calls Daytona v0 through `client.v0`. SDK 2.x has no API URL setting;
the default Daytona v0 API is implied.

`--provider local` runs the same scripts, limits, labels, deadline, export and
cleanup on a self-hosted Docker worker built from
[`local-worker.Dockerfile`](./local-worker.Dockerfile), with package caches on
a volume keyed by the image and lockfile hashes. The image carries the
PostgreSQL, Redis and Corepack-managed pnpm that the ABACare setup starts. It is unmetered and does not
exercise Daytona's API, signed previews or wallet.

GitHub keeps one active run and queues up to 100 pending runs across all three
applications. The queue is hosted by GitHub, independent of the runner.
GitHub cancels requests beyond the queue limit. An interrupted run can be
rerun from its run page. Daytona workers carry the run ID and a hard lifetime.
A rerun cleans up workers left by that run before creating replacements.

Successful results include tests, a browser recording, a decoded MP4, and a
receipt with source and factory SHAs, verified file sizes and hashes, preview
revocation, and worker cleanup. Artifacts require authenticated read access to
the private repository and expire after 90 days. Failure receipts and evidence expire
after 14 days. A repeat request for the same app, source and factory revision reuses
an available, hash-verified artifact. Select **rebuild** to run it again.

ABACare exercises its synthetic voice approval and claim workflow. Empowera
runs its desktop film-path checks and records the synthetic approval outcome.
Revolva runs its rehearsal suite and records the synthetic enterprise-import
workflow. The `journey` suite runs the section 8 journeys against each app's
isolated API and temporary database with every test recorded: Empowera's
review, procedure-revision and bound-learner specs; Revolva's new assignment,
amendment, guest-entry and enterprise-import specs. The signed previews expire in two minutes and are revoked during the
run. The Revolva signed preview is its built web shell. Its recorded workflow
uses the isolated authenticated rehearsal with a synthetic database.

The GitHub environment `daytona-factory` accepts only `main`. It holds a
Daytona sandbox write/delete key and an individual read-only SSH deploy key
for each source repository. Rotate the Daytona key before its expiration.
Workers receive an exact-SHA Git archive and synthetic fixture settings.
Production releases use the application repositories' existing workflows.
