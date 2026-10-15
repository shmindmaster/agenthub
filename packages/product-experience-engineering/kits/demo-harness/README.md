# Demo harness — `demo-harness/v1`

The product-side half of a demo: what a product repository provides so anyone
(or any agent) can bring it up hidden, reset it to the exact take, prove which
build is on screen, prove the data is synthetic, and know what may be claimed.
It is the engineering contract behind
[`prepare-product-for-demo`](../../skills/prepare-product-for-demo/SKILL.md)
criterion 8 ("deterministic and resettable") and the handoff fields
`seeded synthetic fixture plus reset command` and `assessed revision`.

Capture is not here. Playwright + Recast recording belongs to `media-studio`
and runs from an external job workspace (`scaffold-video-workspace.mjs`
writes a `capture/scenes.mjs` skeleton that reads this harness file
read-only). The product repository never holds media capture code.

## 1. `demo/harness.json`

One file at the product root, validated by
[`harness.schema.json`](harness.schema.json) and by
`node scripts/validate-demo-harness.mjs <repo>`:

```json
{
  "harnessVersion": "demo-harness/v1",
  "product": "example-app",
  "demoTenant": { "id": "…fixed id…", "name": "Example Demo Org" },
  "reset": { "full": "pnpm demo:reset", "beat": null },
  "services": [
    { "name": "api", "cwd": "apps/api", "command": "poetry run uvicorn main:app --port 8000",
      "readyUrl": "http://127.0.0.1:8000/health/live", "env": { "APP_ENV": "local" } }
  ],
  "baseUrl": "http://127.0.0.1:5173",
  "versionEndpoints": [{ "service": "api", "url": "http://127.0.0.1:8000/api/version" }],
  "syntheticLabel": { "testId": "synthetic-data-label", "text": "Synthetic demo data" },
  "truthTable": "docs/demo/TRUTH_TABLE.md",
  "smokeSpec": "apps/web/tests/e2e/demo-harness.spec.ts"
}
```

`env` values are literals for local demo flags only. Secrets are never written
here; a service that needs a key reads it by name from the user environment.

## 2. Reset command

- `reset.full` restores the demo tenant to the exact take in one command:
  clean or drop the demo tenant, migrate, seed, verify. It touches only the
  demo tenant, refuses a wrong database or a non-demo tenant id with a non-zero
  exit and no change, and prints a JSON line with the tenant id, counts and a
  seed fingerprint. Two consecutive resets print the same fingerprint.
- `reset.beat` (optional) restores the preconditions one beat consumes,
  without a full reseed.
- By convention the repo also exposes them as `demo:reset` and
  `demo:reset:beat` package scripts.

## 3. Synthetic-data label

Every screen of the demo tenant renders a visible element with
`data-testid="synthetic-data-label"` whose text contains "Synthetic". It is
part of the product UI, in the product's own design system, shown only for the
demo tenant, and never removed for a recording. API responses for the demo
tenant may also carry `X-Data-Classification: synthetic`.

## 4. Truth table

`docs/demo/TRUTH_TABLE.md`, from [`TRUTH_TABLE.template.md`](TRUTH_TABLE.template.md),
has exactly three sections, in this order:

- **Demonstrate now**: what runs today on the real path. Every row names the
  evidence: a test, a file, or an endpoint that exists in the repo.
- **Build next**: real, planned, not yet on the product path. Never shown as working.
- **Do not claim**: things a viewer might infer that are false or not
  cleared (outcomes, legal or clinical advice, customers, certifications,
  metrics without a source).

Narration, captions and case studies may only claim rows in "Demonstrate now".

## 5. Deployed-SHA endpoint

Each service exposes `GET /api/version` (or the URL named in
`versionEndpoints`), unauthenticated, cache-control `no-store`, returning
[`deployed-version.schema.json`](deployed-version.schema.json):

```json
{ "schema": "deployed-version/v1", "service": "example-api", "version": "1.0.0",
  "gitSha": "7bb1a1c389cb3494613f82f13cea75ff2b460875", "builtAt": "2026-10-14T18:02:11Z",
  "environment": "production" }
```

`gitSha` is the full 40-character commit, resolved at build or deploy time
(`GIT_SHA`, `COMMIT_SHA`, a platform variable such as `RAILWAY_GIT_COMMIT_SHA`
or `VERCEL_GIT_COMMIT_SHA`, or a `.release` file written by the build). When it
cannot be resolved the field is `"unknown"`, and the smoke spec fails for a
viewer-facing capture. The film records the SHA it was shot against.

## 6. Smoke spec

A product-owned Playwright spec (template:
[`demo-harness.smoke.spec.ts`](demo-harness.smoke.spec.ts)) run after every
reset: the version endpoints answer with a real SHA, the synthetic label is
visible on the first screen of each role, and each "Demonstrate now" fact the
film depends on is asserted. It is an engineering test, kept in the product's
normal e2e folder, not media capture code.

## 7. Hidden runner

`node scripts/demo-stack.mjs up --repo <path>` starts every service in
`services` as a windowless child (no console window, no focus change), waits
for each `readyUrl`, writes logs and state under
`%LOCALAPPDATA%\AgentHub\demo-stack\<product>\`, and supervises until
`node scripts/demo-stack.mjs down --repo <path>` (or the runner is stopped),
which ends the whole process tree. Agents launch `up` as a background command.
`status` reports each service's readiness. No scheduled task, Run key or
service is registered; nothing survives `down`.

On Windows the runner relies on `CREATE_NO_WINDOW` (Node `windowsHide`) on
non-detached children: the shell and every console program it starts share
one hidden console. `conhost --headless` was tested and rejected for this use
because it ends its session when its standard input closes.
