---
name: prioritize
description: Ranks screened funding opportunities against the product portfolio and recommends which engineering work to move up or defer. Use when asked which funding to pursue, which product fits a program, or how funding should change the backlog. Not for finding programs; use scout.
---

# Prioritize

## Workflow contract

1. Resolve the records root and read the register, the facts file, the portfolio profiles and the newest strategy file.
2. Score only opportunities whose eligibility is screened, match each to its best product, then score the engineering changes that the top matches depend on.
3. Return a ranked matrix and a ranked list of engineering changes, and write the scores and decisions back to the register.
4. If an eligibility fact or a product's evidence is missing, leave the scores empty, name the missing fact and rank the opportunity below every scored one.

The records root is `$FUNDING_RECORDS_ROOT`, otherwise `D:/OneDrive - MahumTech/Documents/03_Products_and_Startups/Funding Intelligence`. If neither exists, stop and ask.

## Checklist

- [ ] Run `node ../scout/scripts/register.mjs check "<root>"`.
- [ ] Drop every row whose `eligibility` starts with `blocked`. A blocked row gets a decision and a reopen condition, never a score.
- [ ] For each remaining row pick the best product and one runner-up from the portfolio profiles. Judge a product by its recorded evidence (customers, pilots, working code), not by its description.
- [ ] Compute the three scores with [scoring](references/scoring.md).
- [ ] Before recommending apply or prepare, run `node ../scout/scripts/register.mjs seen "<root>" "<program>"`. A program already rejected, declined or dropped is recommended again only when its reopen condition is now true, with the new fact cited.
- [ ] Set `best_product`, `runner_up`, `fit_score`, `priority_score`, `band`, `decision`, `decision_date` and `reopen_if` in the register. Rerun `check`.
- [ ] Write the ranked matrix, the engineering changes and the limits of the run to a new `Portfolio Funding Strategy - <YYYY-MM-DD>.md`. Leave earlier strategy files as written.

## Output

Matrix columns, in order: opportunity, funding, deadline with its label, eligibility, best product (runner-up), fit, priority and band, confidence, recommendation.

Engineering changes, in order: change, backlog issue, state now, recommended state, score, effort, what it serves, what it displaces. Follow them with the work worth deferring and the investments several products share.

Close with the limits of the run: which sources failed, which facts were not reopened on the official page, and what was not checked.

## Rules

- Scores rank work. None is a probability of winning; say so in the output.
- Eligibility comes first. A high fit never offsets a blocked or unverified eligibility fact.
- Say plainly when a product has no funding route, and when the best next step is customer evidence and not another application.
- Backlog changes are recommendations. Read the tracker to cite real issues, and change an issue's priority or state only after the owner approves that change.
- Do not submit, contact a funder or spend. List each as an owner action with its deadline.
