# Automation-first gate policy

`registry/automation-gates.json` is the portfolio-wide classification for replacing discretionary process gates with deterministic controls. Validate it with:

```powershell
powershell.exe -NoLogo -NoProfile -NonInteractive -File .\scripts\Test-AutomationGatePolicy.ps1
```

The policy has four decision classes:

| Class | Default decision | Use |
| --- | --- | --- |
| `machine` | auto-proceed | deterministic build, test, security, and release checks |
| `automated_evidence` | go / pivot / stop | reproducible research, pricing, PMF proxies, and evaluation |
| `accountable_external_action` | draft only | contracts, payments, filings, live-data access, and binding communications |
| `fail_closed_exception` | halt and queue | ambiguity, stale evidence, conflicting authority, and unsafe scope |

This explicitly removes interview quotas, workshops, and generic review counts as release prerequisites. It does not treat synthetic or proxy evidence as a signed contract, lawful data authority, legal conclusion, clinical decision, payment, filing, or binding external communication. Those are accountable external actions; automation supplies evidence, a narrow draft, and an immutable receipt.
