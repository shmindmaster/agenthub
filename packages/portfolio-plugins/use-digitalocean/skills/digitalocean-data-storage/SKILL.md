---
name: digitalocean-data-storage
description: Operate DigitalOcean Managed Databases, Valkey, Spaces, and DO inference environment variables for the SH portfolio. Use for Postgres databases/users/firewalls, Valkey bindings, Spaces bucket checks, S3-compatible envs, per-app storage prefixes, and DO inference model/key readiness.
---

# DigitalOcean Data Storage

## Workflow

1. Check local env readiness with `digitalocean-portfolio/scripts/ensure-do-env.ps1`.
2. List managed databases with `doctl databases list -o json`.
3. Inspect cluster details, users, DB names, pools, and firewall rules before changing anything.
4. For App Platform bindings, prefer bindable values like `${sh-postgres.DATABASE_URL}` and `${sh-valkey.DATABASE_URL}` in app specs.
5. For Spaces, use AWS-compatible commands with `--endpoint-url $env:AWS_ENDPOINT_URL_S3`.
6. For DO inference, validate base URL and models without printing the API key.

## Known Services

- `sh-postgres`: Postgres 18, shared production cluster with app databases such as `abacare`, `subops`, and others.
- `sh-valkey`: Valkey 8, shared production cache.
- `coledger-db` and `coledger-cache`: app-scoped bindables in the `coledger` App Platform spec.
- `sh-storage`: shared Spaces bucket in `nyc3`.
- `sh-verigence-prd`: Verigence production Spaces bucket in `nyc3`.

## Spaces Checks

```powershell
aws s3 ls "s3://$env:DO_SPACES_BUCKET" --endpoint-url $env:AWS_ENDPOINT_URL_S3 --region $env:AWS_REGION
aws s3 ls "s3://sh-storage" --endpoint-url "https://nyc3.digitaloceanspaces.com" --region "nyc3"
```

`ListBuckets` may be denied for scoped Spaces keys. A bucket-specific `aws s3 ls s3://bucket` result is the useful check.

## Secret Handling

Never print `DATABASE_URL`, `VALKEY_URL`, `DO_INFERENCE_API_KEY`, Spaces secret keys, or full App Platform `EV[...]` values. When reporting, say present/missing, bound/unbound, or scoped/unscoped.
