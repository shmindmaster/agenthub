# Current State

Verified 2026-08-08. This file records demonstrated reality, not intent.

## Operational today

- **Media-studio delivery finish (2026-08-26):** `Finish-Media.ps1` is the
  compose loudness helper. Two-pass **linear** `loudnorm` to −16 LUFS /
  −1.5 dBTP (Apple Podcasts spoken-word / existing PDS gate). One-pass
  dynamic loudnorm is refused. Optional FFmpeg sidechain duck for a music
  bed. AAC-LC 48 kHz Fast Start. Not an enhancer: no DeepFilterNet,
  Resemble Enhance, or Descript Studio Sound on owner voice.

- **Fleet evidence capture (2026-08-26):** browser-toolkit owns one capture
  contract. Web stills/console/network use the host browser or Playwright MCP;
  **session video and traces use Playwright CLI** (fleet MCP does not pass
  `--caps=devtools`). Native Windows windows and the whole desktop use
  `desktop-evidence` → `packages/browser-toolkit/scripts/Capture-Screen.ps1`
  (FFmpeg `gdigrab`). Files go to `%LOCALAPPDATA%\AgentHub\evidence\<task>\`,
  never into a git repository. Chrome DevTools MCP stays retired.

- **Exa MCP authentication is environment-backed (2026-08-17):** the canonical
  remote server sends `x-api-key` from `EXA_API_KEY`; no key value is stored in
  the registry or any generated host configuration. The Codex MCP writer now
  translates canonical `${env:NAME}` HTTP headers to native
  `env_http_headers` entries, which avoids falling through to OAuth for Exa.
  A synthetic regression fixture proves both the rendered mapping and that an
  available secret value is not resolved into `config.toml`.

- **Canonical Sarosh narration voice (2026-08-11):** Local-AI now exposes one
  personal narration route: transcript-conditioned Qwen3-TTS Base ICL through
  `ai.ps1 voice qwen-clone --voice sarosh`. The owner preferred it in a local
  listening comparison; the retained validation line was complete at WER
  0.000 and 145.8 WPM. Chatterbox Sarosh profiles, aliases, x-vector-only
  cloning, meeting/singing profiles, shootout profiles, and loose references
  are retired. The AgentHub local-AI and media-studio-generate skills
  enforce the same route across managed hosts.

- **Fleet-wide Sarosh expression split (2026-09-02):** AgentHub exposes three
  composable personal skills: `sarosh-communication` for direct interactions
  and concise messaging, `sarosh-writing` for evidence-led long-form artifacts,
  and `sarosh-audio-voice` as a thin route into the existing Local-AI `sarosh`
  clone and identity gates. Each has one global capability owner; none is
  owned or deployed by a client or product repository.

- **Fleet-wide Sarosh expression split (2026-09-02):** AgentHub exposes three
  composable personal skills: `sarosh-communication` for direct interactions
  and concise messaging, `sarosh-writing` for evidence-led long-form artifacts,
  and `sarosh-audio-voice` as a thin route into the existing Local-AI `sarosh`
  clone and identity gates. Each has one global capability owner; none is
  owned or deployed by a client or product repository.

- **Owner-voice output is now measured, not assumed (2026-08-15):** until this
  date the stack had no speaker-identity measurement at all, so the 2026-08-11
  selection above — and every reference change since — was a listening call on a
  single candidate. `ai.ps1 voice score` gates any generation against an
  enrolled profile using two independent embedders (ReDimNet2-B6 and CAM++),
  with the floor derived from the owner's own recordings rather than hard-coded.
  Backends were chosen by measured separation on real audio;
  `wavlm-base-plus-sv` was rejected because it scored up to 0.851 between
  *different* speakers against a same-speaker floor of 0.879.

  Three findings that were invisible before it existed. Retro-scoring 148
  already-delivered brief segments found **6 below the floor**, one at 0.205
  against a floor of 0.505, inside audio that had already gone out. Phonetic
  respelling — the leading candidate fix for the Sarosh/Pendoah mispronunciation
  — was the only orthography variant to **fail** the identity floor on both
  backends, so respelling to fix a vowel changes the speaker. And the canonical
  route itself had never worked from a non-PowerShell caller: `ai.ps1` is an
  advanced script, so under `pwsh -File` the `--out` argument prefix-matches
  `-OutVariable`/`-OutBuffer` and it aborts before running.

- **Engine selection is a shootout, not a memory (2026-08-15):** VoxCPM2 (48 kHz
  native) and IndexTTS-2.5 are installed, registered in `registry.json`, and
  dispatch through `ai.ps1 voice voxcpm|indextts`. On a fixed 10-line evaluation
  script VoxCPM2 beats the Qwen incumbent on 8 of 10 lines
  (redimnet 0.725 vs 0.681, camplus 0.754 vs 0.738). The margin is modest and
  **neither engine reaches the genuine-recording band** (redimnet 0.749–0.900),
  so zero-shot cloning from one reference is measurably not this speaker and the
  default engine has not been changed on this evidence alone. The two lines the
  incumbent wins are both proper-noun lines, which is independent support for
  fixing pronunciation in a dictionary layer rather than by swapping engines.

- **Mobile development is one canonical capability (updated 2026-08-20):**
  `packages/mobile-development` version 2.0.4 owns the public `mobile.ps1`
  entrypoint and both loose skills. Every active coding host receives the
  skills and catalog discovery. Appium remains absent from persistent MCP
  configuration and may be activated only for Claude or Codex; both native
  routes require a new task after enable/add or disable/remove. Product scope
  and identity remain in `registry/mobile-scope.json`, the Appium pin remains
  in `registry/mcps.json`, and VM hardware remains live VMX state. Fleet sync
  and live synthetic smoke are separate acceptance gates.
- **Current host evidence (2026-08-20):** Codex, Qoder, and Factory are active.
  OpenCode Desktop, Hermes, and Windsurf remain unverified on this workstation.
  Mobile skills/catalog are deployed to active coding surfaces, while native
  Appium activation is intentionally available only through Claude and Codex.
- Registry (`registry/*.json`) declares hosts, capabilities, MCP servers,
  fleet profile, and the fleet repository standard roster.
- `scripts/Validate-AgentHub.ps1` validates the registry against on-disk
  package content (content hashes over git-tracked files).
- `tests/Run-AllTests.ps1` runs all behavior tests and package validators.
- Sync scripts deploy managed instructions/skills/MCP config to host user
  directories (`Sync-AgentHub.ps1`, `Sync-Capabilities.ps1`, audit by default).
- **Knowledge-access documents layer (2026-08-21):** capability
  `knowledge-access` (`packages/knowledge-access`) is the sibling of
  RepoWise for `D:\OneDrive - MahumTech\Documents\` folders `01`–`06` and
  `10`. `_INDEX.md` and `AGENTS.md` sit at that Documents root; `_MAP.md`
  is a pointer. Exact search uses WSL `rga` 0.10.10 plus pandoc/poppler
  (no Windows rga build exists). Opportunity rendering is
  `opportunity-engine`; portfolio and professional-material enrichment is
  `portfolio-enrichment`. Runtime records are the private repo
  `C:\Repos\shmindmaster\portfolio-records` (three fail-closed YAML
  records as of 2026-08-21 evening; synthetic fixtures stay in the
  package). Semantic search is Local-AI Qdrant alias `knowledge` (catalog
  `data\catalog\corpus-v2.sqlite`, collection `knowledge_v1`, Docker
  named volume on host `127.0.0.1:16333`). Alias cutover waits on reindex
  parity. Nested-git scan of folders `02`–`06` found **no** `.git`
  directories. Agents were stalling on a 6k-line `_MAP.md` and recursive
  `Get-ChildItem`; filenames live in `_CATALOG.md`, taxonomy in
  `_ENGAGEMENTS.md`. Portfolio Audit is not the retrieval skill for this
  tree. GPU embed/rerank stays native (`ai.ps1`); do not add a second
  Docker RAG container. Duckie keeps host `6333`.
- **RepoWise workspace** at `C:\Repos` (relocated 2026-08-21 from
  `C:\Repos\shmindmaster`; created 2026-08-08): covers git repos under
  `shmindmaster`, `sh-pendoah`, `musa-dev-team`, and `pendoah` (**63
  members** as of 2026-08-24: 18 shmindmaster including
  `portfolio-records`, 1 sh-pendoah, 2 musa-dev-team, 42 pendoah). All 63
  indexed, 0 stale vs HEAD. Nested fixture gits are not members
  (`crewscore/.corpus-cache/*`, `duckie-app/deploy` which is
  `duckie-deploy`). CLI 0.44.0, kept on PyPI latest by
  `scripts/Update-RepoWise.ps1`. MCP is local stdio `repowise mcp C:/Repos`.
  **Local-only:** not signed in to a hosted RepoWise account; telemetry
  disabled 2026-08-24 (`repowise telemetry disable`); indexes stay in each
  repo's `.repowise/` plus `C:\Repos\.repowise-workspace\`; default update
  is `--index-only` (no LLM). Do not `repowise login`. agenthub is the
  default/primary repo. On-demand-local: Claude is wired, other hosts use
  the `use-repowise` skill plus CLI.
- **Fleet checker**: `scripts/Check-RepoStandard.ps1` with fixture tests in
  `tests/Test-RepoStandard.ps1` (11 behavior checks, passing 2026-08-08).
- **Skill deployment ledger**: fixed 2026-08-08. `Sync-Capabilities.ps1` wrote
  `managed-skills.json` only after the failure gate, so any run with a refusal
  copied skills to disk and recorded none of them — stranding every skill
  deployed between 2026-08-06 and 2026-08-08 as permanently "unowned". The
  ledger now writes before the gate and records only what the run can claim
  (refused-and-never-owned excluded; refused-but-owned carried forward with
  its prior hash so the modification stays detectable). Live ledger recovered
  from 469 destinations at 2026-08-05 to 501 current.
- **Mobile scope guard**: `registry/mobile-scope.json` classifies all 21
  products (5 eligible, 4 evaluate-later, 2 frozen, 10 no-native); the
  prohibition is compiled into every managed host by `Sync-Instructions.ps1`;
  `tests/Test-MobileScope.ps1` (5 behavior checks, passing 2026-08-08, each
  demonstrated failing against a synthetic fixture) keeps registry and policy
  true together.
- **LienWise rename (2026-08-08)**: the product frozen by the mobile guard on
  2026-08-07 was repositioned and renamed. The owner rewrote all 296 commits
  with `git filter-repo` and force-pushed, so the retired name is absent from
  content, filenames, and commit messages across the whole history — verified
  independently here. Fleet references (`repo-standard.json`,
  `mobile-scope.json`, the DigitalOcean portfolio/DNS skills, the
  product-demo-studio compatibility table, the product-experience-engineering
  leak guard, and the RepoWise workspace) now say `lienwise`. The freeze exit
  condition was met, so it moved to `include` (P1). **Pre-rewrite SHAs are
  dead**: any other checkout needs `git fetch && git reset --hard origin/main`.
- **What a history rewrite does not reach** (measured on lienwise 2026-08-08,
  and true of any future rename): `git push --force` rewrites branches only.
  Three surfaces survive it and are worth checking before declaring a rename
  complete.
  - **Unmerged branches.** `lienwise/m0-rebrand-and-domain` still descended
    from pre-rewrite history and carried the retired name in **343 files and
    46 commit messages**. Verified superseded (its 8 unique files were older
    docs and `CLAUDE.md` adapters that `main` replaced), then deleted.
  - **`refs/pull/*/head`.** All **163** carried it; **zero** were reachable
    from `main`. GitHub keeps these as immutable PR snapshots — no push
    removes them. 8 merged PR titles also still name the product. Left alone
    deliberately: editing a title whose own diff still says the old name makes
    the record incoherent, and the refs beneath it are permanent regardless.
  - **Gitignored working files.** `backend/.env` still pointed at a database
    named after the retired product (dead — nothing was listening on its
    port), and `frontend/out`, `.next`, `test-evidence`, and `test-results`
    held pre-rename output. None are tracked, so no rewrite touches them.
    Repointed at the compose database; artifacts deleted.
  - **Vendor vocabulary, not just the product name.** A de-brand that greps
    for the product name misses everything the retired positioning dragged
    in. Here that was a payment rail (`SlimCD`) named across the design
    system, its bundled demo payload, and a demo QA script — describing
    "customer parts payments" for a product that now sells Stripe-billed
    SaaS. Grep the vendors, partners, and third-party systems too. Two
    negative test assertions deliberately still name it: they fail if it
    reappears in the API surface, so they are the enforcement.
  - Clean end state: `git ls-remote` shows `refs/heads/main` and nothing else.

- **Third-party extension tracking (updated 2026-08-24)**: `registry/native-connectors.json`
  -> `thirdPartyExtensions` records plugins *and* non-plugin upstream
  distributions the fleet uses but does not own. Tracked today:
  **superpowers** (obra/superpowers; Claude observed at 6.3.0), **firecrawl**
  (firecrawl/skills), **clerk-skills**, **railway**, **framer-agent**,
  **elevenlabs-skills**, **do-app-platform-skills**, **remotion**, and
  optional **creative-writing-skills**. AgentHub overlays may add fleet
  policy (Firecrawl ingestion governance, owner-voice routing, DigitalOcean
  portfolio map) but must not republish upstream skill names. Measured
  2026-08-24: AgentHub had been publishing `clerk@agenthub` and
  `firecrawl@agenthub` and deploying vendored `use-railway` / Framer skills
  as managed loose skills, which pinned hosts and would have downgraded
  Railway from 1.3.7 to 1.3.6 on the next Apply. Those packages are gone
  from the marketplace and `packages/`. `tests/Test-ThirdPartyPlugins.ps1`
  fails if a lagging host names no fix, if an absent host explains no
  reason, or if a tracked extension is ever republished from AgentHub's own
  marketplace. `hostPrivateExtensionPolicy` withholds install authority for
  claude and codex.
- **Capability bundles (2026-08-21)**: `registry/bundles.json` names recipes such
  as `technical-series-production` and `engaging-learning` that compose AgentHub
  packages with tracked third-party extensions. Bundles are install-planning
  metadata, not mega-plugins (`tests/Test-Bundles.ps1`).
- **Portable plugin version authority (2026-08-21)**: root `plugin.json` is the
  Agent Plugins floor and single version authority; host projections must match
  (`scripts/Bump-PackageVersion.ps1`, `tests/Test-PluginManifests.ps1`).
- **Creative / learning packages (2026-08-21)**: `technical-storytelling`,
  `story-series-studio`, and `learning-studio` are registered packages.
  `startup-series` is now a Receipts-only overlay (`startup-showrunner`,
  `comedy-writer`); generic craft lives in the studio packages. Private show
  bibles stay outside AgentHub.

- **Local media studio (2026-08-25, craft 2026-09-02):** `packages/media-studio`
  is the **only public** video/audio/animation pack (`1.4.0`). Rapid default: a
  concept or outline is enough; writer → storyboard → visuals → director →
  Local-AI generate → Remotion/FFmpeg/Recast compose → craft critic → QA.
  Viewer-facing jobs apply `engagement.md` plus `story-craft.md` and the
  scene-archetype kit; `media-story-experience-reviewer` fails closed below 85.
  `intent: draft` skips GPU plates and the critic gate. Remotion is required
  for viewer-facing briefing/training/explainer/series-episode unless draft.
  Product screencasts keep the PDS killer-demo / story-experience gate. Kinds:
  briefing, training, explainer, talking-head, animation, audio-only, and
  `product-screencast`. `product-demo*` **skills are fleet-retired**; the
  Playwright + Recast + four-domain engine remains in
  `packages/product-demo-studio/pipeline` and is invoked by media-studio, not
  loaded as a public skill. Owner voice remains
  `ai.ps1 voice qwen-clone --voice sarosh`. Remotion is official
  `remotion-dev/skills` 4.0.517 (not vendored), installed globally under
  `~/.agents/skills` and recorded current on Claude and Codex. FFmpeg/ffprobe
  are on PATH. Local-AI motif/lipsync/portrait routes are installed and
  documented in `local-ai-stack` `references/video.md`. Product repositories
  are read-only media inputs: job config, capture/Playwright code, Remotion
  composition, dependencies, fixtures, assets, evidence, and generated media
  remain in the external Media Studio workspace. Product fixes require a
  separate explicitly authorized engineering task. Media-studio maps as
  `managed-loose-skills` on skill-only hosts (including Grok) so Sync copies
  into those skill dirs.

## In progress

- Fleet-wide repository standardization to the
  [repo standard](./development/repo-standard.md): plan and live status in
  [plans/active/fleet-repo-standardization.md](./plans/active/fleet-repo-standardization.md).
- Mobile platform rollout for the eligible products: plan and live status in
  [plans/active/mobile-scope-guard.md](./plans/active/mobile-scope-guard.md).
  The guard and the standard are landed; per-product implementation
  (Rexa reference build, abacare `apps/mobile`, gentlenext) is not started.

## Test suite: green, with one intermittent hang (2026-08-11)

**194 passed / 0 failed across all 27 test files**, each run to completion.
Every failure the section below records is now fixed:

| File | Was | Now |
| --- | --- | --- |
| Test-CapabilityRouting | 5 assertions failing on `use-chrome-devtools-mcp` | 9/9 — the skill is a provider reference, not a router; see below |
| Test-DeclaredPathAccountability | 4 (later 7) hermes/qoder paths with no note | 4/4 — every absent path carries a sourced note |
| Test-ScriptsFailLoudly | `Start-ChromeAgentCDP.ps1` missing `$ErrorActionPreference` | passing; fixed at some point before 2026-08-11 and never recorded |
| Test-RepoStandard | 8.3 short-path comparison | fixed 2026-08-08, already recorded below |

`use-chrome-devtools-mcp` was never a routing skill — it is the tool catalog
the three routing skills load *after* resolving a provider. It now declares
`<!-- skill-kind: provider-reference -->`, and a new behavior 9 checks that
claim rather than trusting it: an excused skill must be named by a routing
skill and must document a registered server. The kind defaults to `routing`,
so the exemption cannot be taken by omission.

**The one thing not verified end to end: `Run-AllTests.ps1` hung twice on
2026-08-11**, both times at `Test-SyncAgentHubRegistryRoot` →
`Sync-AgentHub.ps1 -Audit` → `Repair-QwenCodeMcpOAuth.js --check`. The child
`node` sat at 0.1s CPU for minutes — blocked, not slow, and not catastrophic
backtracking. It is not that test and not that script: the test passes 5/5 in
isolation in well under its budget, and the script alone exits 0 in seconds
with 70 bytes of output. It reproduces only inside the full runner, and only
under the heavy concurrent load this machine carried that day (several agent
sessions each running chrome-devtools-mcp, desktop-commander and appium-mcp,
plus a Remotion render). Treat a `Run-AllTests` hang as this, not as a new
failure — and confirm by running the named file alone. Root cause unknown;
a suite that hangs intermittently is nearly as useless as one that is red, so
this is worth chasing when the machine is quiet.

## Known pre-existing test failures (as of 2026-08-08, all now fixed — see above)

Re-measured 2026-08-08 against a clean clone of `8ae18ff`: **163 passed / 4
failed** across 26 files. Four earlier entries (Test-AgentHubEntryPoint,
Test-CrlfAnchors, Test-SyncAgentHubIdempotency, Test-SyncCapabilities) now
pass; `Test-RepoStandard` newly fails and is **not** the 11/11 this file
previously claimed.

The 4 failing files are agenthub's own engineering debt:

| File | Cause |
| --- | --- |
| Test-CapabilityRouting | `use-chrome-devtools-mcp` carries no `## Capability required` or `## Resolve a provider` section (5 assertions) |
| Test-DeclaredPathAccountability | 4 hermes paths absent from disk with no `<field>Note` |
| Test-ScriptsFailLoudly | `Start-ChromeAgentCDP.ps1` does not set `$ErrorActionPreference = 'Stop'` |

The mobile scope guard added `Test-MobileScope.ps1` (+5) and the
Sync-Capabilities ledger fix added one behavior (+1), changing no failure:
169 passed / 4 failed.

**`Test-RepoStandard` was the fourth, and is fixed as of 2026-08-08.** It was
never fixture noise. `Check-RepoStandard.ps1` compared `Get-ChildItem`'s
`FullName` against a path built from the configured `fleetRoot`; those two
disagree whenever the root is spelled differently on disk — an 8.3 short path
(`C:\Users\SAROSH~1\...`, which is exactly what `$env:TEMP` returns here), a
`subst` drive, a symlink. The root `AGENTS.md` then failed the "is this the root
file" test and was audited as a nested one, with its relative path sliced at the
wrong offset (`iant\AGENTS.md`). `Get-Item` expands 8.3; `Resolve-Path` does not.
Two further findings from the same pass: the `nested-refs-root` rule accepted only
two exact phrasings and rejected lienwise's perfectly clear "Root contract still
applies: [`../AGENTS.md`]", and the whole nested-AGENTS rule had **no fixture
coverage at all**, which is why both defects sat unnoticed. Three behaviors added,
covering pass, fail, and the root-is-not-nested case. Suite now **179 passed /
3 failed**. `Test-ThirdPartyPlugins.ps1` then
added six more: **175 passed / 4 failed** across 28 files, still the same four.

## Known constraints

- The checker compares the RepoWise index to `HEAD`; a repo with uncommitted
  in-flight work is fine (hook syncs on commit), but a just-committed repo
  shows stale until the hook or `repowise update --repo <name>` runs.
- `.claude/CLAUDE.md` and `.vscode/mcp.json` are RepoWise-generated per repo;
  they are gitignored / tool-managed respectively, never hand-maintained.

## Verification

```powershell
pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1
pwsh -NoProfile -File .\tests\Run-AllTests.ps1
pwsh -NoProfile -File .\scripts\Check-RepoStandard.ps1 -All
repowise status -w   # from C:\Repos
```
