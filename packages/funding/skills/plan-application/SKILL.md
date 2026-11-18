---
name: plan-application
description: Produces a funder profile and an application strategy for one chosen funding opportunity, ready for the owner to approve. Use when asked how to win a grant, accelerator or competition, to research a funder or investor, or to prepare an application. Not for choosing which to pursue; use prioritize.
---

# Plan application

## Workflow contract

1. Resolve the records root, the one opportunity and product to plan for, and the register row that holds its decision.
2. Research the funder from its own material and prior awards, then build the strategy from the product's recorded evidence.
3. Return the funder profile, the strategy, the artifact list with gaps, a dated plan and the owner actions.
4. If the register row is closed, blocked, unverified or missing, stop and send the request to `scout` or `prioritize` before planning.

The records root is `$FUNDING_RECORDS_ROOT`, otherwise `{documentsRoot}/Documents/03_Products_and_Startups/Funding Intelligence`. If neither exists, stop and ask.

## Checklist

- [ ] Run `node ../scout/scripts/register.mjs seen "<root>" "<program>"`. Plan only a row whose decision is apply, prepare or in-flight and whose eligibility is `eligible`. A row whose eligibility is unverified goes back to `scout` to settle the missing fact first.
- [ ] Reopen the official page today. Confirm the deadline, amount, eligibility text, required artifacts and review criteria. If a term changed, correct the affected register fields first and say what changed; only then set `verified` to today, so the date never sits beside an outdated term.
- [ ] Profile the funder: what it states it funds, its published review criteria and weights, who decides, and its recent awards or portfolio. For federal programs pull comparable awards with the keyless award APIs listed in `../scout/references/sources.md`.
- [ ] Read section D of `Existing Pipeline and Eligibility Facts.md` for drafts and assets that can be reused, and the product's profile for its evidence.
- [ ] Map each review criterion to the evidence that answers it. Mark every criterion with no evidence as a gap, with the smallest piece of work that would close it.
- [ ] List the required artifacts and registrations with their lead times, working back from the deadline.
- [ ] Write the plan to a new `Application Plan - <register id> - <YYYY-MM-DD>.md` in the records root, and add the funder facts to the matching `Opportunities` file. Leave every `Portfolio Funding Strategy` file as written; each is a dated snapshot.

## Output

In order: the opportunity in one line with its deadline label; funder profile; selection patterns from prior awards; criterion-to-evidence map; gaps; artifacts and lead times; dated plan; owner actions; what could not be verified.

## Rules

- Every funder fact carries its URL and the date it was read. Selection patterns come from named prior awards, not from general advice.
- Use only evidence the records hold. Never invent a metric, customer, partner or credential, and never restate a synthetic or internal figure as a result.
- The plan stops at a draft. Do not submit, create an account, sign in to a portal, register an entity, contact a funder, partner or investor, or spend. Each is an owner action, listed with the date it is needed by.
- Approval of one application is not approval of the next.
- Paid research databases stay off until the owner approves the cost.
- Write any draft under the owner's name with the host's writing skill where one exists, and hold it for approval.
