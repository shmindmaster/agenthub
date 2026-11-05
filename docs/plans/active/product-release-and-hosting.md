# Product release and hosting continuation

## Purpose, scope and execution boundary

Prepare the **next session**, not another implementation or deployment in the
planning session. The four lanes are Revolva, CoLedger, Empowera and AgentHub
Runware, with a shared DigitalOcean/Railway custody and retirement lane.
Rexa is explicitly excluded from product work and is not a fifth product lane.

The intended outcome is a reviewed, exact-source release of the already
implemented synthetic features where their gates permit it, plus a rights-safe
hosting disposition. An unknown gate stays blocked. This plan does not authorize
new features, new paid infrastructure, customer-data processing, outreach,
credential changes, destructive cleanup or a provider experiment.

Planning-session changes are documentation only. No application implementation,
cloud changes, provider calls, Linear changes or Notion changes are part of this
plan preparation. The closing session's coordinator owns its tracker closeout.
Next-session execution must re-establish current authority before any mutation.

### State vocabulary and evidence boundary

Use separate fields for **implemented → tested → committed → reviewed →
merged to dev (if applicable) → in main → deployed → production-verified →
user-accepted**. A green test or resolved review thread does not imply deployment.
These repositories do not need an invented `dev` release stage.

The public plan contains public source references and operational requirements,
not private infrastructure receipts. Exact resource identities, SSH details,
account inventories, raw logs, billing receipts, object manifests and data
custody evidence remain in the existing restricted operator records. Do not
paste those records, private input files, contacts, personal information,
credentials, private rows, dumps or files into this repository.

Snapshot: **2026-11-05 UTC** (the closing session began November 4 local time).
GitHub PR pins below were read directly during planning. Provider observations
are coordinator handoff claims, **not independently refreshed by this plan**.
Any later remediation report or changed head invalidates the old test attribution.

## Current inventory: what is and is not established

| Lane | Public source pin / current rung | Verified or reported evidence | Next gate / not established |
| --- | --- | --- | --- |
| AgentHub Runware, SH-3723 | In `origin/main` at [`b5258c91`](https://github.com/shmindmaster/agenthub/commit/b5258c9167f4d7e65e820ca821199a44cff3462f), media-studio 2.1.3 | Coordinator reports 25 adapter tests and validation passed. Copilot `ah-media-studio@agenthub` 2.1.3 is ENABLED from local canonical source; Claude 2.1.3 is ENABLED and contains `runware-image.mjs` | Two surfaces checked on disk; hash comparison pending. Other surfaces UNKNOWN/not checked; fresh-session consumption and Empowera's own SME release remain separate; no paid still regeneration to prove installation |
| AgentHub generic hosting routing | [PR #104](https://github.com/shmindmaster/agenthub/pull/104), MERGED at `a0717c6fd6699afb8c2520d5beaf70153a2d243a` per final coordinator closeout | Router-link finding fixed/resolved in `04260f9`; final docs-only relative link checked. Prior candidate Linux/macOS/Intel, four Doctor jobs and CodeRabbit passed; 18 targeted validator passes reported. Windows baseline had the same two failures (1,590 passes / two failures) | Merge used an explicit baseline exception, not a full Windows-green claim. Refresh merged main at entry; no unrelated Windows remediation is assigned here |
| Revolva release guard | [PR #54](https://github.com/shmindmaster/revolva/pull/54), MERGED at `353314d2ed3e77a7bc54a1b2f1f15955d97e872c` | Guard refuses `--deploy` before evidence or provider access; coordinator reports 23 guard tests and PostgreSQL CI passed | This is a deployment prohibition, not a DigitalOcean backend or a voice release |
| Revolva voice, SH-3720 | [Draft PR #53](https://github.com/shmindmaster/revolva/pull/53), `99b6220ad9c8da4c5430b557e97f8a3c038c8e84` | Exact parent is `b36410e` (SH-3714 candidate, 22 commits including PR #51 ancestry). Reported validation: 342 unit, 32 e2e, 12 mobility passes | No substantive approval; stacked scope unresolved; complete rehearsal evidence blocked by archive lacking `.git`; not merged/deployed |
| CoLedger controller audio, SH-3722 | [PR #188](https://github.com/shmindmaster/coledger/pull/188), OPEN at `1ecff71eb89d224c791013746552690e2fe00d59` | Final remediation report: all ten threads resolved; exact-archive `pnpm verify`, security 14/14 and release eval 8/8 passed. Mocked e2e: five passes / 59 browser-launch failures because `libnspr4` was missing | Same remediation lane is correcting Daytona dependencies and rerunning full browser/PG capsule CI. Deployment verification pending; launch failures are not demonstrated application failures or a complete browser PASS |
| Empowera voice and illustrations, SH-3719 / SH-3721 | [PR #68](https://github.com/shmindmaster/empowera/pull/68), OPEN at `19f2cf7f40b07fbbe52336cec5d25132b9eca416` | Coordinator reports all 13 review threads resolved, 40 web tests, six focused readiness UI tests, formatting/typecheck/build passed in Daytona; CodeRabbit successful | PR explicitly prohibits merge/deploy before SH-3716 and SH-3524 acceptance; both remain UNKNOWN/open in this handoff |
| CoLedger existing hosting | Coordinator reports existing DigitalOcean web/API run `305be214cd305fd33cd33dbe35c4be4fb86fc295` | Prior provider readback, not repeated here | Not PR #188. Refresh current spec, migrate component and all source hashes before release |
| Empowera existing hosting | Coordinator reports existing authorized DigitalOcean systemd release `61b727b`, services active | Prior SSH/runtime readback, not repeated here | Not PR #68. Active services do not prove new feature behavior or satisfy acceptance gates |
| Revolva existing hosting | Coordinator reports DigitalOcean app is static-only at `327342b` | Prior provider readback, not repeated here | Static application is not the durable backend. Retained Railway databases/web/private runner have not been safely migrated |
| Railway retained product custody | Coordinator reports Revolva/fieldbook has four services and three retained volumes | Prior metadata inventory, not a data inspection | Legacy classification and transfer rights UNKNOWN; may contain client data. No private row/dump/file retrieval or migration is permitted on that assumption |
| Reusable DigitalOcean capacity | Coordinator reports existing owner workstation is reachable and has spare CPU/RAM/disk; Node/PostgreSQL absent there | Point-in-time capacity observation; no new cost created by that inspection | Capacity is not a product runtime, database, authorization grant, isolation proof or free credit |

### Hosting decisions versus unknowns

**Decided:** current personal hosting is DigitalOcean-first. Reuse authorized
existing capacity and eligible credits before proposing new spend. Railway
account and integrations are retained for future use; do not create a current
new Railway deployment. Do not route Revolva back to Railway to evade its guard.
The coordinator reports private policy compiled to eleven managed instruction
files with zero drift. Policy deployment itself did not establish a PR merge;
PR #104 separately merged at `a0717c6fd6699afb8c2520d5beaf70153a2d243a`.
Neither establishes that a running conversation consumed the policy.

**UNKNOWN / must be checked:** promotional-credit balance, expiry, eligibility
and applicable charges; current capacity; exact live source/configuration;
private-data rights/classification; full Revolva backend target contract;
Empowera acceptance evidence; latest CoLedger remediation outcome.

The reported shared PostgreSQL inspection enumerated database/user catalog names
and found no names matching Revolva/fieldbook. It did **not** enumerate all schemas,
tables, contents or other accounts. Do not turn a name search into a full SQL
absence claim, and do not inspect private contents to resolve it.

## Source authority and issue map

Executable source at the selected candidate outranks historical runbooks and
derived RepoWise context. Read each repository's `AGENTS.md` and the relevant
runbook again before its lane executes. Several runbooks retain older runtime,
missing-app and Railway checkpoints; preserve historical evidence but do not
reuse their target identifiers without exact authorized readback.

| Outcome | Existing issue / prerequisite | Execution authority |
| --- | --- | --- |
| Empowera reviewed voice evidence | [SH-3719](https://linear.app/shorg/issue/SH-3719) | PR #68; repository `AGENTS.md`, `docs/PRD.md`, `docs/TAKEOVER.md`, current AI-task-routing contract |
| Revolva confirmed voice intake | [SH-3720](https://linear.app/shorg/issue/SH-3720) | PR #53; `AGENTS.md`, `docs/product/REVOLVA_TAKEOVER.md`, PR #51 and exact SH-3714 parent lineage |
| Empowera SOP-bound illustrations | [SH-3721](https://linear.app/shorg/issue/SH-3721) | PR #68 consumer; SH-3723 producer; separate human SME approval/release |
| CoLedger reviewed controller audio | [SH-3722](https://linear.app/shorg/issue/SH-3722) | PR #188; `AGENTS.md`, `docs/product/RELEASE_TAKEOVER.md`, `infra/digitalocean/RUNBOOK.md`, `scripts/verify-release.ps1` |
| AgentHub bounded Runware adapter | [SH-3723](https://linear.app/shorg/issue/SH-3723) | Commit b5258c91; [cloud contract](https://github.com/shmindmaster/agenthub/blob/b5258c9167f4d7e65e820ca821199a44cff3462f/packages/media-studio/kit/cloud/README.md), `docs/development/agent-change-contract.md` |
| Revolva demonstration/release parent | [SH-3714](https://linear.app/shorg/issue/SH-3714), [PR #51](https://github.com/shmindmaster/revolva/pull/51) | Establish exact ancestry, full scope, review and source-bound rehearsal evidence before voice integration |
| Revolva real-data/commercial boundary | [SH-3520](https://linear.app/shorg/issue/SH-3520), SH-3521–3523 conditional children; SH-3369 historical custody | Buyer/corridor decision does not itself grant data-transfer rights |
| Empowera acceptance blockers | [SH-3716](https://linear.app/shorg/issue/SH-3716), [SH-3524](https://linear.app/shorg/issue/SH-3524) | Demonstration/review and independent assessor acceptance; no inferred pass from review automation |
| Empowera broader acceptance | SH-3514 / SH-3517 and their retained accessibility gaps | Preserve separate manual assistive-technology and qualification evidence |
| CoLedger release acceptance | [SH-3515](https://linear.app/shorg/issue/SH-3515), SH-3513; retained source/citation scope SH-1935 | Exact reviewed → main → ACTIVE chain plus synthetic workflow, grants and isolation |

Issue links identify existing outcomes, not newly verified tracker statuses.
Resolve the current issue body, explicit dependencies and acceptance owner at
entry. Do not duplicate issues or mark broad parent outcomes Done for a narrow
feature. AgentHub uses repository execution plans rather than introducing an
external tracker as its control plane.

## Owners, lanes and scheduling

- **Coordinator:** owns entry reconciliation, authority, dependency ledger,
  cross-lane integration, release decisions and honest tracker closeout.
- **Product implementer:** one responsible agent per product, bounded to the
  existing feature/remediation and its native release contract.
- **Independent reviewer:** verifies exact diff, findings and evidence without
  silently changing the acceptance scope.
- **Acceptance owner:** owner-selected practitioner/controller for Revolva or
  CoLedger; independent qualified assessor/SME for Empowera. Named people and
  their qualification evidence are not established here.
- **Hosting/custody operator:** metadata-only inventory and authorized target
  proposal first; no private data transfer while rights are UNKNOWN.

Parallelize independent review, metadata proposals and synthetic remote checks
only after assigning non-overlapping repositories/files. Do not start another
coding host, local AI, macOS VM or Docker. Keep background helpers hidden.
No new scheduled jobs or always-on services.

Use native read-only commands for entry. Prefer existing authorized DigitalOcean
capacity for hosting; use an admitted remote validation lane for tests. Daytona
work is bounded, labeled `owner=<product>` / `purpose=<action-id>`, TTL at most
120 minutes, with at least 60 of 250 vCPU left free and deletion confirmed at
completion. Observe the existing $150/day and $500 total ceilings, not targets.
Capacity/provider admission is a next-session check, not a planning-session call.
Local heavy tests are excluded. Report actual job lane, duration and cost;
unknown cost is UNKNOWN, not zero or credit-covered.

## Action inventory

All rows are **next-session pending or blocked**. Dependencies are prerequisites,
not merely suggested execution order. P0 protects custody and prevents a false
release; P1 completes eligible releases; P2 closes optional acceptance/cleanup.

| ID | Priority / owner / lane | Smallest action | Depends on | Required observable result |
| --- | --- | --- | --- | --- |
| ENTRY-01 | P0 coordinator / native read-only | Inspect status, branches, worktrees, remotes, active PRs and final closing-session reports in all four repositories | None | Exact heads, concurrent ownership and changed-path inventory recorded; no checkout reset or broad staging |
| ENTRY-02 | P0 coordinator / source + tracker read | Read applicable instructions, current issue acceptance/dependencies and selected source/runbooks | ENTRY-01 | Explicit permitted scope, acceptance owner, blocked gates and latest status per action; distinguish source facts from coordinator reports |
| ENTRY-03 | P0 coordinator / policy read | Resolve current private DO-first policy and fleet dispatch; confirm current capacity/budget admission without exposing secrets | ENTRY-02 | Authorized validation/hosting lanes and spend basis; credit balance/expiry remains UNKNOWN until authoritative receipt |
| HOST-01 | P0 custody operator / metadata-only provider read | Enumerate the exact authorized DO/Railway account/project/service/volume/dependency space | ENTRY-03 | Current identities, dependency map, billing/retention state and inventory scope in restricted records; no private content retrieval |
| HOST-02 | P0 owner + custody operator / decision | Classify legacy Revolva custody, transfer authority, retention obligations and required preservation | HOST-01 | Explicit signed-off disposition per retained service/volume; UNKNOWN means keep, do not dump/copy/delete |
| AH-01 | P0 AgentHub implementer + reviewer / GitHub | Reconcile merged PR #104, final router-link correction and documented Windows baseline exception | ENTRY-02 | Merge `a0717c6`, correction `04260f9`, prior candidate checks and docs-only final-delta evidence attributed separately; no unrelated Windows fix or full-green claim |
| AH-02 | P0 coordinator / isolated Git lane | Preserve all local-main owner commits (latest closeout: clean `5aa7c05`, ahead four); identify overlap with incoming work | ENTRY-01 | Clean reviewed integration lane based on remote main; no push of user-owned local history, no loss of concurrent edits |
| AH-03 | P1 AgentHub operator / native sync | Validate package/registry, compare installed Copilot/Claude bytes with canonical source, audit remaining applicable surfaces; apply only demonstrated authorized gaps | AH-01, AH-02, ENTRY-03 | Affected validators and exact package/hash readback pass; audit receipt, plus apply/re-audit if needed; no unnecessary reinstall or paid request |
| AH-04 | P1 AgentHub reviewer / fresh-session read-only | Prove on-disk deployment and runtime consumption separately for the actual surface | AH-03 | Fresh-session discovery/entrypoint/version evidence; unsupported or unchecked hosts stay UNKNOWN; no second coding host launched concurrently |
| REV-01 | P0 Revolva implementer + reviewer / Git | Review the SH-3714 parent and PR #51 ancestry; reconcile current main including guard PR #54 | ENTRY-02 | Complete commit-scope inventory and chosen ordered integration strategy; no blind 22-commit merge or unexplained dropped parent work |
| REV-02 | P0 Revolva implementer / admitted remote validation | Repair source-bound rehearsal setup: use a clean real Git checkout, exact SHA, archive/lock/runner hashes and retained stage evidence | REV-01, ENTRY-03 | All native stages including rehearsal pass against the final candidate; missing `.git` no longer substitutes a source-only pass |
| REV-03 | P0 Revolva reviewer / exact evidence | Validate complete Daytona and exact-SHA PostgreSQL receipts and retain deployment refusal | REV-02 | `scripts/release.mjs` evidence verification passes; `--deploy` still fails before provider access; tampered/wrong-source evidence fails |
| REV-04 | P1 custody operator + Revolva owner / target design only | Propose isolated synthetic DO backend/database/runner placement using existing eligible capacity | HOST-01, REV-01 | Reviewed target contract, bootstrap/migration plan, capacity/isolation/cost/rollback evidence; static-only app is not accepted as backend |
| REV-05 | P1 Revolva implementer + reviewer / Git | Integrate reviewed parent then voice, reconcile guard changes, rerun changed-SHA checks | REV-03 | Reviewed final SHA and main lineage; default-off voice remains safe; in-main status distinct from deployment |
| REV-06 | P1 coordinator + hosting operator / conditional release | Only under renewed release authority, establish and review the missing DO readiness contract before any guard change/deploy | REV-04, REV-05, HOST-02 for any legacy transfer | No implementation/deploy while contract or data rights remain unknown; approved synthetic-only release may remain separate from preserved legacy custody |
| REV-07 | P2 acceptance owner / bounded synthetic evaluation | Freeze the 20-recording evaluation set and review date/number/conflict/timestamp/speaker/correction behavior | REV-05, ENTRY-02 | Owned evaluation criteria and observed outcomes; no arbitrary recording/paid transcription without explicit synthetic scope and spend admission |
| COL-01 | P0 CoLedger implementer + reviewer / GitHub | Reconcile ten resolved threads and final Daytona browser/PG rerun after missing system-library correction | ENTRY-02 | Latest head attribution, each finding's disposition and complete browser/PG evidence; earlier launch failures not labeled application failures or passes |
| COL-02 | P0 CoLedger implementer / admitted remote gate | Verify the final candidate with the native full release procedure and disposable schema-ready PostgreSQL | COL-01, ENTRY-03 | Complete exact-SHA `verify-release.ps1` PASS, required DB suites unskipped, migration review/role-trigger evidence and mocked browser results |
| COL-03 | P1 coordinator / Git + existing DO | Recheck remote-main containment, then fast-forward the exact verified SHA under release authority | COL-02, HOST-01 | `main` equals verified candidate; no unverified squash/merge SHA; automatic deployment treated as a production mutation |
| COL-04 | P1 CoLedger operator + reviewer / deployed system | Observe ACTIVE deployment with exact web/API/migrate source, PRE_DEPLOY outcome and runtime grants | COL-03 | Provider source chain and migration/privilege proof, route/DNS preservation, before/after telemetry; old web/API SHA not mistaken for release |
| COL-05 | P1 controller + reviewer / bounded deployed workflow | Verify audio review/correction, independent approval, ledger comparison, staleness and authorized private access using approved synthetic subjects | COL-04 | Real resulting workflow evidence and unchanged deterministic ledger; narrative inclusion stays unavailable; no fabricated publication acceptance |
| EMP-01 | P0 acceptance owner + coordinator / issue/evidence read | Resolve SH-3716 and SH-3524 acceptance and retained qualification/accessibility requirements | ENTRY-02 | Explicit pass evidence or precise blocked status; no merge/deploy merely because all 13 threads resolved |
| EMP-02 | P0 Empowera reviewer / exact source | Reconcile PR #68 final head, backend/DB migrations, ASR recovery and UI changes against acceptance criteria | ENTRY-02 | Review and focused tests attributable to final SHA; assess auth, upload/poll/correction and stale illustration bindings |
| EMP-03 | P1 Empowera implementer / admitted remote gate | Validate candidate's SQLite + required disposable PostgreSQL migration/role behavior, web build and native systemd archive/rollback checks | EMP-02, ENTRY-03 | Exact-candidate build/test/migration and standalone artifact evidence; previous runs/skipped PG do not cover changed source |
| EMP-04 | P1 coordinator + Empowera operator / existing host | Integrate/release only after acceptance passes; use existing isolated native install/publish/rollback contract | EMP-01, EMP-03, HOST-01 | Exact main/archive/deployed-source chain, API/web service identity, schema and safe default flags; no new host or Docker |
| EMP-05 | P1 SME + AgentHub/Empowera operators / private consumer workspace | Prove import of reusable accepted Runware output without new generation | AH-04, EMP-04 | Live inventory completeness/current selection, source/objective/hash and bytes verified; independent qualified SME downloads exact still, writes alt/text equivalent and releases it separately |
| EMP-06 | P1 assessor + reviewer / bounded deployed workflow | Verify consent, transcript corrections/spans, role boundaries, pending/retry/stale states and source-change invalidation | EMP-04 | Observed synthetic learner→assessor evidence with separate acknowledgement/assessment/authorization; current-revision result and accessibility gaps recorded |
| HOST-03 | P1 custody operator + reviewer / recovery rehearsal | Rehearse authorized synthetic runtime/metadata recovery and legacy dependency preservation without private-data retrieval | REV-04, HOST-02 | Restore/rollback method actually demonstrated in isolated authorized scope, preserved current custody and exact dependency checks |
| HOST-04 | P2 coordinator + owner / deletion decision | Retire only selected legacy resources after replacement acceptance, retention and restore gates | HOST-02, HOST-03, applicable production-verification actions | Exact deletion allowlist and authority; replacement verified first; physical removal and billing cessation independently read back |
| CLOSE-01 | P1 coordinator / tracker + docs | Update existing product outcomes and supporting Notion only when useful and authorized | Each lane's completed or blocked actions | Exact code/review/main/deploy/evidence rung, dependencies and remaining acceptance; readback proves updates; no private attachments in public docs |
| CLEAN-01 | P2 coordinator / Git + bounded compute | Remove only clean, safely retained/merged task worktrees and completed ephemeral workers | CLOSE-01, relevant integration and preservation gates | Exact-ID/path cleanup receipt; user/unmerged/dirty work preserved; sandbox deletion confirmed; account/integrations retained |

### Dependency consequences

- ENTRY-01 → ENTRY-02 → ENTRY-03 is the common entry chain. Reviews may run in
  parallel after ENTRY-02; remote tests await ENTRY-03.
- Empowera illustrations depend on both producer consumption (AH-04) and the
  qualified product release path (EMP-04). Adapter acceptance never substitutes
  Empowera's own release attestation.
- CoLedger's release is independent of Revolva's legacy migration. Do not hold a
  green CoLedger candidate for an unrelated custody problem or bypass its gate
  to compensate for that delay.
- Revolva's synthetic-only target proposal can proceed without reading legacy
  contents. It cannot authorize transfer/deletion. Legacy retirement remains
  blocked on HOST-02 even if a new synthetic runtime is healthy.
- Closing an action as blocked is permitted; closing a feature as live without
  its production evidence is not.

## First next-session steps

1. Read this plan, then obtain the coordinator's **final** closeout. Refresh PR
   #104, #53/#51/#54, #188 and #68 plus remote main. Record changed heads and
   invalidate outdated validation pins. Do not rerun already completed provider
   demonstrations.
2. Inventory status/worktrees before switching branches. The planning session
   earlier observed concurrent dirty/staged AgentHub main edits. Latest coordinator
   closeout reports clean local root `5aa7c05`, ahead four owner commits; the first
   inspection found two. Refresh again and preserve all local-only owner work. Work in reviewed
   branches under `C:\wt\<repo>\<task>` only when isolation is needed.
3. Read current existing issue acceptance, especially SH-3714, SH-3716, SH-3524,
   SH-3515 and SH-3520. Treat missing owner evidence as UNKNOWN.
4. Check current policy, existing authorized target identity, capacity and spend
   allowance. No new Railway deployment, no paid fallback, no credential copying.
5. Assign independent product reviewers/validation lanes and one custody operator.
   Start with COL-01, EMP-01/02, REV-01 and AH-01/02; finish prerequisite evidence
   before any deployment command.

### Native gate details that must not be lost

**Revolva.** At merged guard source,
`node scripts/release.mjs <exact-sha> <daytona-evidence-directory> <postgres-run-id>`
verifies a clean exact checkout, source archive/lock/runner binding and exact
PostgreSQL workflow evidence. It does not deploy. Adding `--deploy` fails closed.
The full Daytona runner includes toolchain/dependencies, guard tests, lint,
typecheck, unit/build, migrations/drift, installed browser/version, e2e,
**rehearsal**, mobility build/tests and final clean status. A plain source archive
that cannot establish verified Git HEAD is insufficient.

**Scratch-path blocker discovered during planning:** the inspected Revolva
Daytona runner explicitly writes under `/tmp` via `mktemp`; the release verifier
uses OS temporary paths. CoLedger's verifier also creates an OS-temp snapshot.
Those scripts must **not** be run unchanged where the current no-temporary-path
constraint applies. In REV-02 / COL-02, first establish a repository-relative
scratch root through a supported process configuration, or make a narrowly
reviewed runner-path repair in the owning engineering lane if configuration
cannot control it. Do not weaken source binding, stage evidence or cleanup.
Any runner repair changes hashes/SHA and requires fresh exact-candidate evidence.
No runner has been edited or executed by this documentation task.

**CoLedger.** Use
`pwsh -File scripts\verify-release.ps1 -Commit <candidate-sha>` in the admitted
remote environment after the scratch constraint is resolved. Source requires
candidate containment of latest remote main, Node 24.20+ and pnpm 11.x including
lifecycle-runtime equality. All seven `COLEDGER_*_TEST_DATABASE_URL` variables
named by that script must identify schema-ready disposable loopback test DBs,
never production. Preserve required authorization/tenant/financial/citation/
OAuth/replay suites; no skip-based PASS.
Use `-MigrationsApplied` only after the selected migrations were reviewed and
applied in the isolated test gate, not as an acknowledgment shortcut. Production
application remains the reviewed PRE_DEPLOY responsibility. Main pushes can
deploy even documentation: do not land an unverified runtime or different merge
SHA. Reconcile provider auto-deploy settings before relying on the template.

**Empowera.** Inspect candidate `scripts/release/install.sh`,
`publish_dedicated.py`, `standalone_smoke.py`, `rollback.sh` and their fixture
tests. Use the immutable archive/systemd release path, not an opportunistic
prototype handler or another host. Migration `readiness_0008` is described by
PR #68; confirm the actual candidate chain and current deployed schema. Keep
feature flags disabled unless their distinct acceptance/activation gate passes.
A successful ASR check does not prove live webhook behavior, professional
qualification, manual screen-reader acceptance or secure host inventory access.

**AgentHub.** Validate registry and affected package contracts before sync;
run `scripts\Sync-AgentHub.ps1 -Audit -Validate`, authorized apply, then audit.
Do not regenerate provider output or initialize another host for a parity check.
Native host packaging and actual consumption are separate. RepoWise orientation
was unavailable as an exposed MCP/CLI in this planning lane; exact source was
read directly. No index refresh was attempted because it can entail provider
work. Resolve the bounded/manual refresh gate under next-session authority;
never use bare update, full private indexing or retired duplicate vendor hooks.

## Smallest accepted product slices

### Revolva: a reviewed fact, not an autonomous decision

One allowlisted synthetic recording or typed note → explicit consent →
timestamped original transcript → separately versioned correction → comparison
to current primary document/version/hash/anchor → authorized fact confirmation.
Dates/numbers/conflicts remain visible; source/transcript change makes approval
stale, while old packets remain immutable. A speaker label is unverified, not
identity. Cross-tenant audio access must deny without leaking bytes.

The frozen evaluation must include date ambiguity, correction, conflicting
primary evidence, partial/mismatched-model transcript and stale source negatives.
Submission-unknown recovery is not a second paid submission. Local cancellation
is not provider cancellation or reversal of charges. No voice rollout on the
static-only target and no new private-data migration are assumed.

### CoLedger: audio supports review, never ledger writes

One synthetic controller recording → explicit consent → durable transcription
and correction → **different-user** review → exact transcript and financial
comparison binding → current/stale outcome. Corrections or evidence refresh
invalidate acceptance; timeout/poll concurrency and independent draft review
must be verified after remediation. Tenant isolation, append-only history and
the database self-approval guard are release-critical.

Audio cannot change financial values. `narrativeInclusionAvailable:false`
remains intentional. Narrative inclusion/publication is a separate future
product decision, **not** an implementation item hidden in this release plan.
Retain broader synthetic CSV→close→board/export/revision acceptance where
SH-3515 requires it; no actual buyer results are inferred.

### Empowera: reviewed evidence, not certified competence

Voice: one synthetic response with separate transcription consent → immutable
timestamped original plus correction revisions → criterion-linked spans →
authorized assessor decision. Verify unresolved transcription cannot be accepted,
upload retry is available, polling is role-bound and correction history is not
disclosed to an unauthorized persona. Acknowledgement, accepted assessment and
work authorization remain different decisions.

Illustration: reuse an existing accepted Runware asset when available →
live inventory/readback → hash and current SOP/objective binding → qualified
independent SME inspection of the **exact bytes** → sequence/PPE/hazards/
accessibility checklist and authored alt/text equivalent → separate product
release. Changed source, candidate selection, attestation or file must stale/
reject the attachment. A generated still is illustrative, not safety evidence.
No enterprise identity or regulatory/commercial qualification is implied.

### AgentHub: producer contract and consumed installation

Keep `media-studio/runware-output-inventory/1` and
`jobs/runware/<id>/inventory.json` as the single producer contract. Consumers
import only current `approved[]`, re-hash files and enforce their own identity,
source and SME release gates. No copied asset or successful adapter test is a
released training illustration.

The adapter caps prepared/submit estimates at **$1 per job**, with one paid
`imageInference` request per job and recovery polling of the existing task.
This is an estimate-admission ceiling, not a guaranteed provider bill. Reported
output costs are not full billing reconciliation. Runware residency is not
established; inputs remain synthetic. Reuse accepted outputs/content hashes and
do not spend to check credentials, installation or coverage.

## Release, production verification and cleanup gates

For each eligible release, retain this minimum chain in restricted receipts:

1. Authority and accepted scope; exact current head plus independent review.
2. Candidate-specific native tests, migrations, negative/failure controls,
   archive/lock/toolchain evidence and unambiguous stage results.
3. Exact integrated/main source; if integration changes SHA, reverify it before
   any deploy-on-push event. Capture the prior active runtime and rollback basis.
4. Provider deployment/systemd source readback, exact components and schema,
   migration result, grants, default flags, preserved routes and dependencies.
5. Underlying deployed logs/traces/metrics/database observations in explicit
   pre/post windows. Compare observed failure/restart/resource signals and state
   their coverage; HTTP 200 alone is insufficient.
6. For **a release changed in that execution session**, an explicitly authorized
   bounded synthetic user workflow with private screenshots/result bindings.
   Do not run repository suites with production credentials. When asked whether
   an already shipped change works, use telemetry, not new live test traffic.
7. Human acceptance and remaining accessibility/privacy/customer-use gates
   recorded separately; existing tracker update and readback.

Cleanup is never the substitute for a release. Before deletion, enumerate the
entire **selected** cleanup space and record exact resources/paths, owner,
dependencies, retention requirements and retained source/restore evidence.
Prove the replacement, restore path and authorized disposition first. Preserve
unmerged/dirty/user-owned work, originals, immutable history and unknown-rights
data. Stop/delete only owned ephemeral workers by exact identity.

Railway product-service retirement does not mean account/integration retirement.
The coordinator's unrelated excluded-product cleanup receipt is outside this
product plan: a scheduled project deletion is **not** physical purge proof.
If administrative closure needs that receipt, verify it separately after its
scheduled deadline without creating excluded-product work or fetching contents.
Do not report all Railway resources gone while Revolva custody is retained.

## Pause, recovery and rollback

| Trigger | Immediate pause | Safe continuation / rollback gate |
| --- | --- | --- |
| New PR head, main movement or concurrent file owner | Stop integration/deploy; retain current work | Reconcile history/ownership, rerun changed-SHA gates; never reset another checkout |
| Missing acceptance or private-data rights | Keep flags off and resources retained | Obtain exact scoped authority/evidence; synthetic target can stay separate, no private inspection as a shortcut |
| Test failure, evidence mismatch, skipped required suite | No release | Correct root cause in owning lane; demonstrate failing control and exact-candidate pass |
| Provider timeout/unknown submission | No paid resubmission or fallback | Recover/poll the persisted task under existing quotas; reconcile unknown state and retained charge receipt |
| Credit/budget/capacity unknown or exhausted | No new paid job/resource | Reuse accepted outputs and approved capacity; report price basis/blocker, obtain required spend authority |
| Deploy/migration/health regression | Stop rollout/activation; preserve failed release evidence | Repository-native previous immutable release/deployment; verify schema compatibility, grants and packet hashes before pointer switch; no destructive down migration |
| Partial transfer, missing hash or uncertain preservation | No source retirement | Preserve both authorized copies, investigate metadata/hash discrepancy; verify full selected inventory and restore before retry/delete |
| Session ends before a gate passes | Record last safe rung, exact heads, active jobs and blocker | Keep only explicitly needed owned helpers; persist sanitized receipt and next action; no unattended scheduled continuation |

For CoLedger, a failed PRE_DEPLOY migration must leave the prior deployment
serving; verify that observation, not just the intended contract. For Empowera,
use the native rollback script only with reviewed schema/store compatibility,
preserving immutable evidence. For Revolva, the deploy guard remains the safe
state until a reviewed backend readiness contract exists. AgentHub rollback
restores only the changed managed package/configuration, not user commits or
retired vendor integrations.

## Expected changes and closeout contract

Only this plan is changed by preparation. Next-session engineering, if authorized,
belongs in the owning repository: release-runner path/setup repairs and exact
regressions; outstanding review fixes; candidate/release runbook corrections;
reviewed hosting readiness contracts; AgentHub routing/managed sync receipts.
Do not create another shared evidence kernel or provider wrapper. Media
production inputs/outputs remain in the private media workspace, never product
repositories. Raw custody, billing and telemetry evidence remains restricted.

Minimum evidence for an action marked Done: its ID, responsible owner, scope,
exact source/target, actual command or decision, observed result, negative/control
coverage where applicable, durable receipt and remaining risk. Feature release
Done additionally needs the reviewed→main→deployed→production-verified chain and
the issue's explicit human acceptance. A blocked rollout may have completed
implementation/review actions without a Done feature outcome.

At every pause/close, update progress below with action IDs, not a generic
“everything shipped” claim. Link the existing issue and PR, exact source, test
receipt, deployed revision (or “not deployed”), acceptance blocker and next gate.
Tracker updates require readback; this document does not claim the closing
coordinator already made them. Once all selected one-time actions are complete
or explicitly superseded, remove this active plan per `docs/plans/PLANS.md`.

## Progress and decision log

- Preparation only: current public pins checked; applicable AgentHub/product
  instructions and native release sources inspected; no app/cloud/provider
  execution performed by this planning lane.
- Decision: four lanes only; exclude Rexa product work, preserve unrelated cleanup
  receipt boundaries, and do not claim physical purge from scheduled deletion.
- Decision: preserve dirty/staged AgentHub main and all user-only commits. Prepare
  plan on a distinct branch/worktree, initially remote `b5258c91`, then rebase
  only the plan onto remote `a0717c6` after routing PR #104 merged; never local main.
- Discovery: PR #104 Intel macOS is successful. Coordinator reports Windows
  failures identical to baseline run
  [41943270486](https://github.com/shmindmaster/agenthub/actions/runs/41943270486):
  missing ElevenLabs Python (exit 9009) and Runware ACL test (actual 1 / expected
  0), 1,590 passes / two failures. Relevant implementation/workflow unchanged.
  [Baseline exception evidence](https://github.com/shmindmaster/agenthub/pull/104#issuecomment-6648030033)
  supports the coordinator's completed small docs-only merge after router-link
  correction, targeted 18-pass validator and review; it does not repair those
  baseline failures or authorize unrelated fixes.
- Final routing closeout: PR #104 merged at
  `a0717c6fd6699afb8c2520d5beaf70153a2d243a`; `04260f9` fixed/resolved the
  router review and the final docs-only relative link was checked. Prior
  candidate suite/Doctor evidence is distinct from that final delta.
- Managed Runware readback: coordinator checked Copilot
  `ah-media-studio@agenthub` 2.1.3 ENABLED from the local canonical source, and
  Claude 2.1.3 ENABLED with `runware-image.mjs` present. Two on-disk surfaces
  established; canonical byte/hash comparison pending. Other surfaces remain
  UNKNOWN/not checked, and fresh-session consumption remains unproven.
- Latest local-root closeout: `5aa7c05` clean, ahead four owner commits.
  Preserve that work; this plan branch contains none of those local-only commits.
- Discovery: complete Revolva rehearsal needs verified Git checkout and bound
  evidence; native temporary-path usage also requires a next-session repair/
  supported configuration before constrained gate execution.
- CoLedger closeout input received: exact `1ecff71` archive verification,
  security 14/14 and release eval 8/8 passed; ten review threads resolved.
  Browser dependency repair/full browser and PG capsule CI results remain
  pending from the same lane. No merge/deployment inferred.
- Pending closeout input: final CoLedger browser/PG results. PR #104's corrected
  head/merge receipt is now reported; refresh remote main on entry.
- No next-session action has been executed by preparing this plan.
