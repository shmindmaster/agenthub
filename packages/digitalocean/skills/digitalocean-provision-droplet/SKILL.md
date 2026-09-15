---
name: digitalocean-provision-droplet
description: Use when a Codex-ready or temporary DigitalOcean remote development machine and its SSH access must be provisioned with doctl.
---

# DigitalOcean Provision Droplet

## Requirements

- Use `doctl` for inventory and deterministic provisioning steps. Use the DigitalOcean v2 API only when a required operation is not exposed by `doctl`.
- `doctl` must be installed and authenticated.
- Local `ssh` and `ssh-keygen` must be available.
- Default region is `nyc3`; default size is `s-2vcpu-4gb`.
- Droplets bill until deleted. Tell the user the droplet name/id and cleanup command.

## Workflow

1. Confirm defaults or requested region/size.
2. Generate an SSH key pair under the user's `.ssh` directory with a `codex-<slug>` name.
3. Upload the public key with `doctl compute ssh-key import`.
4. Create the droplet with `doctl compute droplet create`.
5. Poll `doctl compute droplet get <id> -o json` until active and public IPv4 is present.
6. Add an SSH host entry for root using the generated private key.
7. Wait for cloud-init/SSH readiness with `ssh -o BatchMode=yes <alias> true`.
8. Return the Codex add-SSH-host deeplink.

## Commands

```powershell
doctl compute ssh-key import <key_name> --public-key-file <pub_key_path>
doctl compute droplet create <name> --region nyc3 --size s-2vcpu-4gb --image ubuntu-24-04-x64 --ssh-keys <key_id> --enable-monitoring --tag-names codex,dev
doctl compute droplet get <droplet_id> -o json
doctl compute droplet delete <droplet_id>
```

Use the DigitalOcean Codex Universal image only if its current image id is known from trusted local documentation or a fresh account image lookup. Otherwise use current Ubuntu LTS and bootstrap normally.
