---
name: portfolio-enrichment
description: Use when reviewing, rewriting, or improving a portfolio page, product page, demo, case study, resume, bio, project description, or other professional material. Also for /portfolio-enrichment, enrich portfolio, strengthen case study, improve resume, professional materials, or portfolio intelligence. Retrieve from Local-AI Qdrant knowledge and RepoWise first; never draft via a local chat LLM.
---

# Portfolio & Professional Materials — Intelligent Enrichment

Companion to `use-knowledge-access` (documents) and `use-repowise` (code).
JD / RFP / bid / proposal / interview prep is `opportunity-engine`, not this
skill. Load `use-knowledge-access` before searching OneDrive folders `01`–`06`
or `10`. Load `use-repowise` when inspecting repositories under `C:\Repos`.

Improve the portfolio, product pages, demos, case studies, resume, bio, project descriptions, and other professional materials by **using the machine's existing knowledge to make them stronger, more complete, more credible, and more compelling**.

The purpose is not to conduct an audit or prove every sentence like a legal brief. Use retrieval to **understand what exists, surface forgotten capabilities and accomplishments, generate better material, and intelligently augment the asset.**

## Use the existing knowledge systems

### Local-AI / Qdrant

Use the stable `knowledge` alias on Local-AI to surface:

* career history
* product knowledge
* business context
* past work
* methods
* proposals
* accomplishments
* reusable expertise
* relevant prior research
* approved language and professional voice

Use semantic/problem-oriented queries rather than narrow job-title searches.

Preferred:

```powershell
D:\Local-AI\query.ps1 "<what would improve this asset>" -Index knowledge -Profile client-facing -Limit 8
```

Use layered evidence augmentation when it helps uncover deeper material:

```powershell
pwsh -File packages/knowledge-access/scripts/Get-EvidenceAugmentation.ps1 -Label '<what you are writing>'
```

Do not use the `legal` collection, Duckie Qdrant (`:6333`), or fabricated indexes. Do not address the collection as `knowledge_vN`; the alias is `knowledge`.

### RepoWise / repositories

Use RepoWise across `C:\Repos` to understand what was **actually built** and discover technical capabilities worth showcasing.

Look for:

* products and features
* architecture
* AI/agents
* RAG
* embeddings/vector search
* APIs
* integrations
* automation
* data pipelines
* infrastructure
* CI/CD
* deployment
* testing
* security
* performance
* interesting technical decisions
* reusable platform capabilities

Start broad with `get_overview` / `search_codebase`, then inspect the relevant source when needed. `get_answer` is per-repo (`repo="<alias>"`); do not pass `repo="all"` to it.

### OneDrive

Use:

`D:\OneDrive - MahumTech\Documents\`

for useful career, product, client-work, methodology, startup, certification, research, and professional-profile material.

Navigate through the indexes/catalogs rather than recursively scanning everything.

For public-facing assets, use the `client-facing` profile and avoid private/confidential material or client names that have not been cleared.

When sources disagree, prefer this order: production/runtime → repository/code → validated project docs → OneDrive/source documents → recent analyses → older summaries → AI-generated summaries.

## How to use the information

Do not mechanically copy retrieved text.

**Interpret, synthesize, adapt, rewrite, combine, and improve it.**

For each asset:

1. Understand what the page/resume/case study is trying to accomplish.
2. Retrieve relevant knowledge from Local-AI, RepoWise, OneDrive, and the actual product/repository.
3. Identify valuable capabilities, accomplishments, insights, examples, and context that are missing or underrepresented.
4. Decide what would make the asset substantially stronger.
5. **Rewrite and enhance the actual asset.**
6. Add credible detail, specificity, technical depth, business context, and stronger storytelling where appropriate.
7. Remove weak, generic, repetitive, outdated, or low-value material.
8. Keep the final result coherent rather than turning it into a dump of retrieved facts.

## Be generative, not merely extractive

Use the available knowledge as raw material.

You may:

* synthesize several pieces of evidence into a stronger explanation
* translate technical implementation into understandable business value
* infer reasonable capability categories from demonstrated work
* create stronger case-study narratives
* rewrite resume bullets substantially
* improve positioning
* reorganize sections
* generate better headings and descriptions
* add useful technical detail
* connect related work across projects
* surface patterns of expertise demonstrated across several repositories
* create compelling but realistic descriptions of what the work demonstrates

Do **not** require an existing sentence somewhere else before you can write a better one.

The goal is **credible synthesis**, not transcription.

Never invent metrics, customers, achievements, technologies, or experience. Fail closed on unsourced numbers and uncleared client names.

## Portfolio/project enrichment

For each relevant product or project, strengthen whatever matters most:

* what the product does
* the problem it solves
* important workflows
* architecture
* AI/agent capabilities
* RAG/retrieval/vector infrastructure
* integrations
* infrastructure/deployment
* automation
* testing/reliability
* interesting engineering decisions
* differentiation
* business relevance
* outcome/value
* screenshots/demo story
* capabilities the project demonstrates

Avoid generic statements such as:

> Built an AI-powered platform.

Prefer descriptions that actually communicate the sophistication and usefulness of the work.

## Resume / bio / professional profile

Use the combined knowledge base to improve:

* positioning
* summaries
* experience
* accomplishments
* project bullets
* technical depth
* leadership/ownership
* AI expertise
* platform/architecture work
* business impact
* portfolio links
* skills and capability framing

Make the person sound **strong, experienced, technically credible, and modern**, without turning the material into exaggerated marketing.

It should survive a real interview, but it does not need to read like a compliance document.

## Cross-project synthesis

Look across repositories and knowledge sources for recurring strengths such as:

* AI agents
* RAG
* retrieval infrastructure
* embeddings/vector databases
* model orchestration
* automation
* SaaS/platform engineering
* integrations
* DevOps
* product architecture
* browser automation
* testing
* deployment
* analytics
* product strategy

Use repeated evidence to strengthen higher-level portfolio positioning and capability sections.

## Index awareness

If the `knowledge` index is clearly missing useful material or obviously stale compared with files you encounter, note it.

Refresh only when appropriate and authorized (`ai.ps1 refresh knowledge` is not a default step).

Do not create duplicate Qdrant indexes or use local chat LLMs to write the material.

**You are the writer.** Do not start llama.cpp, Ollama chat, Open WebUI generation, or `:8787/v1/chat/completions` to draft.

## Standard

The finished asset should feel:

* specific
* substantial
* polished
* credible
* realistic
* technically informed
* commercially understandable
* modern
* differentiated
* concise enough to read

Do not turn the work into a research report.

**The retrieval systems exist to help you produce better material. The final product is the improved portfolio/resume/case study itself.**

## Completion

Return only:

* **Improved:** assets changed
* **Added:** useful capabilities, context, stories, or accomplishments surfaced
* **Rewritten:** weak sections substantially upgraded
* **Removed:** stale, repetitive, generic, or low-value material
* **Augmented:** new credible content created from the combined knowledge
* **Remaining opportunities:** only meaningful areas that could still materially improve the portfolio
