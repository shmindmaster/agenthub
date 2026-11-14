# Sources

Read when choosing where to search or how to call a source.

## Order

1. Keyless public APIs below. They return structured records and cost nothing.
2. The organizer's own site, found through the host's web search, for programs with no API: accelerators, foundations, state programs, corporate credits, pitch events.
3. A semantic search plugin such as the vendor Exa plugin, where the host has one, to find similar programs and investors by description.
4. Page extraction only for a page the host's own fetch cannot read.

Whatever finds a program, the organizer's page or API record is what confirms it.

## Keyless public APIs

Each takes plain HTTP with no key. Use `curl` or the host's fetch tool. Keep `rows` or `limit` small and page.

| Source | Use for | Request |
|---|---|---|
| Grants.gov search | Open and forecast federal opportunities | `POST https://api.grants.gov/v1/api/search2` with `{"keyword":"\"quoted phrase\"","oppStatuses":"forecasted\|posted","rows":25,"startRecordNum":0}` |
| Grants.gov detail | Dates, ceilings and eligibility text of one opportunity | `POST https://api.grants.gov/v1/api/fetchOpportunity` with `{"opportunityId":<id from search>}` |
| NIH RePORTER | Prior NIH awards, including SBIR and STTR (`R41` to `R44`) | `POST https://api.reporter.nih.gov/v2/projects/search` with `{"criteria":{"activity_codes":["R43"],"fiscal_years":[<year>],"advanced_text_search":{"operator":"and","search_field":"projecttitle,terms","search_text":"<terms>"}},"include_fields":["ProjectNum","ProjectTitle","Organization","AwardAmount"],"limit":25,"offset":0}` |
| NSF Award Search | Prior NSF awards | `GET https://api.nsf.gov/services/v1/awards.json?keyword=%22<phrase>%22&fundProgramName=SBIR+Phase+I&printFields=id,title,awardeeName,fundsObligatedAmt,date&rpp=25` |
| USAspending | Prior awards from any agency, by assistance listing | `POST https://api.usaspending.gov/api/v2/search/spending_by_award/` with `{"filters":{"award_type_codes":["02","03","04","05"],"program_numbers":["<listing>"],"time_period":[{"start_date":"<YYYY-MM-DD>","end_date":"<YYYY-MM-DD>"}]},"fields":["Award ID","Recipient Name","Award Amount","Awarding Sub Agency"],"limit":25,"page":1}` |
| Devpost | Open hackathons and challenges | `GET https://devpost.com/api/hackathons?status[]=open&search=<term>&per_page=25` |

Notes that save a wasted call:

- Grants.gov matches unquoted multi-word keywords with OR and returns hundreds of unrelated hits. Quote phrases. Add `closed|archived` to `oppStatuses` only for history.
- NSF keyword matching is loose. Read the abstract before counting an award as comparable.
- Prior awards show who wins and at what size. They are selection patterns, never proof that a program is open.

## Sources that need the owner

Do not create an account, request a key or start a trial. Record the source in the access log and list it as an owner action.

| Source | State | What unlocks it |
|---|---|---|
| OpenGrants MCP, `https://mcp.opengrants.io/mcp` | Returns 401 without an account | Owner creates an account and approves any cost |
| Simpler.Grants.gov developer API | Needs a key issued after a Login.gov sign-in | Owner requests the key. Its public opportunity pages read without one |
| SBIR.gov API | Returned 403 | Nothing known. Use RePORTER, NSF and USAspending for awards |
| F6S | Blocks automated access | Owner browses it signed in |
| Crunchbase, Dealroom, PitchBook | Paid | Owner approves the cost first |

## Hosts

Every host can run the keyless requests, so discovery does not depend on any search plugin. Where a host has no semantic search, use its web search and say so in the access log. Where a host has no web access at all, work only from the APIs and mark every non-federal program UNVERIFIED.

## Access log

End every run with one line per source: source, worked or failed with the status, and what it was used for. The next run reads it to skip dead ends.
