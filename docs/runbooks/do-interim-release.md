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
3. **A runner only for what the native build cannot run.** Database, tenant-isolation, security and critical business-rule integration tests that need Postgres or Valkey run before merge on the product's existing runner (see the runner section below; no new runners). That job runs only those tests. It has no image build, no registry access and no secrets. A product without such tests has no runner.
4. **Prove the gate can fail.** Before relying on a check:
   - Build the exact Dockerfile or build command with a deliberately failing check, and show that the build fails.
   - Use a disposable Daytona v2 box for this (`node scripts/daytona-run.mjs --owner <project> -- <command>`; Docker Engine runs inside it), or a short-lived verification app from a throwaway branch, deleted the same hour.
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

## Pre-merge runners on the droplet

The existing product CI runners on the DigitalOcean droplet still serve product CI. That is the one exception to the rule that nothing uses the droplet, and it lasts until those jobs move. No new work goes there: new repositories, new runners and new job types do not use it. Migration off the droplet is tracked in Linear CORE-107.

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
