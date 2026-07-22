---
name: digitalocean-droplets
description: Manage DigitalOcean Droplets, SSH keys, images, snapshots, sizes, power actions, rebuilds, restores, resizes, backups, IPv6/private networking, and tag-based fleet operations. Use when asked to create, inspect, troubleshoot, modify, or clean up a DO VM or remote development box.
---

# DigitalOcean Droplets

## Requirements

- Use the authenticated `doctl` CLI for all Droplet operations.
- Use direct DigitalOcean v2 API calls only when `doctl` lacks the needed operation.
- Read API credentials from the environment for API fallback; never print or persist them.
- `doctl` must already be authenticated before changing resources.

## Portfolio Defaults

- Default dev/Codex region: `nyc3`.
- Default dev/Codex size: `s-2vcpu-4gb`.
- Default image: current Ubuntu LTS, unless a validated account image is explicitly requested.
- Default tags for temporary development Droplets: `codex,dev`.
- Enable monitoring on new Droplets unless the user asks otherwise.

## Safety Rules

- Always read current state before making changes: list/get Droplets, SSH keys, images, and relevant tags first.
- Never delete, rebuild, resize down, restore, reset password, or power off a production-looking Droplet without an explicit user request naming the target.
- Before destructive or high-risk changes, capture the Droplet id, name, region, image, size, tags, public IPs, private IPs, and backup/snapshot status in the response or working notes.
- Recommend a snapshot before rebuilds, restores, major package work, filesystem changes, or risky incident remediation.
- Treat tag-based bulk actions as destructive unless the user explicitly scopes the tag and action.
- Do not print tokens, private SSH keys, Spaces secrets, or cloud-init secrets.

## Inventory Workflow

1. List Droplets and note id, name, status, region, size, image, tags, VPC, IPv4, IPv6, and monitoring.
2. List SSH keys and available sizes/images when provisioning or resizing.
3. Check snapshots/backups before rebuild, restore, or deletion.
4. For app incidents, correlate Droplet state with networking, DNS, firewall, load balancer, and project membership.

## Provisioning Workflow

1. Confirm name, region, size, image, tags, VPC, and SSH key source.
2. Reuse an existing SSH key when appropriate; otherwise import a dedicated public key.
3. Create with monitoring enabled and minimal required tags.
4. Poll until active and public IPv4 is assigned.
5. Verify SSH readiness before handing back access details.
6. Return cleanup instructions including the exact Droplet id.

## Common `doctl` Commands

```powershell
doctl compute droplet list -o json
doctl compute droplet get <droplet_id> -o json
doctl compute ssh-key list -o json
doctl compute ssh-key import <key_name> --public-key-file <pub_key_path>
doctl compute size list
doctl compute image list-distribution
doctl compute image list-user -o json
doctl compute droplet create <name> --region nyc3 --size s-2vcpu-4gb --image ubuntu-24-04-x64 --ssh-keys <key_id> --enable-monitoring --tag-names codex,dev
doctl compute droplet-action snapshot <droplet_id> --snapshot-name <snapshot_name>
doctl compute droplet-action reboot <droplet_id>
doctl compute droplet-action shutdown <droplet_id>
doctl compute droplet-action power-on <droplet_id>
doctl compute droplet-action resize <droplet_id> --size <size_slug> --resize-disk=true
doctl compute droplet delete <droplet_id>
```

## Troubleshooting

- If SSH fails, check Droplet status, public IPv4, firewall rules, cloud-init progress, SSH key fingerprint, and local `~/.ssh/config`.
- If provisioning fails, inspect account limits, region availability, size availability, image slug validity, VPC selection, and SSH key ids.
- If performance is degraded, inspect CPU, memory, disk, network, and monitoring metrics before resizing.
- If network reachability fails, check DNS, reserved IPs, firewalls, VPC/private networking, IPv6 state, and load balancers.
- If cleanup is requested, delete only the named Droplet and preserve reusable SSH keys unless the user explicitly requests key deletion.
