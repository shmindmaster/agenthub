# AH-Daytona

Run heavy, parallel or untrusted work in Daytona cloud sandboxes. One skill, no MCP server and no hook, so nothing runs until a sandbox is needed.

The key comes from `DAYTONA_API_KEY` in the environment and is never written to a file.

Hosts whose own catalog carries Daytona use that plugin instead. See `docs/runbooks/plugin-deployment.md`.

To refresh, copy the listed references from `daytona/skills`, keep the Fleet rules section, and update the commit in `NOTICE`.