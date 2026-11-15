# Interim release on DigitalOcean (until 2026-11-30)

This is how a DigitalOcean-hosted personal product builds, tests and deploys until DigitalOcean is retired on 2026-11-30, and how it stays ready for AWS on 2026-12-01. The estate inventory (app IDs, owners, per-product state) lives in the private tracker, not here.

## Default: the platform's native build, no extra CI

The release path is:

GitHub merge → App Platform Git-source build (`deploy_on_push`) → checks inside that build → native deploy → smoke check.

A failed build or a failed health check leaves the previous deployment serving, so the native build is the release gate. Do not add a container-build-and-publish pipeline, a registry push or a runner for anything the native build can do itself.

## Rules

1. **Checks run inside the native build.** The build command, or the Dockerfile the component builds from Git, runs the following in order:
   1. The config-payload scanner, before any install.
   2. The lockfile install.
   3. Lint, typecheck and compile.
   4. The unit tests.

   If any step fails, the build fails and nothing is released.
2. **The scanner comes first.** Config files execute during an ordinary install or build, so a build is not a read-only inspection.
   - Vendor the canonical scanner from `packages/security/scripts/check-config-payloads.mjs`. Keep it byte-identical with LF endings, at `scripts/ci/check-config-payloads.mjs`.
   - Record the source commit and SHA-256 in the product's `docs/deployment.md`.
   - Run `node scripts/ci/check-config-payloads.mjs --root .` as the first build step.
   - AgentHub is private, so the build cannot fetch the scanner itself.
   - Where the build command lives in the app spec rather than the repository (static sites, buildpack components), the gate is outside the reach of a repository push.
3. **A runner only for what the native build cannot run.** Database, tenant-isolation, security and critical business-rule integration tests that need Postgres or Valkey run before merge on the product's runner, described below. That job runs only those tests. It has no image build, no registry access and no secrets. A product without such tests has no runner.
4. **Prove the gate can fail.** Before relying on a check:
   - Build the exact Dockerfile or build command with a deliberately failing check, and show that the build fails.
   - Use the build droplet's Docker context for this, or a short-lived verification app from a throwaway branch, deleted the same hour.
   - Never push a failing commit to `main`.
5. **Running commit.** After each deploy, check that the deployment's source commit hash equals the merged SHA, and that `/health` reports the same SHA where it is exposed. Smoke-test the production domain.
6. **Native rollback.** Record the live deployment ID before the first change. Roll back with `POST /v2/apps/{id}/rollback` and `skip_pin: true`, against one of the last 10 successful deployments, or by redeploying an earlier deployment. Rollback restores code, not data. A database rollback is a separate, backup-verified procedure.
7. **Static sites stay `static_site` components** with `deploy_on_push: true`. The scanner and checks go in the spec's `build_command`.
8. **One environment per product.** There are no staging apps on DigitalOcean. The only exception is the product the operator policy names.
9. **Remove only what is proven redundant.** Before deleting a workflow, runner, registry repository or release script, follow these steps in order:
   1. Read what it verifies.
   2. Show the native build covers it, or move the check there.
   3. Prove the failure case.
   4. Confirm rollback still works.

   Do not destabilise a working deployment only to simplify tooling.

**Residual risk.** The native build releases whatever lands on `main`, and anyone who can push to `main` can remove an in-repository check. The mitigations are branch protection and the pre-merge runner job, where one exists.

## Pre-merge runner (`ci/do-runner/`), only where rule 3 applies

Since 2026-11-12 every product shares one droplet, `sh-forge` (SSH alias `forge`, Docker context `forge`). It carries the CI lane, macOS and iOS builds, Android, renders and dev or test jobs. `sh-ci` runs there as root from `/srv/work/sh-ci/bin/sh-ci`. `/srv/work/sh-ci/OWNERS.md` on the box says who owns which lane.

The systemd slice `sh-ci.slice` (`ci/do-runner/sh-ci.slice`, installed in `/etc/systemd/system/`) caps the whole CI lane at 12 CPUs and 24 GB, which is three concurrent 4-CPU / 8 GB jobs. That way CI never starves an iOS build or a render. The runners are overcommitted on purpose: there are more of them than the slice can hold at their 8 GB ceilings, because most sit idle at under 100 MB. If more than three heavy jobs run at once, the slice is throttled at 22 GB and then hits its 24 GB limit. At that point the kernel kills a job process, never a database: runners and BuildKit run with `oom_score_adj: 500` and the Postgres and Valkey sidecars with `-500`. The killed job fails visibly in GitHub and can be re-run. It never passes silently. If that happens often, raise the slice limits only together with the owners of the other lanes in `OWNERS.md`. Each repository that needs a runner gets a compose project `sh-ci-<repo>`:

| Service | Purpose |
| --- | --- |
| `runner` | `ghcr.io/actions/actions-runner`, pinned by digest. Persistent registration `do-sh-build-<repo>` with labels `self-hosted, do-sh-build, sh-ci-<repo>`. `_work` is on tmpfs and is wiped at every job start by `job-started.sh`. No Docker socket. The scanner is mounted read-only at `/opt/sh-security`. |
| `postgres` (`--postgres` / `--pgvector` / `--pg-image=sh-ci/<name>:<tag>` or `@sha256`-pinned) | Postgres 18, pgvector on Postgres 18, or a repository-built image. It runs on tmpfs with trust auth: `TEST_POSTGRES_URL=postgresql://postgres@postgres:5432/ci`. |
| `valkey` (`--valkey`, `--valkey=2`) | Valkey 8 with no persistence: `TEST_REDIS_URL=redis://valkey:6379/0`, plus `TEST_REDIS_URL_B` for a second instance. |
| `buildkitd` (`--buildkit`) | Off by default. A private BuildKit daemon, only for a repository that genuinely must build images in CI. |

Write the job's label through a repository variable, so the move to AWS CodeBuild-hosted runners ([codebuild-pr-ci.md](./codebuild-pr-ci.md)) is a variable change:

```yaml
runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted","sh-ci-<repo>"]') }}
```

Register or update the runner from a workstation with repository admin. Never copy a runner's state directory to another host; register there with a new token instead, because two hosts holding one registration fight over the session.

```bash
gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token \
  | ssh forge /srv/work/sh-ci/bin/sh-ci up <repo> --postgres --valkey
ssh forge /srv/work/sh-ci/bin/sh-ci status
```

- The one-hour bootstrap token is read from stdin, used once and deleted. On later re-ups, pass `</dev/null`. A re-up with no options reuses the saved ones; `--reset` clears them.
- If the repository already has a runner named `do-sh-build-<repo>` or labelled `do-sh-build` outside the kit, use `--sole-label`. The kit runner then registers as `sh-ci-<repo>` with only that label. Without it, `config.sh --replace` takes over the existing registration.
- Runners are persistent. A personal account supports repository-level runners only, and ephemeral or JIT registration needs an admin credential for every job. With a GitHub App holding Administration: write, switch to `generate-jitconfig` per job.
- Runners are registered with `--disableupdate`. GitHub stops dispatching to a runner more than 63 days behind the latest release, which is longer than the droplet's remaining life.
- Containers use `restart: on-failure`, and no unit is enabled at boot. Run `sh-ci up <repo>` after a droplet reboot.
- Teardown before 2026-11-30:
  1. Run `sh-ci rm <repo>` for every repository.
  2. Delete each runner registration under Settings, Actions, Runners.

## Android build lane (`ci/do-runner/android-*`)

Builds an Expo/React Native Android app from a branch of a bare repo on the host, inside a container, with no EAS cloud and no load on the owner PC (SH-4524).

- Image `forge/android-builder:2` (`ci/do-runner/android-builder.Dockerfile`): the same `reactnativecommunity/react-native-android` base as `:1` (JDK 17, SDK 37, NDK 28.2), plus Node 24.22, pnpm 11.15.0 and the React Native 0.86 toolchain (`platforms;android-36`, `build-tools;36.0.0`, `ndk;27.1.12297006`) so an ephemeral container never re-downloads an NDK. `:1` is left untouched.
- `android-setup.sh` (root, on forge) builds the image, installs `/usr/local/bin/android-build`, and writes the shared caches: `/opt/forge/android/gradle-home` (its `gradle.properties` overrides the generated project's 512 MB Metaspace cap, the cold-build OOM measured 2026-11-10) and `/opt/forge/android/pnpm-store`.
- Lane run, ABACare preview values (public, from `apps/mobile/eas.json`):

```bash
git -C <abacare-checkout> push ssh://forge/srv/abacare.git <local-branch>:<branch>
ssh forge android-build /srv/abacare.git <branch> --app apps/mobile \
  --env EAS_BUILD_PROFILE=preview \
  --env EXPO_PUBLIC_API_URL=https://abacare.ai/api \
  --env EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_Y2xlcmsuYWJhY2FyZS5haSQ= \
  --env EXPO_PUBLIC_SENTRY_ENVIRONMENT=preview
```

  The lane fetches only the pushed ref, runs the app's own `build-environment.cjs` gate when it ships one, `expo prebuild --platform android`, then `gradlew clean assembleRelease` (`--variant debug` for a debug APK). Working trees persist at `/srv/work/android/<repo>-<repo-key>-<branch>-<branch-key>` (node_modules and the generated `android/` survive between runs); before reuse, the script verifies that the checkout's `origin` still resolves to the requested bare repo.
- Builds that share a persistent checkout are serialized with a host `flock`; each builder container is capped at 12 CPUs and 24 GiB of memory with swap disabled. The lane removes prior APK outputs for the requested variant before starting Gradle, so a failed or empty build cannot publish an older APK under the current commit identity.
- Output: `/srv/work/android/artifacts/<repo>-<repo-key>-<branch>-<branch-key>-<sha8>-<app>-<variant>[-<envhash8>].apk` with its sha256 and the full build log under the same stem; root builds use the `root` app tag. Exit 0 means the APK was built. The stem is the rerun key: identical identity replaces its own artifacts, and a different repository, branch, app, variant or `--env` set can never overwrite another build's evidence. The APK is unsigned: the lane holds no Android signing keys, and store builds still go through EAS.

## Jobs dashboard (`jobs.forge.shtrial.com`)

Read-only status page for the box (SH-4524): `ci/do-runner/jobs-dashboard.py` serves `127.0.0.1:8790` under `forge-jobs-dashboard.service` (installed at `/opt/forge/jobs-dashboard/`, unit in `/etc/systemd/system/`), and Caddy reverse-proxies `https://jobs.forge.shtrial.com` to it with the same owner-IP matcher as `mac.forge.shtrial.com`. It shows host vitals, the macOS VM lane (container state, `mac` leases, storage), the Android lane (image, artifacts), the sh-ci runners and sidecars, the media/render jobs under `/srv/work/jobs`, and other containers. Every page is regenerated on request (15 s cache); `/status.json` is the machine-readable form; `/healthz` answers `ok`. The service reads this host only: no writes, no external calls, no credentials.

## AWS target (2026-12-01)

The AWS equivalent of the native path is a CodeBuild project that builds from the Git commit into ECR, then deploys to ECS.

| DigitalOcean | AWS |
| --- | --- |
| App Platform service or job (native build) | CodeBuild from Git into ECR, then ECS Express Mode (Fargate, one shared ALB with host rules). App Runner has been closed to new customers since 2026-04-30. |
| Managed PostgreSQL 18 | RDS for PostgreSQL 18. Use logical replication, but test publication rights first, because DigitalOcean does not grant superuser. The fallback is `pg_dump`/`pg_restore` under a write freeze. |
| Managed Valkey | ElastiCache Serverless Valkey, or none if it is only a cache. |
| App secrets | SSM Parameter Store or Secrets Manager, referenced by name. |
| Static site | S3 with CloudFront, or Amplify Hosting. |
| Pre-merge runner | CodeBuild-hosted GitHub Actions runner (`vars.CI_RUNS_ON`), for the same narrow test set. |

Order of operations:
1. Lower DNS TTLs 48 hours ahead.
2. Rehearse in an AWS staging stack by 2026-11-27.
3. Cut over only after backups and data reconciliation pass.
4. Keep DigitalOcean for a rollback window, and get approval before deleting anything there.
