# SH DigitalOcean Portfolio

Use this as the starting map. Refresh live data before making changes because App Platform specs, deployments, DNS records, and secrets change frequently.

## Primary Repos

| Repo | Local path | Live DO app | Notes |
| --- | --- | --- | --- |
| verigence | `C:\Repos\shmindmaster\verigence` | `verigence` / `84714e3b-632b-4e05-aebb-c1d814c41f76` | `.do/app.yaml`, `api`, `web`, `admin`, shared Postgres/Valkey, dedicated `sh-verigence-prd` space. |
| abacare | `C:\Repos\shmindmaster\abacare` | `abacare` / `908ce9fc-f5df-4f90-91a6-79f04e212e29` | `.do/app.yaml`, `web`, `api`, shared Postgres/Valkey. |
| coledger | `C:\Repos\shmindmaster\coledger` | `coledger` / `a892742b-024b-4e1d-b8f9-954488c1a9cb` | App-scoped aliases `coledger-db` and `coledger-cache` bind shared `sh-postgres` and `sh-valkey`; separate logical database/user. |
| gentlenext | `C:\Repos\shmindmaster\gentlenext` | `gentlenext` / `e46545ee-3a8a-42e7-a3be-70bdb1089895` | Shared Postgres/Valkey. |
| lawli | `C:\Repos\shmindmaster\lawli` | `lawli` / `006a9176-a98c-4746-ad55-dc1d887f99ef` | `.do/app.yaml`, shared Postgres/Valkey. |
| lexalign | `C:\Repos\shmindmaster\lexalign` | `lexalign` / `add34a2b-dbb6-4a11-af0a-7ddaacfe267c` | `.do/app.yaml`, shared Postgres/Valkey. |
| subops | `C:\Repos\shmindmaster\subops` | `subops` / `3dc23de1-dadc-49df-8683-7997f4692537` | `.do/app.yaml`, `subops-frontend`, `subops-core-api`, shared Postgres/Valkey, `sh-storage`. |
| lienwise | `C:\Repos\shmindmaster\lienwise` | `lienwise` / `2a07f105-f105-44e1-8da6-b5bf0e8a9dfb` | ACTIVE readback 2026-09-14; own database/user on `sh-postgres`, shared `sh-valkey`. |
| warrantygains | `C:\Repos\shmindmaster\warrantygains` | `warrantygains` / `7a3cfdf3-4666-4b73-bcef-daab3358183a` | ACTIVE readback 2026-09-14; own database/user on `sh-postgres`. |

The 2026-09-14 App Platform readback also returned ACTIVE apps for `mahumtech`,
`saroshhussain`, `tgiagency` and the retired `shtrial` redirect. These are provider
deployment states; lifecycle, health, credentials and application access need
their own evidence. The ABACare live spec includes a Phoenix service/database
that its tracked historical spec intentionally omits; do not apply that record
as a complete replacement. Older DNS/Spaces notes below were not reverified by
this metadata-only readback.

## Shared Services

- Projects: `platform-shared`, `apps-prd`, `static-sites-prd`.
- Managed databases: `sh-postgres` Postgres 18 in `nyc1`; `sh-valkey` Valkey 8 in `nyc1`.
- Spaces: `sh-storage` in `nyc3`; `sh-verigence-prd` in `nyc3`.
- Spaces access: AWS-compatible envs are used for object listing and app integration.
- Container registry: latest discovery returned no DOCR registry.

## DNS Zones

Managed in DigitalOcean: `abacare.ai`, `coledger.ai`, `crewscore.ai`, `documed.ai`, `empowera.ai`, `gentlenext.ai`, `lawli.ai`, `lexalign.ai`, `mahumtech.com`, `saroshhussain.com`, `shtrial.com`, `subops.ai`, `verigence.ai`, `warrantygains.ai`.

Several apex records use Cloudflare anycast A/AAAA targets while app subdomains commonly CNAME to `*.ondigitalocean.app`. Do not assume apex records point directly to App Platform.

## Required Local Environment

- `doctl` authenticated with the target team.
- For API fallback, use `DIGITALOCEAN_API_TOKEN`, `DO_API_TOKEN`, or `DIGITALOCEAN_ACCESS_TOKEN` from the environment.
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL_S3`, and `AWS_REGION` for Spaces checks.
- `DO_SPACES_*` variables for app-facing Spaces conventions.
- `DO_INFERENCE_*` variables for app AI runtime checks.

Do not print token, secret, connection string, or encrypted App Platform secret values in final answers.
