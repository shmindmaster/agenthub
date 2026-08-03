---
name: docs-drift
description: Use when repository documentation may be stale, contradicted by code or deployment configuration, or has not been checked recently.
---

# Docs-drift audit

If the executing host supports read-only documentation-audit subagents, delegate the comparison
pass to a fresh one. Otherwise, execute the same evidence workflow directly. Every worker
must read the current repository instructions, code, manifests, infrastructure
configuration, and relevant evidence for this task; do not assume prior
session context or hidden model memory.

Code and current deployment configuration win over documentation when they
disagree. For each claim checked: cite the actual code/config that confirms
or contradicts it — never accept another doc as the source of truth for
verifying a doc.

Common drift patterns already seen in this portfolio: docs referencing an
old CI/review workflow that's since been replaced by a portfolio-wide
policy change (check for a "Portfolio Automation Policy" or similar
superseding note before flagging an old policy as current); docs naming a
deployment path/service that's moved; docs claiming a feature is "live"
when the code shows it's actually human-gated or unbuilt.

Only fix confirmed stale documentation — don't rewrite doc sections that
are still accurate just because they could be phrased differently. State,
for each fix, what changed and what code/config justifies the new wording.
