# Hosting provider routing

Resolve the hosting provider from the applicable operator policy and the product's
authorized release runbook before choosing a deployment tool. An installed Railway
plugin is a provider-specific capability, not the default for an unspecified deploy.
Keep provider integrations available when a policy reserves them for later authorized
work; changing the current route does not authorize uninstalling them or changing
client-project routes.

For DigitalOcean, use the product's native release scripts and `doctl`. The existing
`do-app-platform-skills` entry in `registry/native-connectors.json` identifies the
official upstream design and migration skills; its host-channel observations are not
proof of an installed skill. The former `packages/digitalocean` overlay is retired.
Do not invent a replacement plugin, restore the retired package, or install a catalog
merely to perform operations supported by the native CLI.

Temporary validation compute and persistent product hosting are separate decisions.
Follow the operator's compute policy for bounded validation; a sandbox is not a
production deployment. Confirm the exact source revision, persistent data and domain
routing before claiming a hosting cutover.
