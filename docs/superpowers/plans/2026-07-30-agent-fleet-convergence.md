# Agent Fleet Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Converge the live coding-agent fleet onto explicit AgentHub ownership, remove verified duplication, preserve and relocate unique work, correct local runtime drift, and produce a fresh evidence-backed final status.

**Architecture:** AgentHub registry files declare canonical, vendor-owned, and evidence-pending skill ownership. Existing deployers distribute repository-owned skills; a narrow external-skill reconciler hash-pins vendor-owned local trees without importing third-party source into AgentHub. Worktree migrations preserve Git identity and WIP below `C:\wt`, while the live drift scanner remains the final arbiter and fails closed on unsupported or unresolved behavior.

**Tech Stack:** PowerShell 5.1/7, Pester 6, JSON, Markdown Agent Skills, Git worktrees and bundles, Windows process/CIM inspection, native host plugin managers, Node.js package validators.

## Global Constraints

- The approved design is `docs/superpowers/specs/2026-07-30-agent-fleet-convergence-design.md`.
- AgentHub is the control plane. Do not use a client repository, tracker, identity, dataset, deployment, or communication system as a capability fixture.
- Preserve credentials, OAuth state, cookies, private evidence, customer data, and regulated data outside AgentHub and outside reports.
- Cursor and Cursor Agent remain retained-disabled. Do not invoke, probe, or route work to either surface.
- Only unique, reusable, high-value behavior becomes canonical. Do not promote a skill merely because several homes contain it.
- Byte-equivalent or verified superseded active copies move to managed quarantine before removal from discovery roots.
- Dirty, untracked, unpushed, unreachable, or uniquely committed work is protected. Migration is permitted; deletion is not.
- `C:\wt\RepositoryName\TaskSlug` is the only permitted user-created worktree
  layout.
- Do not add or run a GitHub Actions workflow. `validate.yml` remains the sole self-hosted validation definition, but it is not dispatched by this work.
- Do not create a pull request. After review, fast-forward the verified commits into `main` and push `main`.
- Implementation tasks run sequentially. Parallel agents may perform read-only investigation or independent review only.
- Every code behavior change follows red-green-refactor. Tests must exercise behavior, not grep source text.
- `C:\tmp` remains a release blocker unless a supported Codex Desktop control is verified. Do not add a junction, ACL workaround, undocumented setting, or scanner exclusion.
- The preserved-pending `issue-to-pr` and legal/knowledge skills remain blocked until their provider, authorization, provenance, and synthetic-fixture contracts exist. Do not silently convert them into passes.

---

### Task 1: Create the isolated execution workspace and restore the workflow invariant

**Files:**
- Delete: `.github/workflows/copilot-setup-steps.yml`
- Test: `tests/NoHostedCi.Tests.ps1`
- Test: `tests/RuntimeCentralization.Tests.ps1`

**Interfaces:**
- Consumes: approved worktree root `C:\wt`, current `main`, existing local-only workflow assertions.
- Produces: isolated branch `worktree-fleet-convergence` at `C:\wt\agenthub\fleet-convergence`, with `validate.yml` as the sole workflow definition.

- [ ] **Step 1: Verify the current checkout and create the approved worktree**

Run:

```powershell
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  "C:\Users\SaroshHussain\AppData\Local\AgentHub\bin\New-AgentHubWorktree.ps1" `
  -Cwd "C:\Repos\shmindmaster\agenthub" -Name "fleet-convergence"
```

Expected: a new registered worktree at `C:\wt\agenthub\fleet-convergence`, based on the approved-plan commit, with no nested or alternative worktree root.

- [ ] **Step 2: Run the existing workflow policy test and verify the red state**

Run from the new worktree:

```powershell
Invoke-Pester -Path .\tests\NoHostedCi.Tests.ps1 -Output Detailed
```

Expected: FAIL because two YAML workflow definitions exist and the test requires exactly one named `validate.yml`.

- [ ] **Step 3: Remove only the redundant workflow**

Delete `.github/workflows/copilot-setup-steps.yml` with `apply_patch`. Do not change `validate.yml`, `validate-repository.ps1`, runner labels, or workflow permissions.

- [ ] **Step 4: Verify the workflow invariant locally**

Run:

```powershell
Invoke-Pester -Path .\tests\NoHostedCi.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\RuntimeCentralization.Tests.ps1 -Output Detailed
```

Expected: both suites pass; no workflow is dispatched.

- [ ] **Step 5: Commit**

```powershell
git add -- .github/workflows/copilot-setup-steps.yml
git diff --cached --check
git commit -m "chore(agenthub): restore single-workflow policy"
```

---

### Task 2: Extract one reusable managed-quarantine primitive

**Files:**
- Create: `scripts/ManagedQuarantine.ps1`
- Modify: `scripts/Apply-FullAccessAgentProfile.ps1`
- Create: `tests/ManagedQuarantine.Tests.ps1`
- Test: `tests/Apply-FullAccessAgentProfile.Tests.ps1`

**Interfaces:**
- Consumes: a safe user-profile root and an exact source artifact path.
- Produces:
  - `New-AgentHubQuarantineBatch([string] $UserProfilePath) -> PSCustomObject`
  - `Move-ToAgentHubQuarantine([object] $Batch, [string] $Path, [string] $HostId, [string] $ArtifactKind, [string] $ArtifactName, [string] $Reason, [string] $ContentHash) -> string`
  - `Write-AgentHubQuarantineManifest([object] $Batch) -> string`

- [ ] **Step 1: Write failing behavioral tests**

Create `tests/ManagedQuarantine.Tests.ps1` with a real `$TestDrive` tree. The tests must verify:

```powershell
It 'moves only the exact artifact and records a recoverable manifest' {
    $source = Join-Path $TestDrive 'profile\.host\skills\fixture'
    # Create SKILL.md plus one reference file.
    # Invoke the public functions.
    # Assert source absent, quarantine copy present, and manifest fields exact.
}

It 'refuses a source outside the approved user profile' {
    # Invoke against a sibling path and assert it throws before moving anything.
}

It 'does not overwrite an existing quarantine destination' {
    # Pre-create the destination and assert fail-closed behavior.
}
```

The manifest assertion must cover `sourcePath`, `quarantinePath`, `hostId`, `artifactKind`, `artifactName`, `reason`, `contentHash`, and UTC timestamp.

- [ ] **Step 2: Run the tests and verify the red state**

```powershell
Invoke-Pester -Path .\tests\ManagedQuarantine.Tests.ps1 -Output Detailed
```

Expected: FAIL because the reusable functions do not exist.

- [ ] **Step 3: Implement the reusable primitive**

Move the existing batch-ID, entry collection, safe move, and manifest behavior from `Apply-FullAccessAgentProfile.ps1` into `ManagedQuarantine.ps1`. Keep path validation through `PathSafety.ps1`. Reject an empty reason, unsafe source, duplicate destination, or malformed 64-character hash.

- [ ] **Step 4: Rewire the profile deployer without changing behavior**

Dot-source `ManagedQuarantine.ps1`, create one batch, replace calls to the old local move helper with `Move-ToAgentHubQuarantine`, and write the manifest once after all profile operations. Do not alter which artifacts currently qualify for quarantine.

- [ ] **Step 5: Verify focused and regression suites**

```powershell
Invoke-Pester -Path .\tests\ManagedQuarantine.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\PathSafety.Tests.ps1 -Output Detailed
```

Expected: all pass.

- [ ] **Step 6: Commit**

```powershell
git add -- scripts/ManagedQuarantine.ps1 scripts/Apply-FullAccessAgentProfile.ps1 `
  tests/ManagedQuarantine.Tests.ps1 tests/Apply-FullAccessAgentProfile.Tests.ps1
git diff --cached --check
git commit -m "refactor(agenthub): centralize managed quarantine"
```

---

### Task 3: Canonicalize the portfolio engineering skills

**Files:**
- Create: `capabilities/portfolio-engineering-ops/skills/docs-drift/SKILL.md`
- Create: `capabilities/portfolio-engineering-ops/skills/portfolio-audit/SKILL.md`
- Create: `capabilities/portfolio-engineering-ops/skills/release-readiness/SKILL.md`
- Create: `capabilities/portfolio-engineering-ops/skills/repo-onboard/SKILL.md`
- Create: `capabilities/portfolio-engineering-ops/skills/verify-and-commit/SKILL.md`
- Modify: `registry/capabilities.json`
- Modify: `tests/Apply-FullAccessAgentProfile.Tests.ps1`
- Modify: `tests/LiveAgentFleetDrift.Tests.ps1`
- Modify: `docs/fleet-capability-contracts.md`

**Interfaces:**
- Consumes: the `.agents` and `.claude` variants identified in the approved evidence review.
- Produces: capability `portfolio-engineering-ops`, owner `portfolio`, type `skills`, with five host-neutral canonical skills.

- [ ] **Step 1: Add failing distribution and drift fixtures**

Extend the synthetic capability registry in `tests/Apply-FullAccessAgentProfile.Tests.ps1` with a five-skill capability mapped to `claude`, `codex`, and `cline`. Assert:

```powershell
(Invoke-DistributionOnly -Fixture $fixture) | Should -Be 0
foreach ($hostRoot in $mappedRoots) {
    foreach ($skillId in $portfolioSkillIds) {
        Test-Path (Join-Path $hostRoot "$skillId\SKILL.md") | Should -BeTrue
    }
}
```

Extend `tests/LiveAgentFleetDrift.Tests.ps1` so two mapped copies with the canonical hash produce no `unowned-*` finding, while a divergent mapped copy produces `canonical-skill-content-drift`.

- [ ] **Step 2: Run the focused tests and verify they fail for missing ownership**

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
```

- [ ] **Step 3: Create the five canonical skills**

Use the complete current `.agents` bodies as the behavior source, but normalize these exact host-specific phrases:

- Replace `README/AGENTS.md/AGENTS.md/docs` and `README/AGENTS.md/CLAUDE.md/docs` with `README, applicable repository instructions, and docs`.
- Replace references to a specific agent home or agent-name configuration with `the executing host's managed configuration`.
- Make `portfolio-audit` derive repository inventory from AgentHub registries instead of a hard-coded portfolio list.
- Preserve `release-readiness` prohibitions on deployment, migration, and credential rotation.
- Preserve selective staging and opt-in push in `verify-and-commit`; never introduce blind `git add -A`.
- Use synthetic fixtures in examples and tests.

- [ ] **Step 4: Register exact ownership**

Add `portfolio-engineering-ops` to `registry/capabilities.json` with:

Construct the entry from the following exact PowerShell object so
`contentHash` is the literal produced by the repository hash helper rather
than a hand-written value:

```powershell
$hashBasis = 'C:\Repos\shmindmaster\agenthub\capabilities\portfolio-engineering-ops'
$contentHash = Get-AgentHubRegistryHashBasisValue -HashBasis $hashBasis
$portfolioCapability = [ordered]@{
  id = 'portfolio-engineering-ops'
  owner = 'portfolio'
  capabilityType = 'skills'
  canonicalSource = 'C:/Repos/shmindmaster/agenthub/capabilities/portfolio-engineering-ops'
  managedSkillNames = @(
    'docs-drift',
    'portfolio-audit',
    'release-readiness',
    'repo-onboard',
    'verify-and-commit'
  )
  contentHash = $contentHash
  hashBasis = $hashBasis
  status = 'active-canonical'
}
```

Use `managed-loose-skills` mappings for exactly these registered loose-skill targets:

`amp`, `antigravity`, `claude`, `cline`, `codex`, `copilot`, `cursor`, `devin`, `factory`, `gemini`, `grok`, `hermes`, `opencode`, `qoder`, `qwen-code`, `warp`, and `windsurf`.

Compute the full-tree hash with `Get-AgentHubRegistryHashBasisValue`; insert the returned literal before committing.

- [ ] **Step 5: Document the owner and run validation**

Add one `portfolio-engineering-ops` row to `docs/fleet-capability-contracts.md`. Run:

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1
```

- [ ] **Step 6: Commit**

```powershell
git add -- capabilities/portfolio-engineering-ops registry/capabilities.json `
  tests/Apply-FullAccessAgentProfile.Tests.ps1 tests/LiveAgentFleetDrift.Tests.ps1 `
  docs/fleet-capability-contracts.md
git diff --cached --check
git commit -m "feat(agenthub): own portfolio engineering skills"
```

---

### Task 4: Canonicalize Framer and its code-component companion

**Files:**
- Create: `capabilities/framer/skills/framer/SKILL.md`
- Create: `capabilities/framer/skills/framer/start-conversation.md`
- Create: `capabilities/framer/skills/framer/projects/__template__/index.template.md`
- Create: `capabilities/framer/skills/framer/projects/__template__/project-inventory.template.md`
- Create: `capabilities/framer/skills/framer/projects/__template__/recipes.md`
- Create: `capabilities/framer/skills/framer-code-components/SKILL.md`
- Modify: `registry/capabilities.json`
- Modify: `tests/Apply-FullAccessAgentProfile.Tests.ps1`
- Modify: `tests/LiveAgentFleetDrift.Tests.ps1`
- Modify: `docs/fleet-capability-contracts.md`

**Interfaces:**
- Consumes: the complete five-file `framer` tree and the byte-equivalent 2,526-line `framer-code-components` companion.
- Produces: one atomic `framer` capability whose two skill IDs deploy together.

- [ ] **Step 1: Add a failing exact-tree distribution test**

Create a fixture containing both skill directories and all four `framer` companion files. Seed a stale target missing `recipes.md`. Assert the profile replaces the full target tree and that `framer-code-components` remains a separate skill ID.

- [ ] **Step 2: Verify the red state**

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
```

- [ ] **Step 3: Create the canonical trees**

Preserve every instruction and template from the `.agents` version. Replace the two source-root-specific allowed-tool entries:

```yaml
- 'Read(C:\Users\SaroshHussain\.agents\skills\framer/projects/**)'
- 'Read(C:\Users\SaroshHussain\.agents\skills\framer/start-conversation.md)'
```

with host-neutral relative-resource instructions in the body:

```markdown
Read `projects/SafeProjectId/index.md` and `start-conversation.md` from this
skill's installed directory through the host's normal skill-resource loader.
```

Keep the Framer temp-area and `npx @framer/agent` permissions. Do not add an AgentHub-local MCP server.

- [ ] **Step 4: Register and validate ownership**

Add capability `framer`, owner `portfolio`, type `skills`, managed names `framer` and `framer-code-components`, full-tree hash basis, and the same 17 loose-skill host mappings listed in Task 3.

Add a drift fixture that proves both IDs resolve to the same capability owner and a missing companion file causes canonical content drift.

- [ ] **Step 5: Run focused and registry validation**

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1
```

- [ ] **Step 6: Commit**

```powershell
git add -- capabilities/framer registry/capabilities.json `
  tests/Apply-FullAccessAgentProfile.Tests.ps1 tests/LiveAgentFleetDrift.Tests.ps1 `
  docs/fleet-capability-contracts.md
git diff --cached --check
git commit -m "feat(agenthub): canonicalize framer skills"
```

---

### Task 5: Merge UI verification into Browser Toolkit and retire the duplicate ID

**Files:**
- Modify: `capabilities/browser-toolkit/skills/browser-debugging/SKILL.md`
- Modify: `registry/capabilities.json`
- Modify: `tests/Apply-FullAccessAgentProfile.Tests.ps1`
- Modify: `tests/LiveAgentFleetDrift.Tests.ps1`

**Interfaces:**
- Consumes: existing Browser Toolkit ownership and exact legacy `ui-verify` hash `19E15F4745FD39172A67534369B12469897014EE84B45EC2A5998C5EBEE6AD9C`.
- Produces: one browser-debugging owner with the useful UI completion gate, plus a signed retirement contract for `ui-verify`.

- [ ] **Step 1: Add failing merge and retirement tests**

The fixture must deploy Browser Toolkit, seed an exact one-file `ui-verify` copy, and assert:

```powershell
Test-Path $legacyUiVerifyPath | Should -BeFalse
$manifest.entries.artifactName | Should -Contain 'ui-verify'
$deployedBrowserDebugging | Should -Match 'Never claim a UI change works'
```

The assertion must read the deployed artifact and quarantine manifest, not the production script source.

- [ ] **Step 2: Verify the red state**

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
```

- [ ] **Step 3: Merge the distinct behavior**

Add a `UI change completion gate` to `browser-debugging` that requires:

- Repository-native startup instructions; never guess the port.
- Rendering the changed flow, checking console and network before and after.
- Exercising the golden path and one relevant edge case.
- Running the repository's focused Playwright configuration when present.
- Capturing a screenshot and reporting an explicit environment blocker when rendering is unavailable.

Do not duplicate the browser-evidence ownership or Product Demo Studio decisions.

- [ ] **Step 4: Add the exact retirement signature**

Append this contract to Browser Toolkit:

```json
{
  "name": "ui-verify",
  "contentHash": "19E15F4745FD39172A67534369B12469897014EE84B45EC2A5998C5EBEE6AD9C",
  "reason": "Merged into browser-debugging; exact loose copies are superseded."
}
```

Recompute Browser Toolkit's full-tree `contentHash`.

- [ ] **Step 5: Run tests and commit**

```powershell
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1
git add -- capabilities/browser-toolkit registry/capabilities.json `
  tests/Apply-FullAccessAgentProfile.Tests.ps1 tests/LiveAgentFleetDrift.Tests.ps1
git diff --cached --check
git commit -m "feat(agenthub): merge ui verification ownership"
```

---

### Task 6: Record external and evidence-pending skill ownership

**Files:**
- Create: `registry/skill-ownership.json`
- Create: `scripts/Sync-ExternalSkills.ps1`
- Create: `tests/ExternalSkillOwnership.Tests.ps1`
- Modify: `scripts/Test-LiveAgentFleetDrift.ps1`
- Modify: `tests/LiveAgentFleetDrift.Tests.ps1`
- Modify: `tests/Validate-AgentEcosystem.ps1`
- Modify: `tests/AdvertisedValidationCommands.Tests.ps1`
- Modify: `docs/fleet-capability-contracts.md`

**Interfaces:**
- Consumes: verified Railway v1.3.6 source tree and exact pending-skill hashes.
- Produces:
  - external owner contract for `use-railway`;
  - evidence-pending contracts for `issue-to-pr` and 18 legal/knowledge skills;
  - `Sync-ExternalSkills.ps1 -RegistryRoot -UserProfilePath -AppDataPath [-Apply]`;
  - live drift that distinguishes external ownership, preserved blockers, and true unowned copies.

- [ ] **Step 1: Add failing registry and reconciler tests**

Create real synthetic trees in `$TestDrive`:

```powershell
It 'reports an outdated external skill without mutating in report mode' {
    # Source matches currentHash; target matches previousHash.
    # Assert report state outdated and target unchanged.
}

It 'replaces outdated targets and retires a shared shadow only after all targets verify' {
    # Run -Apply, assert exact tree parity, quarantine manifests, and shared shadow absence.
}

It 'fails closed when no source candidate matches the trusted hash' {
    # Assert no target or shared shadow moves.
}
```

Extend live-drift fixtures so:

- one current Railway copy per mapped host is owned and current;
- two discovery roots for Railway within the same host still fail;
- old Railway hash fails;
- exact evidence-pending copies remain explicit WARN findings;
- divergent `issue-to-pr` remains FAIL with `preserve-pending-evidence` in the detail.

- [ ] **Step 2: Verify the red state**

```powershell
Invoke-Pester -Path .\tests\ExternalSkillOwnership.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
```

- [ ] **Step 3: Create the ownership registry**

Use schema version 1 with:

```json
{
  "schemaVersion": 1,
  "externalOwners": [
    {
      "skillId": "use-railway",
      "owner": "railway",
      "ownershipType": "vendor-installed-local-skill",
      "currentVersion": "1.3.6",
      "skillHash": "0D70B4DAF9D8657EF2432EEAE88E9E2A46F433E7A4C668F26A3A4052815337A3",
      "treeHash": "9555D7FCAAF0D7326D48AA823577783BDE907E945B3E738C0B1379B995E23184",
      "previousTreeHashes": [
        "F2228477490AED1A5EE5E9F466512F330A48D7ED580A54B1BDED70E326484A15"
      ],
      "sourceCandidates": [
        "${USERPROFILE}/.claude/skills/use-railway",
        "${USERPROFILE}/.codex/skills/use-railway"
      ],
      "sharedShadowPaths": [
        "${USERPROFILE}/.agents/skills/use-railway"
      ]
    }
  ]
}
```

Add exact targets for `claude`, `cline`, `codex`, `copilot`, `cursor`, `devin`, `factory`, `gemini`, `antigravity`, `grok`, `opencode`, and `windsurf`, using `${USERPROFILE}` or `${APPDATA}` templates and each host's registered native skill root.

Add `preservePendingEvidence` entries for:

`issue-to-pr`, `analyze-legal-contradictions`, `ask-local-knowledge`, `build-evidence-packet`, `build-legal-timeline`, `check-knowledge-health`, `code-legal-issues`, `export-knowledge-results`, `ingest-legal-evidence`, `operate-qdrant-index`, `promote-reusable-knowledge`, `refresh-knowledge-corpus`, `research-external-courts`, `research-legal-authority`, `review-knowledge-duplicates`, `review-legal-communications`, `search-legal-evidence`, `search-local-knowledge`, and `verify-legal-citations`.

Each entry must contain the exact observed hash or hashes, current paths, missing owner/connector/auth evidence, personal-data boundary, and `status: "preserve-pending-evidence"`. These contracts classify but do not suppress FAIL/WARN results.

- [ ] **Step 4: Implement safe external reconciliation**

`Sync-ExternalSkills.ps1` must:

1. Expand only `${USERPROFILE}` and `${APPDATA}`.
2. Verify one source candidate exactly matches the trusted full-tree hash.
3. Report every target as current, missing, outdated-known, or divergent-unknown.
4. Refuse `-Apply` when any target is divergent-unknown.
5. Stage a complete tree, quarantine an outdated-known target, and atomically move the staged tree into place.
6. Verify every target before quarantining a shared shadow.
7. Write one managed quarantine manifest.
8. Never download, install, launch Railway, or invoke Cursor.

- [ ] **Step 5: Validate registry semantics**

Update `Validate-AgentEcosystem.ps1` to reject unknown hosts, duplicate skill IDs, malformed hashes, unapproved placeholders, an external target outside a registered skill root, or a pending record with no blocker reason.

- [ ] **Step 6: Run focused validation and commit**

```powershell
Invoke-Pester -Path .\tests\ExternalSkillOwnership.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1
git add -- registry/skill-ownership.json scripts/Sync-ExternalSkills.ps1 `
  scripts/Test-LiveAgentFleetDrift.ps1 tests/ExternalSkillOwnership.Tests.ps1 `
  tests/LiveAgentFleetDrift.Tests.ps1 tests/Validate-AgentEcosystem.ps1 `
  tests/AdvertisedValidationCommands.Tests.ps1 docs/fleet-capability-contracts.md
git diff --cached --check
git commit -m "feat(agenthub): govern external skill ownership"
```

---

### Task 7: Correct Grok's unsupported local MCP plugin and classify runtime trees

**Files:**
- Modify: `scripts/Test-LiveAgentFleetDrift.ps1`
- Modify: `tests/LiveAgentFleetDrift.Tests.ps1`
- Create: `docs/codex-node-repl-root-temp-blocker-2026-07-30.md`
- Modify: `docs/runtime-centralization-cleanup-2026-07-29.md`

**Interfaces:**
- Consumes: process ancestry, native connector registry, Grok enabled-plugin state, Codex host-owned runtime evidence.
- Produces: one logical local-MCP tree per top-level owner, a failure for unsupported enabled local plugins, and a documented Codex platform blocker.

- [ ] **Step 1: Add failing process-tree fixtures**

Use synthetic process objects:

```powershell
$processes = @(
    @{ ProcessId=100; ParentProcessId=50; CommandLine='npx chrome-devtools-mcp@1.6.0' },
    @{ ProcessId=101; ParentProcessId=100; CommandLine='chrome-devtools-mcp.js' },
    @{ ProcessId=102; ParentProcessId=101; CommandLine='telemetry watchdog --parent-pid=101' }
)
```

Assert the scanner emits one logical runtime tree, identifies the owning host, and does not report three servers. Add a fixture where Grok enables `chrome-devtools-mcp` even though Grok is absent from that native connector's supported-host contract; assert FAIL.

- [ ] **Step 2: Verify the red state**

```powershell
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
```

- [ ] **Step 3: Implement ownership-aware grouping**

Build parent/child relationships from `ProcessId` and `ParentProcessId`, choose the highest matching MCP ancestor as the logical root, record descendants, and correlate its first non-launcher ancestor to a registered agent executable. Exclude the observer command itself. Hosted HTTP MCP client sessions remain outside local-process counts.

- [ ] **Step 4: Detect unsupported enabled plugin ownership**

Read supported host mappings from `registry/native-connectors.json` and compare them with enabled host plugin state. An enabled local plugin on an unmapped host is FAIL even if its process is idle.

- [ ] **Step 5: Disable Grok's unsupported plugin through its supported manager**

Before mutation, confirm the exact entry and command:

```powershell
grok plugin disable --help
Select-String -LiteralPath "$env:USERPROFILE\.grok\config.toml" `
  -Pattern 'chrome-devtools-mcp'
grok plugin disable chrome-devtools-mcp
```

Do not run a Grok agent prompt. Re-read the enabled-plugin list. If the already-running MCP descendants remain, verify every descendant belongs to the exact Grok `chrome-devtools-mcp` tree, stop only that traced descendant set from leaves to root, and observe for 20 seconds. Do not terminate the Grok parent or unrelated Node processes.

- [ ] **Step 6: Document the Codex platform blocker**

Record:

- Codex Desktop and `node_repl` versions/paths.
- Masked presence/equality of `TEMP`, `TMP`, and `TMPDIR`.
- `node_repl → codex app-server → ChatGPT → explorer` ancestry.
- `C:\tmp\sessions` creation timeline.
- Embedded runtime statement that the sandbox sets temp variables to its writable workspace root.
- Supported CLI surface: `--disable-sandbox` only, with no temp-directory option.
- Prohibited workarounds and the evidence required for a vendor fix.

Do not change Codex's host-owned MCP entry or weaken the live scanner.

- [ ] **Step 7: Verify and commit**

```powershell
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-LiveAgentFleetDrift.ps1 `
  -SkipRepositoryScan -Json
git add -- scripts/Test-LiveAgentFleetDrift.ps1 tests/LiveAgentFleetDrift.Tests.ps1 `
  docs/codex-node-repl-root-temp-blocker-2026-07-30.md `
  docs/runtime-centralization-cleanup-2026-07-29.md
git diff --cached --check
git commit -m "fix(agenthub): classify local runtime ownership"
```

Expected live result: Grok's unsupported plugin finding is gone. `C:\tmp` remains FAIL until Codex provides a supported remediation.

---

### Task 8: Deploy canonical and external skills to the live fleet

**Files:**
- No new source files unless a focused test exposes a deployer defect.
- Runtime evidence: `%LOCALAPPDATA%\AgentHub\sync\drift-reports\`
- Runtime evidence: `%USERPROFILE%\.agenthub\quarantine\`

**Interfaces:**
- Consumes: Tasks 2–7 contracts and scripts.
- Produces: current canonical skills at every mapped root, Railway v1.3.6 at every mapped external target, no shared managed shadow, and recoverable quarantine manifests.

- [ ] **Step 1: Run report-only external reconciliation**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-ExternalSkills.ps1
```

Expected: known Railway v1.3.5 targets report `outdated-known`; Cline and Gemini native targets report `missing`; shared `.agents` copy reports `shared-shadow`; no unknown divergence.

- [ ] **Step 2: Apply the AgentHub profile**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\scripts\Apply-FullAccessAgentProfile.ps1 -RetireLegacyVideoOwners
```

Expected: portfolio and Framer capabilities deploy exactly to mapped hosts; exact superseded loose copies and `ui-verify` move to quarantine; Cursor is not launched.

- [ ] **Step 3: Apply external Railway reconciliation**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\scripts\Sync-ExternalSkills.ps1 -Apply
```

Expected: all mapped targets match Railway v1.3.6 tree hash; the shared `.agents` shadow moves to quarantine only after verification.

- [ ] **Step 4: Prove idempotence**

Run both commands again in report mode. Expected: no additional quarantine manifest, no changed target, and every managed/external target current.

- [ ] **Step 5: Run live profile validation**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-FullAccessAgentProfile.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-LiveAgentFleetDrift.ps1 `
  -SkipRepositoryScan -Json
node .\packages\handoff-plugins\plugins\product-demo-studio\scripts\validate-host-parity.mjs
```

Record the report and quarantine manifest paths in the task report. No commit is required unless a tested source correction was necessary.

---

### Task 9: Migrate the three registered ABACare worktrees intact

**Files:**
- Create: `docs/fleet-convergence-worktree-migration-2026-07-30.md`
- Runtime evidence: `%LOCALAPPDATA%\AgentHub\reports\worktree-migrations\`

**Interfaces:**
- Consumes: three registered dirty ABACare worktrees.
- Produces:
  - `C:\wt\abacare\sh2317-ci-boundary`
  - `C:\wt\abacare\sh2317-final`
  - `C:\wt\abacare\sh2317-review-findings`

- [ ] **Step 1: Capture immutable pre-move evidence**

Use this exact mapping and record every command result:

```powershell
$registeredWorktrees = @(
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707'
    Destination = 'C:\wt\abacare\sh2317-ci-boundary'
    ExpectedHead = 'e7c177091e20a2d32285f8ac942cf706e7c797b2'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707-final'
    Destination = 'C:\wt\abacare\sh2317-final'
    ExpectedHead = '998128b19827b18a20295b90b61e4c32b4a62dfb'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707-review-fixes'
    Destination = 'C:\wt\abacare\sh2317-review-findings'
    ExpectedHead = '20bbf2192251e7ccf363d5e029b5ce2e4706669e'
  }
)
foreach ($worktree in $registeredWorktrees) {
  git -C $worktree.Source status --porcelain=v2 --branch
  git -C $worktree.Source rev-parse HEAD 'HEAD^{tree}'
  git -C $worktree.Source ls-files --others --exclude-standard
  git -C $worktree.Source stash list
  git -C C:\Repos\shmindmaster\abacare for-each-ref --contains $worktree.ExpectedHead
  Test-Path -LiteralPath $worktree.Destination
}
```

Expected identities:

- `abacare-pr707`: `e7c177091e20a2d32285f8ac942cf706e7c797b2`
- `abacare-pr707-final`: `998128b19827b18a20295b90b61e4c32b4a62dfb`
- `abacare-pr707-review-fixes`: `20bbf2192251e7ccf363d5e029b5ce2e4706669e`

Stop if any HEAD differs, a destination exists, or new untracked content appears without being recorded.

- [ ] **Step 2: Move through the owning repository**

Create only the approved parent and run serially:

```powershell
New-Item -ItemType Directory -Path C:\wt\abacare -Force
git -C C:\Repos\shmindmaster\abacare worktree move `
  "C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707" `
  "C:\wt\abacare\sh2317-ci-boundary"
git -C C:\Repos\shmindmaster\abacare worktree move `
  "C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707-final" `
  "C:\wt\abacare\sh2317-final"
git -C C:\Repos\shmindmaster\abacare worktree move `
  "C:\Users\SaroshHussain\Documents\Codex\2026-07-27\review-recent-email-and-calendar-activity\abacare-pr707-review-fixes" `
  "C:\wt\abacare\sh2317-review-findings"
```

Do not use `--force`, raw deletion, prune, checkout, reset, clean, or branch deletion.

- [ ] **Step 3: Verify exact post-move parity**

For each destination, assert HEAD, tree, status lines, dirty-file set, and stash visibility equal the recorded source. Verify:

```powershell
git -C C:\Repos\shmindmaster\abacare worktree list --porcelain
```

The three old paths must be absent and the three `C:\wt` paths registered.

- [ ] **Step 4: Record and commit evidence**

Document old/new paths, HEAD/tree, dirty-file counts, command exit codes, and confirmation that no source was deleted manually.

```powershell
git add -- docs/fleet-convergence-worktree-migration-2026-07-30.md
git diff --cached --check
git commit -m "docs(agenthub): record registered worktree migration"
```

---

### Task 10: Preserve and migrate the five Grok standalone repositories

**Files:**
- Modify: `docs/fleet-convergence-worktree-migration-2026-07-30.md`
- Runtime evidence: `%LOCALAPPDATA%\AgentHub\quarantine\worktrees\20260730\`

**Interfaces:**
- Consumes: five standalone Git repositories below `%USERPROFILE%\.grok\worktrees`.
- Produces four preserved repositories below `C:\wt` and one verified Shwiki quarantine.

- [ ] **Step 1: Revalidate and bundle every standalone repository**

Use the following exact inventory. For each source, capture status, HEAD/tree,
untracked files, refs containing HEAD, remote URL, and stashes. Create and
verify the named bundle:

```powershell
$quarantineRoot = 'C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730'
$standaloneRepositories = @(
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-abacare\subagent-019f905a-b8ce-7cf2-927e-2473e54cf405'
    ExpectedHead = '5b22ed5ef82b6151b045c119a2e2469c7bd4dd93'
    Bundle = Join-Path $quarantineRoot 'abacare-sh2237-rbt-phone-fidelity.bundle'
    Destination = 'C:\wt\abacare\sh2237-rbt-phone-fidelity'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-abacare\subagent-019f905a-b8cf-7ad1-82f0-da93b31c1641'
    ExpectedHead = 'd5e6095f995360e1bcd6151152d1a7b1ccd2844b'
    Bundle = Join-Path $quarantineRoot 'abacare-sh2201-agentic-ux-slice.bundle'
    Destination = 'C:\wt\abacare\sh2201-agentic-ux-slice'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-shwiki\local'
    ExpectedHead = '5d05de8362448bdfafee4b72cb8aa09f90918b70'
    Bundle = Join-Path $quarantineRoot 'shwiki-local.bundle'
    Destination = 'C:\wt\shwiki\local-preserved'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-subops\subagent-019f9ac8-b626-7e43-a358-d768211f01e6'
    ExpectedHead = 'ecf208fdf092087314a0e164829b33e3ae029556'
    Bundle = Join-Path $quarantineRoot 'subops-fleet-pass-a-strip-e26.bundle'
    Destination = 'C:\wt\subops\fleet-pass-a-strip-e26'
  },
  [pscustomobject]@{
    Source = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-subops\subagent-019f9ac8-b627-7ed0-9021-4d7f08f3fc45'
    ExpectedHead = 'c142500262b4f370f30814224d5bba822038de65'
    Bundle = Join-Path $quarantineRoot 'subops-sh1093-correction-history.bundle'
    Destination = 'C:\wt\subops\sh1093-correction-history'
  }
)
New-Item -ItemType Directory -Path $quarantineRoot -Force
foreach ($repository in $standaloneRepositories) {
  git -C $repository.Source status --porcelain=v2 --branch
  git -C $repository.Source rev-parse HEAD 'HEAD^{tree}'
  git -C $repository.Source ls-files --others --exclude-standard
  git -C $repository.Source for-each-ref --contains $repository.ExpectedHead
  git -C $repository.Source remote get-url origin
  git -C $repository.Source stash list
  git -C $repository.Source bundle create $repository.Bundle --all
  git bundle verify $repository.Bundle
}
```

For dirty SH-2201 also create:

```powershell
git -C 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-abacare\subagent-019f905a-b8cf-7ad1-82f0-da93b31c1641' `
  diff --binary > 'C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730\abacare-sh2201-working-tree.patch'
```

Verify bundle and patch paths are below:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730`.

- [ ] **Step 2: Move the four unique repositories**

After confirming exact absolute targets are below `C:\wt`, move complete directories with native PowerShell:

- SH-2237 → `C:\wt\abacare\sh2237-rbt-phone-fidelity`
- SH-2201 → `C:\wt\abacare\sh2201-agentic-ux-slice`
- SubOps `ecf208fd` → `C:\wt\subops\fleet-pass-a-strip-e26`
- SubOps `c1425002` → `C:\wt\subops\sh1093-correction-history`

Move the directory as one unit so `.git`, local branches, stashes, objects, and dirty WIP remain together. Do not reconstruct the checkout from a remote.

- [ ] **Step 3: Quarantine or preserve Shwiki according to current remote proof**

Run:

```powershell
$shwikiSource = 'C:\Users\SaroshHussain\.grok\worktrees\shmindmaster-shwiki\local'
$remote = git -C $shwikiSource remote get-url origin
git ls-remote --exit-code $remote refs/heads/main
```

If the returned commit is exactly `5d05de8362448bdfafee4b72cb8aa09f90918b70`, move the complete clean repository to:

`C:\Users\SaroshHussain\AppData\Local\AgentHub\quarantine\worktrees\20260730\shwiki-local`.

If the commit differs or cannot be verified, move the complete repository to:

`C:\wt\shwiki\local-preserved`.

In neither branch is the source recursively deleted.

- [ ] **Step 4: Verify all preserved identities**

Re-run HEAD/tree/status/stash checks at every destination and `git bundle verify` for every bundle. Confirm every audited `.grok\worktrees` source is absent.

- [ ] **Step 5: Update and commit migration evidence**

Record exact disposition, bundle path/hash, old/new path, HEAD/tree, dirty status, stashes, and remote-proof result.

```powershell
git add -- docs/fleet-convergence-worktree-migration-2026-07-30.md
git diff --cached --check
git commit -m "docs(agenthub): record standalone worktree preservation"
```

---

### Task 11: Run full verification, review, and direct-to-main integration

**Files:**
- Create: `docs/agent-fleet-convergence-status-2026-07-30.md`
- No other source changes unless verification produces a reproduced root cause and a new red-green task.

**Interfaces:**
- Consumes: every committed source change and every live migration/deployment result.
- Produces: fresh inventory, independent review, direct `main` integration, and an honest `PASS` or `BLOCKED` status.

- [ ] **Step 1: Run all focused and ecosystem suites**

```powershell
Invoke-Pester -Path .\tests\ManagedQuarantine.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\ExternalSkillOwnership.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\LiveAgentFleetDrift.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\Apply-FullAccessAgentProfile.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\PathSafety.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\NoHostedCi.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\RuntimeCentralization.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\WorktreePolicyDeployment.Tests.ps1 -Output Detailed
Invoke-Pester -Path .\tests\StaleWorktreeReaper.Tests.ps1 -Output Detailed
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-AgentEcosystem.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-FullAccessAgentProfile.ps1
node .\packages\handoff-plugins\plugins\product-demo-studio\scripts\validate-host-parity.mjs
```

- [ ] **Step 2: Generate the fresh full live inventory**

```powershell
$report = "$env:LOCALAPPDATA\AgentHub\reports\fleet-inventory\full-converged-20260730.json"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  .\scripts\Test-LiveAgentFleetDrift.ps1 -ReportPath $report -Json
```

Read the complete result. Do not reduce or hide failures. Expected unresolved gates are:

- `C:\tmp` — confirmed Codex Desktop platform blocker.
- `issue-to-pr` — preserve-pending evidence/authority blocker.
- Legal/knowledge skills — explicit preserve-pending warnings until canonical service ownership exists.
- Windsurf executable — permitted only as an explicit inactive-host warning.

Any other FAIL is a regression and must return to its owning task.

- [ ] **Step 3: Capture runtime evidence**

Record one five-second CPU-delta sample and complete ancestry for every local MCP tree. Expected after Grok correction: zero unsupported local MCP server trees. Codex `node_repl` wrappers remain host-owned and separately classified.

- [ ] **Step 4: Write the final status**

`docs/agent-fleet-convergence-status-2026-07-30.md` must include:

- Before/after PASS/WARN/FAIL counts.
- Canonical, external, preserved-pending, retired, and quarantined skill dispositions.
- Host deployment parity.
- Worktree old/new paths and recoverability evidence.
- Grok plugin correction and local-process counts.
- Codex `C:\tmp` blocker with exact reason.
- Commands and results.
- Commit range, current branch, and final report paths.
- An explicit `BLOCKED` decision if any FAIL remains; never call the fleet fully streamlined while blocked.

- [ ] **Step 5: Commit the final report**

```powershell
git add -- docs/agent-fleet-convergence-status-2026-07-30.md
git diff --cached --check
git commit -m "docs(agenthub): record fleet convergence status"
```

- [ ] **Step 6: Run the Superpowers whole-change review**

Generate a review package from the plan's merge base to `HEAD`. Dispatch a fresh high-capability reviewer with the approved design, this plan, task reports, full diff, test results, live inventory, quarantine manifests, and worktree evidence. Resolve every critical or important finding through the defined fix loop.

- [ ] **Step 7: Fast-forward `main` and push without a pull request**

From `C:\Repos\shmindmaster\agenthub`:

```powershell
git status --short
git fetch --prune
git merge --ff-only worktree-fleet-convergence
git push origin main
```

Stop on a non-fast-forward; do not rebase, force-push, or overwrite concurrent work.

- [ ] **Step 8: Remove the temporary implementation worktree safely**

After confirming `origin/main` contains the final `HEAD`:

```powershell
git -C C:\Repos\shmindmaster\agenthub worktree remove `
  C:\wt\agenthub\fleet-convergence
git -C C:\Repos\shmindmaster\agenthub worktree list --porcelain
git -C C:\Repos\shmindmaster\agenthub branch -d worktree-fleet-convergence
git -C C:\Repos\shmindmaster\agenthub worktree prune --dry-run
```

Do not use forced removal. If removal fails, preserve the worktree and report the exact blocker.
