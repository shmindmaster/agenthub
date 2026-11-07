# Plugin redesign and fleet rollout

Baseline commit `f4cd221e`.

## Delivery waves

1. Shared deployment command, package containment checks and fixture coverage.
2. Browser, Product, Media Studio, mobile and RepoWise workflow handoffs.
3. Provider workflows and privately distributed owner workflows.

Keep stable plugin and skill identities. Preserve accepted artifacts, approval and spending boundaries. Package tests distinguish documented workflow fixtures from live agent or provider acceptance.

## Verification and release

Run registry, package and workflow checks and the full test runner before rollout. Publish the reviewed source and require successful CI on that exact commit before `plugins -Apply`. Deploy a canary for each route, read back its native registration and managed content, then expand. Repeat apply to prove idempotence.

The plugin audit derives ownership from the capability and MCP registries. It reports unavailable, incompatible and unmanaged routes separately. Preserve unrelated configurations. Receipts and private evidence stay under the local AgentHub runtime.

Record licenses from package provenance. Existing MIT declarations that differ from the root Apache-2.0 license require provenance review before changing them.

## Environment blockers

At the baseline, the Windows AgentHub runtime directory can be probed but cannot reliably create or enumerate children. Mobile runtime staging and the shared RepoWise refresh lease are affected. Diagnose through their normal entry points and preserve runtime dependencies. Do not replace or redirect a shared lease to bypass the failure.

