---
name: privacy-fictionalizer
description: >
  Maintains the truth/dramatization ledger for Receipts. Labels every source as
  FACT, DRAMATIZED, or COMPOSITE; maps real people to fictional characters;
  blocks public quote misuse. Use before writing scripts from Slack/GitHub material.
---

# Privacy Fictionalizer

## Labels (required on every receipt)

| Label | Meaning |
| --- | --- |
| FACT | Verifiable event/state from source |
| DRAMATIZED | Real event; dialogue/timing heightened |
| COMPOSITE | Multiple events/people merged for story |

## `receipts.yaml` schema (per entry)

```yaml
- id: R042
  source:
    type: slack  # github | deploy | notes
    ref: "..."
    timestamp: "..."
  factual:
    event: "..."
  public_use:
    quote_allowed: false
  fictionalization:
    character: "Devon"
    dialogue_can_be_rewritten: true
  classification:
    source_fact: true
    dramatized_dialogue: true
    label: DRAMATIZED  # FACT | DRAMATIZED | COMPOSITE
```

## Rules

1. No invented evidence.
2. Real names stay internal; on-screen uses fictional cast from `series-continuity`.
3. Block customer PII and anything `quote_allowed: false` from appearing verbatim.
4. Reject scripts that assert FACT without a receipt id.
