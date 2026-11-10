# AH-Funding

Find, verify, rank and plan funding for a product portfolio, against one set of records that every run reads and updates.

Three skills, no MCP server and no hook, so nothing connects or runs until a skill is used:

| Skill | Does |
|---|---|
| `scout` | Finds opportunities, confirms each on its official page, screens eligibility and records it in the register |
| `prioritize` | Scores screened opportunities against the products and ranks the engineering work that funding depends on |
| `plan-application` | Profiles one funder and builds an application strategy for the owner to approve |

## Records

The skills read and update the folder named by `FUNDING_RECORDS_ROOT`. They never create a second store. `skills/scout/scripts/register.mjs` validates the register and answers whether a program was already decided; it only reads.

## Sources

Discovery uses keyless public APIs (Grants.gov, NIH RePORTER, NSF Award Search, USAspending, Devpost) and the organizer's own pages, so it works on every host without a search plugin. `skills/scout/references/sources.md` holds the request recipes and the sources that need an owner decision first.

## Not built

No MCP server ships with this plugin. Paid databases (Crunchbase, Dealroom, PitchBook) and account-gated sources (OpenGrants, Simpler.Grants.gov) wait for an owner decision. If several hosts later need the same sources behind one interface, a single remote gateway server with tools such as `discover_opportunities` and `verify_eligibility` is the option to weigh; it would be registered in `registry/mcps.json` as shared-remote and off by default.

## Boundary

The skills research, record and draft. They do not submit an application, create an account, contact a funder or spend.

## Test

```
node --test packages/funding/tests/
```
