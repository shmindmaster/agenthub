---
name: digitalocean-app-platform
description: Use when DigitalOcean App Platform apps need inspection or changes involving specs, deployments, logs, environment variables, databases, scaling, domains, or health checks.
---

# DigitalOcean App Platform

## Workflow

1. Identify the app from repo, app name, domain, or app id. If ambiguous, run `doctl apps list -o json`.
2. Inspect before editing:
   - `doctl apps get <app_id> -o json`
   - `doctl apps spec get <app_id>`
   - `doctl apps list-deployments <app_id> -o json`
3. For live changes, base the update on `doctl apps spec get <app_id>`, not a tracked template that may omit encrypted secrets.
4. Use `doctl apps propose --app <app_id> --spec <spec>` before `doctl apps update`.
5. After deploying or updating, verify deployment status, app health endpoint, and relevant custom domains.
6. Never print raw secret values. Preserve `EV[...]` encrypted values from live specs.

## Portfolio App Map

- `verigence`: `84714e3b-632b-4e05-aebb-c1d814c41f76`, repo `shmindmaster/verigence`, components `api`, `web`, `admin`.
- `subops`: `3dc23de1-dadc-49df-8683-7997f4692537`, repo `shmindmaster/subops`, components `subops-frontend`, `subops-core-api`.
- `abacare`: `908ce9fc-f5df-4f90-91a6-79f04e212e29`, repo `shmindmaster/abacare`, components `web`, `api`.
- `coledger`: `6784bf5f-afb7-4177-83e5-837e7e01d9ed`, repo `shmindmaster/coledger`, components `web`, `api`.
- `gentlenext`: `e46545ee-3a8a-42e7-a3be-70bdb1089895`, repo `shmindmaster/gentlenext`, components `web`, `api`.
- `lawli`: `006a9176-a98c-4746-ad55-dc1d887f99ef`, repo `shmindmaster/lawli`, components `web`, `api`.
- `lexalign`: `add34a2b-dbb6-4a11-af0a-7ddaacfe267c`, repo `shmindmaster/lexalign`, components `web`, `api`.

Refresh this map with `digitalocean-portfolio/scripts/inventory-digitalocean.ps1` before relying on it.

## Commands

```powershell
doctl apps list -o json
doctl apps get <app_id> -o json
doctl apps spec get <app_id> > live.yaml
doctl apps list-deployments <app_id> -o json
doctl apps logs <app_id> <component> --type run
doctl apps logs <app_id> <component> --type build
doctl apps create-deployment <app_id>
```

## Repo Guidance

Before touching a repo, read its local `AGENTS.md` and any `docs/runbooks/platform-operations.md`. Several repos already document DO-specific secret handling and deployment scripts.
