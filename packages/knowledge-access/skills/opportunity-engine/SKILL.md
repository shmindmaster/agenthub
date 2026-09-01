---
name: opportunity-engine
description: Use when discovering, triaging, researching, tailoring, submitting, tracking, or following through on job opportunities, or when turning a JD, RFP, Upwork post, or client brief into a resume, proposal, pitch, rate table, or interview preparation. Always retrieve from Local-AI Qdrant knowledge and RepoWise first; never draft via a local chat LLM.
---

# Opportunity Response Engine

Companion to `use-knowledge-access`. That skill gets at the documents.
This one turns them into something you send. Portfolio pages, case
studies, and bios that are not an opportunity response:
`portfolio-enrichment`. You are the writer. Do
**not** start llama.cpp, Ollama chat, Open WebUI generation, or
`:8787/v1/chat/completions` to draft — those are local inference
daemons, not this pipeline.

The shared evidence workflow is:

```
DISCOVER → VERIFY → RANK → RESEARCH → AUGMENT → MATCH → RENDER → QA
         → ROUTE → SUBMIT → FOLLOW THROUGH → LEARN
```

Load `packages/knowledge-access/references/opportunity-response-engine.md`
for the full model (package-level; not deployed beside this skill).
Load `references/opportunity-shape-library.md` before writing queries.
Load `use-knowledge-access` before searching `01`–`06` or `10`.
Load `use-repowise` when the opportunity needs repository/code evidence.

## Standing job operating mode

The objective is high-quality interviews and offers, not application volume.
Do not center discovery on LinkedIn, Easy Apply, or any other single surface.

### Discover and record coverage

Search all useful sources available on the active host: installed job
connectors, major job boards, employer career sites and ATS systems,
executive-search firms, specialized recruiters, hiring-manager posts, employee
or network signals, and current web discovery. Use the fleet routing policy;
do not install, emulate, or claim access to a connector that is unavailable.

For every discovery run, record each material source as `checked`,
`unavailable`, or `unchecked`. Choose opportunities by quality and expected
conversion, never by application convenience.

### Verify and rank before heavy work

Verify the live authoritative posting, employer, title, level, location,
work arrangement, freshness, compensation components, credible total
compensation, authorization/citizenship/clearance terms, travel, relocation,
available routes, and duplicate state across mail, LinkedIn, FoundRole,
trackers, ATS receipts, and local application folders.

Priority contract:

- Flagship companies and exceptional roles receive immediate attention.
- Credible USD 300K-1M+ total compensation is a worldwide target.
- USD 250K-299K is a secondary target, primarily in the United States.
- Confirmed compensation below USD 250K is out unless the owner changes the
  floor.
- Easy Apply and other low-friction methods confer no priority.

Reject only a confirmed sub-floor package, dead posting, duplicate submission,
fundamental seniority mismatch, or immutable legal incompatibility. An absent
keyword, title, technology, industry, or thin first retrieval is `UNKNOWN ->
SEARCH DEEPER`, not proof of no experience. Clearance eligibility, active
clearance, citizenship, work authorization, and willingness to obtain a
clearance are separate facts and must not be collapsed.

Rank surviving roles by compensation, company quality, role influence, career
upside, strategic fit, evidence strength, hiring activity, freshness, access
path, interview likelihood, and ability to differentiate. Application method
is not a ranking factor.

### Research serious opportunities

Use official job, company, team, engineering, and candidate-policy pages as
primary truth. For every serious role, add current research from Firecrawl,
Exa, Tavily, and normal web sources when those capabilities are available. Use
Context7 when current SDK, API, framework, protocol, or technical-stack facts
affect the application. Record sources and distinguish source facts from
inference.

Research the mission, strategy, product direction, relevant organization and
leadership, current initiatives, hiring patterns, likely recruiter or hiring
manager, technical stack, pain points, expected outcomes, interview process,
and language used for successful candidates. Respect employer candidate-AI
policies; if a policy requires a candidate-written first draft, obtain one and
limit assistance accordingly.

### Resolve recurring application answers

The private canonical profile is:

```
%LOCALAPPDATA%\AgentHub\runtime\opportunity-engine\application-answer-profile.yaml
```

Validate it with
`packages/knowledge-access/scripts/validate_application_answer_profile.py`
against `schemas/application-answer-profile.schema.yaml` before relying on it.
It is private runtime state: never copy it into Git, OneDrive, Qdrant, RepoWise,
an application package, or an external prompt.

Resolve answers in this order:

1. Current explicit owner answer.
2. Latest verified submitted answer with equivalent scope.
3. Confirmed canonical profile value.
4. Verified career or supporting record.
5. Deterministic normalization only when meaning is unchanged.
6. Ask once when unresolved, conflicting, stale, or materially different.

Semantically identical options may be normalized; adjacent legal facts may
not. Never infer citizenship from work authorization, active clearance from
willingness or eligibility, or one jurisdiction's sponsorship answer from
another jurisdiction. Keep job-specific answers with the application and
promote them to the profile only when reusable and verified.

### Tailor, QA, route, and submit

Create a purpose-built resume from verified history and the strongest retrieved
evidence. Tailor the headline, summary, leadership positioning, experience
order, bullets, technical and ATS vocabulary, projects, consulting examples,
company value proposition, and executive-versus-hands-on balance. Augmentation
means finding and translating stronger real evidence, never fabricating it.

Retain the authoritative job snapshot and URL, research, compensation analysis,
requirement/evidence map, claim ledger, tailored DOCX/PDF, application answers,
change log, QA results, submission evidence, outreach notes, and interview
material together. Before upload, check facts, confidentiality, ATS relevance,
spelling, page count, visual rendering, and DOCX/PDF machine parseability. The
parsed output must preserve sections, employers, titles, dates, email, phone,
and bullets.

Choose the strongest available entry route for the role: trusted referral,
executive search, specialized or internal recruiter, hiring manager, executive
sponsor, direct ATS, connector, specialized platform, or LinkedIn. For major
roles, identify up to three evidence-backed human paths; do not spam.

A current explicit request to apply authorizes in-scope research, tailoring,
form completion, known answers, attachment selection, upload, and submission.
Standing memory alone does not authorize an external action when the active
task is only discovery, review, or preparation. If the host or browser requires
action-time confirmation, finish every reversible step first and request one
grouped confirmation at the final action.

Immediately before submission verify the company, role, candidate details,
answers, and exact attachment. Only a confirmation page, confirmation email,
ATS receipt, or equivalent authoritative proof establishes `submitted`.
Prepared, saved, attached, uploaded, or a timed-out browser action does not.

Track states distinctly:

```
discovered -> triaged -> researched -> evidence_mapped -> tailored -> qa_passed
-> submitted -> outreached -> screening -> interviewing -> final -> offered
-> negotiating -> accepted | declined
```

Also preserve `rejected`, `closed`, `duplicate`, `withdrawn`, and `follow_up`.
After submission, update the tracker, save the exact submitted resume, URL,
date, and proof, monitor available mail/LinkedIn/recruiter/ATS sources, and use
the saved evidence for responses and interviews. Track conversion by source,
route, company, role, compensation, human path, resume version, outreach,
freshness, and research depth; recalibrate future prioritization from observed
results.

## Evidence sources (Qdrant + RepoWise)

Default for every opportunity: retrieve, then write. Iterate search if
the first pass is thin.

1. Analyze the role, RFP, or client requirements: skills, technologies,
   responsibilities, outcomes, evaluation criteria, differentiators.
2. **Qdrant `knowledge`** — always with `-Profile client-facing`:

   ```
   D:\Local-AI\query.ps1 "<query>" -Index knowledge -Profile client-facing
   ```

   Also reachable via `Search-Knowledge.ps1 -Semantic`. Prior projects,
   products, architecture decisions, capabilities, proposal material,
   accomplishments, client/work context (names only if this turn cleared
   them), documented expertise. Alias `legal` is out of scope here.

   **The profile is not optional for opportunity work.** The collection
   also holds personal finance, family records, credentials, licensed
   analyst research, live-dispute material, and 66K chunks of
   prior-agency client work that is never nameable. `client-facing`
   excludes all of it at retrieval time. The default (`safe`) is looser —
   it still returns licensed research and never-name clients, because it
   is tuned for internal work. Omitting the flag here is how a Gartner
   excerpt or a named Fortune 500 client reaches a client-facing draft.

   Use `-Profile unrestricted` only for internal analysis that never
   leaves the machine.

   `Get-EvidenceAugmentation.ps1` does not take a profile: it applies a
   rendering mode per item instead of excluding, so restricted client
   work returns as `ANONYMIZE` rather than disappearing. Hard exclusions
   are in `config/evidence-layers.json`.
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

## 0. Augment

Retrieval here is generative, not adjudicating. The corpus exists to
enhance, adapt and thicken what you are writing — not to rule an
opportunity in or out. A thin direct match is a prompt to find the
nearest transferable work and translate it, never a reason to stop.

```
pwsh -File packages/knowledge-access/scripts/Get-EvidenceAugmentation.ps1 `
    -Label '<what you are writing>' `
    -ShapesFile packages/knowledge-access/skills/opportunity-engine/references/shapes/<archetype>.txt `
    -Shape '<one or two opportunity-specific shapes>'
```

Query on **problem shape**, never role vocabulary — resumes are written in
role vocabulary, so a title-shaped query retrieves your own marketing copy
as "evidence" and launders unsupported claims forward. See
`references/opportunity-shape-library.md`.

Five layers return together, each contributing something different:
`METHOD` (05, structure you own) · `PRECEDENT` (02, real substance) ·
`RECENT` (03, current AI/product work) · `CONTEXT` (06, cite-only market
framing) · `VOICE` (04, tone and approved claims — never evidence).

Every item carries a rendering mode. `ANONYMIZE` means the substance is
fully usable and only the client name is withheld; most of `02` is
un-nameable rather than unusable. Layers, modes and descriptors are data
in `packages/knowledge-access/config/evidence-layers.json`.

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
