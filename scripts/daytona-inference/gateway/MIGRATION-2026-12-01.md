# Permanent Inference Gateway Migration Guide (Pre-2026-12-01 Teardown of sh-forge)

> **Status (2026-11-25):** Migrated off `sh-forge` to dedicated persistent DigitalOcean droplet **`sh-inference`** (`64.225.2.73`, `s-2vcpu-4gb`, `nyc3`, firewall `sh-inference-fw`, `SH_FORGE_SSH_HOST=sh-inference`). Both `inference.shtrial.com` (LiteLLM + Postgres + Caddy) and `studio.shtrial.com` (Open WebUI + `daytona_media_lab` tool) run under `/opt/agenthub/` and `/opt/forge/caddy/` on `sh-inference`. `sh-forge` containers/volumes remain untouched as rollback evidence until the scheduled `2026-12-01` teardown.

`sh-forge` is scheduled for teardown on **2026-12-01**. Because all coding agents point at `https://inference.shtrial.com/v1` and DNS is managed in DigitalOcean (`shtrial.com`), migrating the gateway off `sh-forge` required **zero changes** to coding-agent configs or `gpu.py` aliases.

## Target Host Requirements
- Small persistent CPU server (for example, a dedicated 2 vCPU / 4 GB DigitalOcean droplet in `nyc3`, or AWS EC2/Lightsail) with Docker + Docker Compose and Caddy (ports 80/443 open).
- Static IPv4 address (`<NEW_GATEWAY_IP>`).

## Migration Procedure

1. **Back up LiteLLM Postgres state on `sh-forge`:**
   ```bash
   ssh forge 'docker exec agenthub-litellm-db pg_dump -U litellm -d litellm > /tmp/litellm-backup.sql'
   ```
2. **Copy gateway stack + `.env` + backup to the new host:**
   - Copy `/opt/forge/inference-gateway/` (including `.env`, `docker-compose.yml`, `litellm-config.yaml`, `reasoning_normalizer.py`) and `/tmp/litellm-backup.sql` to `/opt/agenthub/inference-gateway/` on the new host (`chmod 600 .env`).
   - Remove `/tmp/litellm-backup.sql` from `sh-forge` after transfer.
3. **Start Postgres first and restore data on the new host:**
   ```bash
   cd /opt/agenthub/inference-gateway
   docker compose up -d litellm-db
   # wait until healthy, then restore:
   docker exec -i agenthub-litellm-db psql -U litellm -d litellm < litellm-backup.sql
   rm -f litellm-backup.sql
   docker compose up -d litellm
   ```
4. **Configure Caddy on the new host** using `Caddyfile.snippet` (with the owner IP), validate, and reload Caddy.
5. **Switch DNS A record in DigitalOcean (`shtrial.com`):**
   ```powershell
   doctl compute domain records list shtrial.com --format ID,Type,Name,Data
   doctl compute domain records update shtrial.com --record-id <INFERENCE_RECORD_ID> --record-data <NEW_GATEWAY_IP> --record-ttl 300
   ```
6. **Verify end-to-end without editing any coding agent:**
   ```powershell
   python "$env:USERPROFILE\.config\opencode\daytona\gpu.py" doctor
   python "$env:USERPROFILE\.config\opencode\daytona\gpu.py" reconcile
   ```
