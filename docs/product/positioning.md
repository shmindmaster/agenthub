# Product positioning

## The problem AgentHub owns

Installing an agent skill or MCP server is only the first step. A real fleet
still needs to answer:

- Which package is the canonical owner of this capability?
- Which hosts truly support the surface, which were checked and do not, and
  which remain unknown?
- Did the deployed copy preserve the reviewed content and policy?
- Can a local operator add private identity, paths, or capabilities without
  leaking them into a public distribution?
- Can an invalid registry or weaker policy reach an apply step?

AgentHub makes those answers explicit in a desired-state registry and checks
them through a validate → audit → apply lifecycle.

## Category boundary

| Product type | Primary job | AgentHub relationship |
| --- | --- | --- |
| Agent package managers, including Microsoft APM | Resolve and install agent dependencies | Treat as an upstream delivery mechanism; verify the resulting ownership, policy, and drift |
| Cross-host configuration renderers, including AgentStack | Translate a portable manifest into host-native configuration | Complement with explicit support evidence, capability ownership, private overlays, and fleet conformance |
| Host-native marketplaces and plugin managers | Install packages for one host | Record the native surface honestly; do not invent a compatibility format |
| AgentHub | Govern what the fleet intends to carry and prove whether deployed state matches | Remain installer-neutral and fail closed on invalid or empty work sets |

This boundary is based on the public capabilities of those projects as of
2026-09-15. Links are evidence, not endorsements:
[Microsoft APM](https://github.com/microsoft/apm) and
[AgentStack](https://github.com/Tarekkharsa/agentstack).

## Differentiators that must remain true

1. **Evidence, not assumed parity.** `false` means checked and absent; `null`
   means not established. Neither becomes a silent success.
2. **One owner per capability.** Duplicate ownership fails validation instead
   of allowing last-writer-wins deployment.
3. **Private overlays stay local.** Public exports exclude personal identity,
   credentials, machine roots, and private capability ids.
4. **Apply is gated.** Validation must pass before managed state can change;
   audit-only behavior is the default.
5. **Native formats remain authoritative.** AgentHub records degradation rather
   than fabricating a plugin shape a host does not support.

## Adoption hypothesis

The first useful external workflow is not “move every agent setup into
AgentHub.” It is smaller:

1. register one public capability and two hosts;
2. validate ownership and declared support;
3. deploy through the host's normal mechanism;
4. introduce one synthetic drift;
5. detect it and explain the next safe repair.

That path needs a runnable cross-platform fixture and outside-maintainer
feedback before broader adoption claims are justified.
