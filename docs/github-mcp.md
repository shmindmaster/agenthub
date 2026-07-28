# GitHub MCP Fleet Contract

## Decision

The canonical GitHub MCP capability is the GitHub-hosted remote server:

- owner: `registry/mcps.json` entry `github`
- endpoint: `https://api.githubcopilot.com/mcp/`
- account: `shmindmaster`
- credential reference: `GITHUB_MCP_SHMINDMASTER_TOKEN`
- token storage: outside this repository and every generated adapter

GitHub's released server does not provide native automatic routing across
multiple GitHub accounts. Running separate server registrations for each
account is technically possible, but GitHub maintainers warn that duplicate
tool surfaces can confuse clients and agents. Until native routing is released,
the fleet uses the user-approved fallback account, `shmindmaster`.

## Host ownership

`Sync-AgentCapabilities.ps1` renders the canonical registration into each
active host's native format. OpenCode Desktop inherits the OpenCode
configuration. Antigravity Desktop and Antigravity IDE inherit the Antigravity
configuration. GitHub Copilot CLI keeps its built-in `github-mcp-server`;
the synchronizer must not add a duplicate custom server there.

Cursor remains owner-disabled and is not part of this active registration.
Other inactive hosts are not configured by this capability until reactivated
and revalidated.

## Authentication

The repository and generated host files contain only an environment reference.
They never contain a bearer token. The environment value must belong to
`shmindmaster`.

For a non-persistent validation shell, resolve the existing GitHub CLI
credential into the current process only:

```powershell
$env:GITHUB_MCP_SHMINDMASTER_TOKEN = gh auth token --user shmindmaster
```

Clear it when validation is finished:

```powershell
Remove-Item Env:GITHUB_MCP_SHMINDMASTER_TOKEN
```

Persisting or rotating a credential requires explicit owner authorization.

## Verification

```powershell
powershell.exe -NoProfile -File .\tests\Sync-AgentCapabilities.Tests.ps1
pwsh -NoProfile -File .\scripts\Sync-AgentCapabilities.ps1 -Apply -Validate
pwsh -NoProfile -File .\scripts\Test-McpSecrets.ps1
pwsh -NoProfile -File .\scripts\Test-McpLiveness.ps1
```

Configuration validation proves schema and secret hygiene. A successful
authenticated MCP `initialize` request proves the remote endpoint and account
credential work. Host restart and host-native MCP status checks remain
separate runtime gates.

## Official sources

- [GitHub MCP Server README](https://github.com/github/github-mcp-server/blob/main/README.md)
- [Installation guides](https://github.com/github/github-mcp-server/tree/main/docs/installation-guides)
- [Remote server documentation](https://github.com/github/github-mcp-server/blob/main/docs/remote-server.md)
- [Open multi-account routing request](https://github.com/github/github-mcp-server/issues/1940)
