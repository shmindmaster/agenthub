## Outcome

What observable result does this change produce?

## Scope and hosts

- Affected hosts:
- Capability owner from `registry/capabilities.json`:
- Public/private boundary impact:

## Evidence

- Reproduction or fixture:
- Validation commands and results:
- Unsupported or degraded behavior:

## Checklist

- [ ] I did not include credentials, private overlays, personal paths, customer data, or generated runtime artifacts.
- [ ] I used official host formats and did not invent an unsupported package or plugin surface.
- [ ] I updated registry content hashes when canonical capability content changed.
- [ ] I ran `pwsh -NoProfile -File ./scripts/Validate-AgentHub.ps1`.
- [ ] I ran `pwsh -NoProfile -File ./tests/Run-AllTests.ps1`.
- [ ] I documented behavior that remains unsupported or unverified.
