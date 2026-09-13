# Security

## Reporting

Report a vulnerability privately to the repository owner. Do not open a public issue that includes tokens, customer data, or a reproduction that writes live host configuration.

## What must never enter git

- Credentials, tokens, OAuth state, session dumps, or secret values.
- Customer data, private evidence, or generated media.
- A filled `agenthub.profile.json` if it pins a personal tree you do not intend to publish. The example file is the contract; the real file is gitignored.

Registry MCP entries use `${env:NAME}` (or the host's equivalent). Sync must not expand those into config files.

## Path isolation

`-UserProfile` exists so a test or alternate profile cannot write the live host configuration. UNC paths and forward-slash drive paths are refused because they used to skip rebasing. Do not add a fallback that writes the declared path when binding fails.
