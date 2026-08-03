---
name: digitalocean-incident-response
description: Use when a DigitalOcean deployment fails, a service is down, health checks or certificates fail, storage is unreachable, resource usage spikes, or rollback is being considered.
---

# DigitalOcean Incident Response

## Triage Order

1. Identify blast radius: one app/component, one domain, shared DB/cache/Spaces, or account/platform-wide.
2. Capture state:
   - `doctl apps get <app_id> -o json`
   - `doctl apps list-deployments <app_id> -o json`
   - `doctl apps logs <app_id> <component> --type run`
   - `doctl apps logs <app_id> <component> --type build`
3. Check health endpoints and custom domains from outside the app.
4. Inspect recent spec/env/deployment changes before changing code.
5. If shared services are implicated, inspect `sh-postgres`, `sh-valkey`, and relevant Spaces bucket access.
6. Apply the smallest reversible fix: redeploy, restore prior spec value, scale component, fix DNS record, or roll forward code.
7. Verify with deployment status, logs, health endpoint, and DNS/cert status.

## Common Signals

- Build failure: inspect build logs and repo lockfile/Dockerfile changes.
- Immediate runtime exit: check run command, `PORT`, missing required envs, database binding, and startup logs.
- `502`/health failure: check component port, health path, startup delay, and app binding to `0.0.0.0`.
- DB failures: check bindable env, database user/db name, trusted sources/firewall, and SSL flags.
- DNS/cert failure: compare App Platform domain state with DO zone records and CNAME targets.
- OOM or high CPU: inspect available usage through `doctl` or the DigitalOcean v2 API, then scale only after confirming app behavior.

## Escalation Packet

Before involving DigitalOcean support, collect app id, deployment id, component, UTC timestamps, region, current spec, relevant logs, and exact failing URL/domain. Redact secrets.
