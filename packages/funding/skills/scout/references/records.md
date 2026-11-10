# Records

Read when adding or changing a register row or a narrative entry.

## Files in the records root

| File | Holds | Who changes it |
|---|---|---|
| `Funding Opportunity Register.csv` | One row per opportunity: terms, eligibility, scores, decision, reopen condition | `scout` adds rows and facts; `prioritize` sets scores and decisions |
| `Opportunities - Grants and SBIR.md`, `- Accelerators and Equity.md`, `- Competitions and Challenges.md`, `- Credits and Strategic Support.md` | The evidence behind each row: source access log, terms, review criteria, checked-and-rejected lists, what could not be verified | `scout` |
| `Existing Pipeline and Eligibility Facts.md` | Entity, ownership, registration and prior-award facts; what is in flight; section C rejected list | Update only from a cited source. Mark each fact CONFIRMED, STATED, CONFLICT, INFERRED or UNKNOWN |
| `Portfolio Profiles - Group *.md` | What each product is, its stage and its evidence | Update from code and records, never from a pitch |
| `Portfolio Funding Strategy - <date>.md` | The ranked matrix, engineering changes and plan as of that date | `prioritize` writes a new dated file and leaves earlier ones as written |
| `Application Plan - <register id> - <date>.md` | The funder profile, criterion-to-evidence map, gaps and dated plan for one opportunity | `plan-application` writes a new dated file per plan |

Edit in place. Never copy a file to keep a backup, and never write these facts anywhere else.

## Register columns

Keep the header and column order exactly. Quote any value that contains a comma.

| Column | Value |
|---|---|
| `id` | Stable and unique. Use the funder's own number where one exists, otherwise `<PROGRAM>-<cycle>` |
| `program`, `organizer` | As the organizer writes them |
| `category` | Such as grant, equity, competition, prize, credits, accelerator |
| `cash_or_noncash` | `cash`, `noncash`, or `unpublished` |
| `amount` | As published, with the equity or fee terms |
| `deadline` | The date with time and zone where published |
| `deadline_status` | `confirmed`, `forecast`, `expected`, `open`, `unverified`, or a pipeline state such as `submitted` or `approved` |
| `best_product`, `runner_up` | Set by `prioritize` |
| `eligibility` | `eligible`, `blocked (<fact>)` or `unverified (<missing fact>)` |
| `fit_score`, `priority_score`, `band` | Set by `prioritize`. Leave empty until eligibility is screened |
| `decision` | Such as `apply`, `prepare`, `monitor`, `skip`, `in-flight`, `rejected-by-owner` |
| `decision_date` | `YYYY-MM-DD` |
| `reopen_if` | The one new fact that would reopen a closed row |
| `official_url` | The organizer's page the facts were read from, `https` only |
| `verified` | `YYYY-MM-DD` the official page was last read |

A row whose decision starts with skip, rejected, declined, dropped, expired or not-eligible is closed. Closing a row always fills `reopen_if` or states that nothing reopens it.

## Narrative entry

One entry per opportunity in the matching `Opportunities` file: official URL, amount and terms, dates with their label, eligibility text, required artifacts, published review criteria, and what could not be verified. Programs checked and turned down go in that file's checked-and-rejected list with the reason, so the next run does not research them again.

## Never record

Tax identifiers, state file numbers, bank details, patent application numbers, phone numbers, street addresses, credentials or portal passwords. Write "present" or "absent".
