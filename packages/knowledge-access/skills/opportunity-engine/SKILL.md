---
name: opportunity-engine
description: Use when turning a JD, RFP, Upwork post, client brief, capability statement, cover letter, technical pitch, or interview prep into a tailored resume, bid, proposal, rate table, or Q&A. Also for /tailor-resume, /bid, /proposal, /prep, /price, opportunity parser, portfolio match, or opportunity-response-engine. Always retrieve from Local-AI Qdrant knowledge and RepoWise first; never draft via a local chat LLM.
---

# Opportunity Response Engine

Companion to `use-knowledge-access`. That skill gets at the documents.
This one turns them into something you send. You are the writer. Do
**not** start llama.cpp, Ollama chat, Open WebUI generation, or
`:8787/v1/chat/completions` to draft — those are local inference
daemons, not this pipeline.

Parse, match, and gate are shared. Only the renderer changes.

```
OPPORTUNITY → MATCH → RENDER → GATE
```

Load `references/opportunity-response-engine.md` for the full model.
Load `use-knowledge-access` before searching `01`–`06` or `10`.
Load `use-repowise` when the opportunity needs repository/code evidence.

## Evidence sources (Qdrant + RepoWise)

Default for every opportunity: retrieve, then write. Iterate search if
the first pass is thin.

1. Analyze the role, RFP, or client requirements: skills, technologies,
   responsibilities, outcomes, evaluation criteria, differentiators.
2. **Qdrant `knowledge`** (via `Search-Knowledge.ps1 -Semantic` or
   `D:\Local-AI\query.ps1 --index knowledge`): prior projects, products,
   architecture decisions, capabilities, proposal material,
   accomplishments, client/work context (names only if this turn cleared
   them), documented expertise. Alias `legal` is out of scope here.
3. **RepoWise** (workspace `C:\Repos`): implementations, APIs,
   infrastructure, AI/LLM workflows, integrations, database and
   deployment patterns, optimizations, code-backed examples.
4. Combine: Qdrant for history and business context; RepoWise for
   concrete engineering. Prefer the strongest relevant example even if
   it was built for a different client, product, or industry — translate
   it to this opportunity. Older work stays in play when it is the
   better proof.
5. Prioritize specifics over generic capability statements: architecture
   choices, problems solved, scale, performance, cost, automation,
   reliability, measurable outcomes. For senior / architecture / AI /
   consulting roles, look for system ownership, judgment, modernization,
   and end-to-end delivery.
6. Outcome language for the audience: scalability, latency, reliability,
   AI quality, ops efficiency, infra/LLM cost, productivity, customer
   experience, revenue enablement, delivery speed.

Gate still applies after retrieval. A miss is a GAP, not a prompt to
invent.

## Records

Runtime store: `C:\Repos\shmindmaster\portfolio-records\records\engagements\`.
Schema: `../../schemas/engagement-record.schema.yaml`.
Synthetic fixtures (the only records that may live in this package):
`../../fixtures/engagements/`.

If the runtime store has no real records yet, say so and run against
fixtures. Do not invent engagements. Do not copy client names out of
`02_Client_Work` into a record unless this turn is an authorized
extraction.

`rate_or_value` is never-render unless the user explicitly asked for
commercial figures in the output. An outcome without a locatable
citation is `claim: null` / `evidence: NOT_FOUND`.

## 1. Parse

Input: JD, RFP, Upwork post, recruiter email, client brief.
Output YAML matching `../../schemas/opportunity.schema.yaml`.

Map each requirement's language into a `capability` join key (reasoning,
not embedding similarity). Set `kind`, `engagement_shape`, `tone`, and
`gaps_to_preempt`.

## 2. Match

Read every engagement record (40–80 will fit; do not top-k). For each
requirement emit: best evidence, strength (`strong` / `partial` / `GAP`),
note. The gap list is the valuable output. A GAP is not a prompt to
fabricate coverage.

## 3. Gate (every renderer)

Before any bytes leave:

- No unsourced numeric or outcome claim.
- No client name unless `name_cleared: true` **and** the user cleared
  that name this turn.
- No `rate_or_value` unless explicitly requested.
- Private ventures in `03` are not Pendoah work.

Fail closed: a grounded document or a precise gap report. Never a
plausible document with invented specifics.

## 4. Render

All first-person voice is the owner's. Do not send copy to a hosted TTS
provider.

| Intent | Renderer | Output |
| --- | --- | --- |
| resume / tailor this JD | `tailor-resume` | docx + change log |
| Upwork / bid / proposal short | `draft-upwork-bid` | short proposal |
| RFP / SOW / fixed or hourly proposal | `draft-proposal` | long proposal |
| what should this cost | `price-engagement` | decision table, not a document |
| interview prep (candidate) | `prep-interview --side candidate` | Q&A + STAR |
| discovery / assessing them | `prep-interview --side discovery` | questions + risk signals |

### tailor-resume

Reorder and rewrite bullets against the requirement set. First-person,
`attribution.personal`. Pull metrics only from `outcomes` with evidence.
Flag gaps so the user can address or omit. Write a change log of what
was emphasized and why.

### draft-upwork-bid

Short. Open with the client's problem in their words, one precedent with
a sourced number, a concrete first-week deliverable, one question. Draw
shareable proof from `03_Products_and_Startups/Pendoah/Upwork Profile
Management` and `05` only after `use-knowledge-access` locates the files.

### draft-proposal

Needs the full record set plus `05` accelerators. If records are still
fixtures-only, stop after match and say remaining extraction is the
gate. Shape: `--shape fixed|hourly|retainer`. Problem restatement →
approach → precedent → team → timeline → risks from `risks_hit` →
commercials (no rates unless asked).

### price-engagement

Decision table from `commercials` across comparable records: quoted vs
actual, where estimates broke. Never echo `rate_or_value` into a
customer-facing artifact.

### prep-interview --side candidate

Likely questions from requirements; one STAR story per requirement from
`situation/task/action/result`; numbers only with evidence; use
`failure_or_setback` for the "went wrong" question; honest GAP answers.

### prep-interview --side discovery

You assessing them. Questions that surfaced real problems in comparable
engagements; industry pain patterns; prior objections and what resolved
them; scope-risk signals.

## Extraction rule

Do not bulk-extract `02` in this skill. One authorized record at a time,
fail-closed on citations. Wave 1 is schema + fixtures (done). Real
records are a later authorized pass.
