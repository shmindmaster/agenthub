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
# Fall back to Daytona v0 and its snapshots:
gh workflow run daytona-factory.yml -R shmindmaster/agenthub --ref main \
  -f app=revolva -f sha=<full-commit-sha> -f platform=v0
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
On Daytona v2 the TTL is the sandbox lifecycle policy (`on_timeout: delete`),
so the platform deletes a worker at the deadline even if the runner dies.

The rates are Daytona v2 on-demand Linux list prices. v2 bills CPU per core
(one core is 2 vCPUs with SMT), so a worker is 2 cores (4 vCPUs), 8 GiB and
10 GiB of ephemeral disk, which v2 does not bill. A create does not pin the CPU
model, so the reservation uses the highest on-demand core rate. The `v0` block
keeps the v0 per-vCPU rates and limits for `-f platform=v0`. A batch can mix
both platforms, so every reservation uses the dearer platform's worst case.

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
separately because the Daytona v0 SDK re-raises an interrupt as `DaytonaError`.
The Daytona provider has no package cache: every worker starts from its
image, and the reusable layer is the hash-verified artifact.

The workflow installs Daytona SDK 2.x with its v0 extra
(`daytona[v0-sdk]==2.0.0`). SDK 2.x has no API URL setting. The default
provider, `--provider daytona`, calls Daytona v2 through `client.v2`; the same
key works on both platforms. It finds workers with `GET /sandboxes/search`
(paged, eventually consistent, so every hit is re-read before it counts) and
creates them from two images in the default project:
`factory-node-build-v2` from [`node-build.Dockerfile`](./node-build.Dockerfile)
and `rexa-remotion-4-0-517-v2` from [`render.Dockerfile`](./render.Dockerfile).
These rebuild the v0 snapshots `factory-node-build-v1` and
`rexa-remotion-4-0-517`, which did not appear as v2 images. A v2 build stores
at most 16384 new files, so the build image starts from the full Debian Python
image and leaves Python 3.13 to uv, and the render image ships `node_modules`
as one archive that the render step unpacks. The v2 file proxy refuses paths
ending in `.log`, so logs are downloaded through a hard link. Build an image
again after editing its Dockerfile (an identical named build returns the
existing image; a changed one needs a new name in `factory.py`):

```python
from daytona import Daytona
from daytona.v2 import ImageBuilder
image = Daytona().v2.images.build(
    ImageBuilder.from_dockerfile(open("node-build.Dockerfile").read()), name="factory-node-build-v2")
```

`--provider daytona-v0` keeps the Daytona v0 path through `client.v0` and the
v0 snapshots.

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
