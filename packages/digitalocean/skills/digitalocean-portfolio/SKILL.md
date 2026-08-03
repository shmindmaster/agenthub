---
name: digitalocean-portfolio
description: Use when DigitalOcean account-wide apps, projects, repositories, DNS, databases, Spaces, inference configuration, ownership, or operational posture needs inventory or audit.
---

# DigitalOcean Portfolio

## Workflow

1. Verify local access with `scripts/ensure-do-env.ps1`; use `-PersistUser` when the user asks to set environment variables for future Codex sessions.
2. Read `references/portfolio.md` for the known repo/app/service map.
3. Refresh live inventory before making claims: run `scripts/inventory-digitalocean.ps1`.
4. Use the authenticated `doctl` CLI as the primary interface. If `doctl` lacks an operation, use a direct DigitalOcean v2 API call with the token already present in the environment. Do not use or expect a DigitalOcean MCP server.
5. Treat live App Platform secrets as sensitive. Never print raw token values, database URLs, Spaces secret keys, or encrypted `EV[...]` payloads.
6. For mutation requests, summarize the intended change, inspect current state, make the smallest change, and verify with a readback.

## Access Policy

- Run `doctl` commands first and prefer `-o json` for machine-readable output.
- Use `Invoke-RestMethod` against `https://api.digitalocean.com/v2` only when the CLI lacks the needed endpoint.
- Read API credentials from environment variables; never print or persist raw tokens.
- Treat CLI/API responses as sensitive when they contain app specs, connection strings, Spaces keys, or encrypted `EV[...]` values.

## Portfolio Defaults

- Primary repos are under `C:\Repos\shmindmaster`.
- Main production DO apps are `verigence`, `abacare`, `coledger`, `gentlenext`, `lawli`, `lexalign`, and `subops`.
- `sabhi` is currently DNS/Railway-oriented in discovery, not a DO App Platform app.
- Shared services are `sh-postgres`, `sh-valkey`, `sh-storage`, and `sh-verigence-prd`.
- Most app domains are DO-managed zones with `www`/`api` records pointing to App Platform default ingress hosts.

## Handoffs

- Use `digitalocean-app-platform` for app specs, deployments, logs, scaling, and runtime envs.
- Use `digitalocean-dns` for zones, records, domain validation, and mail/auth DNS.
- Use `digitalocean-data-storage` for Managed DB, Valkey, Spaces, and inference env checks.
- Use `digitalocean-incident-response` for outages, failed deploys, bad health checks, or performance incidents.
- Use `digitalocean-provision-droplet` only for creating Codex-ready DO droplets.
