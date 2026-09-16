# Roadmap

AgentHub Core is a public, host-neutral control plane for skills, plugins, MCP servers, and policy. The roadmap separates what exists today from proposed work so that a public repository or funding application does not turn plans into shipped claims.

## Current public core

- Desired-state registries for capabilities, hosts, bundles, and MCP servers.
- A validate, audit, then apply lifecycle with read-only drift inspection as the default.
- Cross-platform path binding for Windows, macOS, and Linux.
- A gitignored personal overlay for private capability ids, policy fragments, machine roots, and identity-specific configuration.
- Public-core export checks that prevent private packages and personal overlay data from entering the public tree.
- Repository-native tests for path isolation, host routing, capability ownership, plugin manifests, and sync behavior.

## Bounded public-interest work

The items below are proposed maintenance work. They are not funded, released, or promised on a specific schedule.

1. **Portable bootstrap and conformance path.** Produce a versioned public artifact and a deterministic ten-minute setup that does not require contributors to understand the PowerShell implementation. Keep PowerShell as the current engine while testing the user-facing wrapper on Windows, macOS, and Linux.
2. **Host-adapter conformance fixtures.** Publish synthetic fixtures that show what each supported host can express, what degrades, and how drift is detected. A host passes by producing the declared outcome, not by copying another host's file layout.
3. **Local overlay hardening.** Expand tests proving that personal identity, local roots, credentials, and private capability ids stay outside public exports and host-neutral policy.
4. **Interoperability documentation and demo.** Publish a small reproducible example that transports one public capability and policy rule across multiple hosts, then detects an intentional drift without exposing personal configuration.
5. **Release and maintenance policy.** Add a public release procedure, compatibility statement, changelog discipline, and issue templates for host adapters and policy portability.

## Validation gates

Each work item must preserve the public/private boundary, pass the repository validation suite, document unsupported host behavior explicitly, and avoid invented packaging formats. Negative findings and unsupported surfaces are valid published outcomes.

## Non-goals

- An AI application or hosted agent runtime.
- A credential store, customer-data plane, or centralized copy of personal overlays.
- Identical host mechanics where platforms provide different native surfaces.
- Silent mutation of host configuration or production systems.
- Mobile identities or deployment surfaces outside the separate mobile-scope policy.
