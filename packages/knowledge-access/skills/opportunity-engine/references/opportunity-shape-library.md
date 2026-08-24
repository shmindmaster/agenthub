# Opportunity shape library

Reusable problem-shape sets for the role archetypes that recur in this
pipeline. Feed them to `Get-EvidenceAugmentation.ps1 -ShapesFile`, and add
one or two opportunity-specific shapes with `-Shape` on top.

Ready-to-use files live beside this one in `shapes/`.

## Why shapes, not role vocabulary

Querying the corpus with a job title retrieves your own resumes. Resumes are
written in role vocabulary ("Field CTO", "enterprise AI strategy"), so a
role-vocabulary query is a near-duplicate match against your own marketing
copy — circular evidence that launders unsupported claims from one document
into the next.

Problem-shape language does not appear in resume prose. It appears in work
product. Measured across five live roles, switching from role vocabulary to
problem shape moved self-citation in the top 10 from **22/50 to 1/50**, and
returned an almost entirely disjoint document set (zero overlap on four of
the five).

It also reaches work whose vocabulary predates the target domain. A 2014
platform-consolidation program is invisible to "agent platform" and squarely
relevant to it.

## Writing a good shape

Describe the **structure** of the problem:

- who the consumers are, and how many
- what constraint binds it (regulation, cost, deadline, fragmentation)
- what the failure mode is
- what decision is being made, and by whom
- the scale

Avoid: job titles, product names, technology brands, seniority words.

| Weak (role vocabulary) | Strong (problem shape) |
| --- | --- |
| "agent platform engineering leader" | "shared internal platform many teams build on, with standards, golden paths and onboarding governance" |
| "enterprise AI strategy executive" | "executive technology strategy and operating model design across business units" |
| "AI infrastructure for legal" | "handling privileged material with segregation, access control and audit obligations" |
| "senior analyst, analytics and AI" | "written advisory deliverable comparing options for an executive decision" |

## Archetypes

Each set is a starting point. Three to five shapes is usually right — enough
angles to pull different material, few enough to stay on-topic.

### Internal platform engineering — `shapes/internal-platform-engineering.txt`
Teams build on a shared thing you own. Adoption, standards and migration are
the real work. Reaches: platform consolidation, application rationalization,
standards governance, ITSM/ServiceNow consolidation.

### Regulated AI governance — `shapes/regulated-ai-governance.txt`
Controls, validation and audit over sensitive data. Reaches: information
governance, security operating models, PHI/PII segregation, resolution
planning, HIPAA/HITRUST design work.

### Enterprise AI architecture — `shapes/enterprise-ai-architecture.txt`
End-to-end architecture and modernization across a fragmented estate.

### Advisory and analyst research — `shapes/advisory-analyst-research.txt`
The deliverable is a written recommendation for an executive audience.
Reaches: strategy briefs, vendor assessments, market and demand analysis.

### Field CTO and pre-sales — `shapes/field-cto-presales.txt`
Client-facing solution shaping and proposal work. Reaches: pursuit guides,
proposal tooling, SOWs, packaged-service definitions.

### Hands-on retrieval delivery — `shapes/hands-on-retrieval-delivery.txt`
Short scoped build: RAG, vector search, evaluation, handover. The Upwork
lane. Reaches: prior RAG proposals with sprint structures and acceptance
criteria you can reuse almost verbatim.

### Fractional CTO and transformation — `shapes/fractional-cto-transformation.txt`
Operating model, org design, cost and capability decisions.

## Using the output

Every returned item carries a rendering mode. `ANONYMIZE` means the substance
is fully usable and only the client name is withheld — a large body of the
corpus is un-nameable rather than unusable, and treating those as blocked
discards the strongest precedent available.

The invariant that survives every adaptation: **facts transfer verbatim with
a citation, framing adapts.** Scale, duration, constraint, outcome and your
actual role come across unchanged. Never invent a fact to fit a frame.
