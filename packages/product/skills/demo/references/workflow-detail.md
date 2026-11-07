# Workflow detail

## Final mapping

`afterVerdict` is the gate. `beforeVerdict` never authorises recording.

| `afterVerdict` | `verdict` | `handoffDecision` |
|---|---|---|
| `DEMO-READY`, all eleven pass | `PASS` | `PROCEED` |
| `REMEDIABLE`, including when every residual is capture-fixable | `FAIL` | `DO-NOT-RECORD` |
| `DEFERRED` | `FAIL` | `DO-NOT-RECORD` |

## Product fix or capture fix

- `product-fix-required`: behaviour, accessibility, truth, responsiveness or performance.
- `capture-fixable`: a rough edge the camera or edit can treat, with the exact treatment written down.
