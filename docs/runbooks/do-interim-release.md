# Interim release on DigitalOcean (until 2026-11-30)

This is how a DigitalOcean-hosted personal product builds, tests and deploys until the build droplets are destroyed on 2026-11-30, and how it is kept ready for AWS on 2026-12-01. The estate inventory (app IDs, owners, per-product state) lives in the private tracker, not here.

## Rules

1. **CI runs only on DigitalOcean.** Every workflow job runs on the product's self-hosted runner on the shared build droplet. GitHub Actions only orchestrates. Write the label through a repository variable, so the move to AWS CodeBuild-hosted runners ([codebuild-pr-ci.md](./codebuild-pr-ci.md)) is a variable change:

   ```yaml
   runs-on: ${{ fromJSON(vars.CI_RUNS_ON || '["self-hosted","sh-ci-<repo>"]') }}
   ```

2. **Scan before anything executes.** The first step after checkout and runtime setup is `node /opt/sh-security/check-config-payloads.mjs --root "$GITHUB_WORKSPACE"`, the canonical scanner in `packages/security`, mounted read-only into the runner. It runs before install, lint or build. Release builds run it on the exact tree they build. Config files execute during an ordinary install or build, so a build is not a read-only inspection.
3. **Image per component, tagged by full commit SHA.** Use multi-stage, version-pinned Dockerfiles built for `linux/amd64`, with tags `<component>-<40-char sha>` in the product's DOCR repository. App Platform refuses a never-deployed `image.digest` with "not configured for this app". So the app spec references the SHA tag, and the release step checks that the tag resolves to the pushed digest before the spec update and again after the deployment is ACTIVE. It records the digest in the release record.
4. **No socket, no secrets on the CI runner.** A job builds images through its repository's private BuildKit daemon:

   ```bash
   docker buildx create --name sh-ci --driver remote tcp://buildkitd:1234 --use
   docker buildx build --platform linux/amd64 --output type=cacheonly ...
   ```

5. **Scripted CD until a scoped token exists.** Automated deploy needs a custom-scoped DigitalOcean token (`registry:read`, `registry:update`, `app:read`, `app:update`, `app:create`). It is created in the control panel, which only the owner can do, and stored as the `production` environment secret, readable only by `main`. Until then the release script runs from the operator workstation:
   - It confirms that CI passed on the exact `main` SHA.
   - It builds on the build droplet's Docker context and pushes with `doctl registry login --expiry-seconds 1800`.
   - It moves every component and PRE_DEPLOY job to the new tag. Secrets stay as the encrypted values the live spec returns.
   - It waits for ACTIVE, verifies the digests, smoke-tests the production domain and records the release.

   The workflow's `release` job is gated on `vars.CD_ENABLED == 'true'`. Never put an operator's full-access token in GitHub.
6. **Rollback.** Record the live deployment ID before every cutover. Roll back by redeploying a recorded SHA tag, or by calling `POST /v2/apps/{id}/rollback` with `skip_pin: true`, targeting one of the last 10 successful deployments. Rollback restores code, not data. Database rollback is a separate, backup-verified procedure.
7. **Static sites remain `static_site` components.** App Platform cannot serve a static site from an image. Turn off `deploy_on_push`. CI gates the change, and the release script runs `doctl apps create-deployment` and then verifies that the deployed commit equals the SHA.
8. **One environment per product.** No staging apps on DigitalOcean. The only exception is the product the operator policy names.

## Runner kit (`ci/do-runner/`)

`sh-ci` runs on the build droplet as root from `/srv/work/sh-ci/bin/sh-ci`. It gives each repository a compose project `sh-ci-<repo>`:

| Service | Purpose |
| --- | --- |
| `runner` | `ghcr.io/actions/actions-runner`, pinned by digest. Persistent registration `do-sh-build-<repo>`, labels `self-hosted, do-sh-build, sh-ci-<repo>`. `_work` is on tmpfs and wiped at every job start by `job-started.sh`. 8 CPUs, 16 GB. |
| `buildkitd` | The repository's own BuildKit daemon. The daemon is privileged, but build steps run in BuildKit's unprivileged sandboxes with insecure entitlements off. It is reachable only on the project network. |
| `postgres` (`--postgres` / `--pgvector`) | Postgres 18, or pgvector on Postgres 18, on tmpfs with trust auth: `TEST_POSTGRES_URL=postgresql://postgres@postgres:5432/ci` |
| `valkey` (`--valkey`) | Valkey 8, no persistence: `TEST_REDIS_URL=redis://valkey:6379/0` |

Register or update from a workstation with repository admin:

```bash
gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token --jq .token \
  | ssh <build-host> /srv/work/sh-ci/bin/sh-ci up <repo> --postgres --valkey
ssh <build-host> /srv/work/sh-ci/bin/sh-ci status
```

- The one-hour bootstrap token is read from stdin, used once and deleted. The runner keeps only its own registration credential, in a 0700 state directory.
- Runners are persistent because a personal account supports repository-level runners only, and ephemeral or JIT registration needs an admin credential for every job. With a GitHub App holding Administration: write, switch to `generate-jitconfig` per job.
- Runners are registered with `--disableupdate`. GitHub stops dispatching to a runner more than 63 days behind the latest release, which is longer than the remaining life of the droplet.
- Containers use `restart: on-failure`. No unit is enabled at boot. Run `sh-ci up <repo>` after a droplet reboot.
- Teardown before 2026-11-30: run `sh-ci rm <repo>` for every repository, then delete each runner registration under Settings, Actions, Runners.

## AWS target (2026-12-01)

| DigitalOcean | AWS |
| --- | --- |
| App Platform service or job | ECS Express Mode (Fargate, one shared ALB with host rules). App Runner has been closed to new customers since 2026-04-30. |
| DOCR | ECR (push the same SHA-tagged images) |
| Managed PostgreSQL 18 | RDS for PostgreSQL 18. Use logical replication; test publication rights first, because DigitalOcean does not grant superuser. Fallback: `pg_dump`/`pg_restore` under a write freeze. |
| Managed Valkey | ElastiCache Serverless Valkey, or none if it is only a cache |
| App secrets | SSM Parameter Store or Secrets Manager, referenced by name |
| Static site | S3 with CloudFront, or Amplify Hosting |
| CI runner | CodeBuild-hosted GitHub Actions runner (`vars.CI_RUNS_ON`) |

Order of operations:
1. Lower DNS TTLs 48 hours ahead.
2. Rehearse in an AWS staging stack by 2026-11-27.
3. Cut over only after backups and data reconciliation pass.
4. Keep DigitalOcean for a rollback window and get approval before deleting anything there.
