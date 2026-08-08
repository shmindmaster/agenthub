---
name: digitalocean-dns
description: Use when DigitalOcean DNS zones, application routing, mail records, certificates, or a DNS cutover needs inspection, troubleshooting, or change.
---

# DigitalOcean DNS

## Workflow

1. Resolve the zone first with `doctl compute domain list -o json`.
2. Inspect records with `doctl compute domain records list <zone> -o json`.
3. For App Platform domains, compare DO DNS records against `doctl apps get <app_id> -o json`.
4. Keep apex, `www`, `api`, `admin`, `clerk`, `accounts`, mail, DKIM, SPF, and DMARC records distinct.
5. Prefer low-risk edits: create replacement records, verify, then remove stale records when needed.
6. For destructive DNS changes, capture current records first and include a rollback command.

## Known Zones

`abacare.ai`, `coledger.ai`, `crewscore.ai`, `documed.ai`, `empowera.ai`, `gentlenext.ai`, `lawli.ai`, `lexalign.ai`, `mahumtech.com`, `saroshhussain.com`, `shtrial.com`, `subops.ai`, `verigence.ai`, `warrantygains.ai`.

## Patterns

- App subdomains often CNAME to App Platform default ingress hosts such as `*.ondigitalocean.app`.
- Some apex records use Cloudflare A/AAAA values, so do not replace apex routing just because the app is on DO.
- `shtrial.com` includes Railway verification and CNAME records for lienwise-related subdomains.
- Mail and auth records for Microsoft 365 and Clerk should be preserved unless the task explicitly targets them.

## Commands

```powershell
doctl compute domain list -o json
doctl compute domain records list <zone> -o json
doctl compute domain records create <zone> --record-type CNAME --record-name api --record-data <target>.
doctl compute domain records delete <zone> <record_id> --force
```
