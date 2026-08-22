# Opportunity Response Engine

Companion to `knowledge-access-plan.md`. That doc covers getting at the
contents. This one covers turning the contents into the things you send.

## Evidence sources

Do not draft through a local chat LLM. Retrieve, then write.

- Qdrant alias `knowledge` (Local-AI `query.ps1 --index knowledge` /
  `Search-Knowledge.ps1 -Semantic`): career, project, and proposal
  history. Never alias `legal` for this pipeline.
- RepoWise workspace `C:\Repos`: repository architecture and
  implementation evidence.
- Combine them. Iterate the query if the first hits are thin. Prefer
  specific transferable examples and outcome language. Gate still
  forbids unsourced numbers and uncleared client names.

## The insight

Resume, Upwork bid, fixed-scope proposal, hourly/rate proposal, candidate
interview prep, and discovery-call prep are one pipeline with six
renderers. Parse, match, and gate are shared.

```
OPPORTUNITY → MATCH → RENDER → GATE
JD / RFP / Upwork     requirements vs      format + voice     evidence check
post / client brief   portfolio evidence   per output type    name filter
```

Extraction has to be done once, richly, rather than six times narrowly.

## Records

One YAML per engagement in `C:\Repos\shmindmaster\portfolio-records\`
(private). Schema:
`packages/knowledge-access/schemas/engagement-record.schema.yaml`.

Fail-closed: any outcome without a locatable citation is
`claim: null, evidence: NOT_FOUND`. `rate_or_value` never reaches a
rendered output unless the user put it there deliberately.

## Matcher

At 40–80 records the library fits in context — no top-k. The gap list is
the valuable output. Similarity search cannot produce it.

## Renderers

All chain through the owner's voice. Same gate on every renderer.

| Renderer | Notes |
| --- | --- |
| tailor-resume | Cheapest; proves the matcher |
| draft-upwork-bid | Short form, high volume |
| prep-interview --candidate | Zero new extraction |
| draft-proposal | Needs `05` + full records |
| price-engagement | Needs commercials across most records |
| prep-interview --discovery | Last; least urgent |

Build order: schema + fixtures (done) → resume → bid → candidate prep →
remaining real records (authorized) → proposal → price → discovery.

## Packaging

AgentHub capability `knowledge-access`. Router skill `opportunity-engine`.
Records are private and are not this repository.
