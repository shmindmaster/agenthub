---
name: docs-drift
description: Compare a repo's documentation (README, applicable repository instructions, and docs) against actual code, package manifests, infra specs, and deployment topology, and fix confirmed stale documentation. Use when a doc claim looks suspicious or a repo hasn't had its docs checked in a while.
---

# Docs-drift audit

Delegate the comparison pass to the `docs-auditor` subagent — it has a
standing memory of drift patterns already found in this portfolio, so
reuse it rather than starting cold each time.

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
