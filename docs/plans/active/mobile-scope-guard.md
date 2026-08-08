# Plan: Mobile Scope Guard and Platform Standard (2026-08-08)

## Purpose / outcome

No fleet product acquires a permanent mobile identity under a name that is
known to be temporary, and every product that *is* eligible for native mobile
work builds against one written baseline instead of a reconstructed-from-memory
one.

Mobile identifiers do not behave like the rest of the stack. An Apple bundle
identifier cannot be changed after the first build reaches App Store Connect,
and Android treats a changed `applicationId` as a different application. A
product pending refactor, repositioning, and rebranding therefore cannot have
an Expo/EAS/Apple/Google/Firebase identity minted under its current name: that
identity becomes long-lived infrastructure carrying a name already known to be
wrong.

The guard earned its keep within a day. The product frozen here on 2026-08-07
was renamed to **LienWise** on 2026-08-08 — new domain, new package
identifiers, and a `git filter-repo` rewrite that erased the retired name from
all 296 commits. Had a bundle identifier been minted under the old name during
that window, it would have outlived the rename permanently.

This is not hypothetical here. Rexa's EAS project shipped as
`@shmindmaster/recallforge` — the pre-rename product name, live in every build
URL — recoverable only because nothing had been store-submitted yet.

## Verified state at start (2026-08-08)

- `registry/repo-standard.json` roster: 17 repos; `awesome-mcp-servers` and
  `.demo-workspace` excluded.
- `empowera` and `documed` exist as private GitHub repos (both last pushed
  2026-07-18) but are **not cloned** to the fleet root, so a path-keyed guard
  would not bind them.
- `scripts/Check-RepoStandard.ps1` iterates the roster, not the filesystem, so
  nothing currently fails when a newly cloned repo is missing from the roster.
- Rexa: Expo SDK 57 / RN 0.86 / React 19.2.3, EAS project
  `982c8db2-0af0-4bc0-9770-b261385c78cc`, slug `recallforge`, bundle IDs
  `app.shmindmaster.rexa` (correct). `eas build:list` shows only
  `preview`/internal builds — nothing store-submitted.
- Rexa declares `developmentClient: true` in `eas.json` but carries no
  `expo-dev-client` dependency.
- No mobile artifacts existed under the then-frozen product (verified by
  behavior 5 of the new test); `empowera` and `documed` are not on disk to
  check.

## Target observable behavior

1. `registry/mobile-scope.json` classifies every fleet repository; an
   unclassified repository is a test failure, not a silent default to eligible.
2. `global-agent-policy.md` carries the prohibition, compiled verbatim into all
   17 managed hosts' global instruction files including Cline.
3. `tests/Test-MobileScope.ps1` fails if the guard is weakened, if a repository
   appears unclassified, or if a frozen product grows a mobile footprint.
4. The `mobile-platform-standard` skill gates on the registry before it
   describes any baseline.

## Exclusions

Deliberately **not** in this plan; each needs its own decomposition:

- Rexa reference-implementation hardening (dev-client, three installable
  variants, EAS environments, EAS Update + fingerprint runtime, EAS Workflows,
  Maestro, Sentry, EAS Observe, `expo-doctor` CI gate). **Its first step is
  M6 below.** Also carries a defect found here: `eas.json` declares
  `developmentClient: true` while `package.json` has no `expo-dev-client`.
- `abacare` `apps/mobile` (RBT session capture, caregiver workflows).
- `gentlenext` native caregiver/family experience.
- `subops` native statement/evidence field capture.
- Apple App Store Connect API key; Google Play organization account and Play
  App Signing.
- Push (APNs/FCM v1) and Universal Links / Android App Links.

One carve-out was in scope — the Rexa EAS slug rename — but Expo turned out to
expose no rename, so it became a project re-create and moved into the hardening
work. See "Rexa identity" below.

## Milestones

1. [x] `registry/mobile-scope.json` — 21 products classified, 3 frozen.
2. [x] `## Mobile scope` section in `global-agent-policy.md`.
3. [x] `mobile-platform-standard` skill + 2 references; registered in
       `capabilities.json`; `contentHash` recomputed.
4. [x] `tests/Test-MobileScope.ps1` — 5 behaviors, each verified to fail.
5. [x] Fleet sync: instruction files rendered to all managed hosts.
6. [ ] **Rexa EAS project re-create** — deferred into the Rexa hardening work
       by owner decision 2026-08-08, as its *first* step. See "Rexa identity"
       below. This is a milestone, not an intention: `recallforge` survived
       this long precisely because it was never one.

## Validation per milestone

- M1–M3: `Validate-AgentHub.ps1` (contentHash drift is a hard failure).
- M4: `tests/Test-MobileScope.ps1` green, **and** each behavior demonstrated
  failing against a synthetic fixture — a test that has never failed proves
  nothing. Done 2026-08-08 against a scratch copy with a redirected
  `fleetRoot`; the real tree was never mutated.
- M5: `Sync-Instructions.ps1 -Audit` reports drift on every managed host and
  **zero unmanaged** hosts (an unmanaged destination is never written, so the
  guard would silently not reach that host), then `-Apply`.
- M6: `eas project:info` reports `@shmindmaster/rexa`; `app.json` carries the
  new `extra.eas.projectId`; an internal build succeeds on the regenerated
  credentials.

## Rexa identity (M6 detail)

**Measured 2026-08-08.** Expo exposes no slug rename. The project settings
page edits only a separate "Display name" field; the Danger zone offers only
transfer and delete, and `eas-cli` 21.7.0 exposes only
`project:icon|delete|info|init|new`. `@shmindmaster/recallforge` is therefore
permanent for project `982c8db2-0af0-4bc0-9770-b261385c78cc`. The only route
to `@shmindmaster/rexa` is a new EAS project.

What a re-create actually costs, measured rather than assumed:

| Asset | State | Cost |
| --- | --- | --- |
| Store submissions | `eas submit:list` empty | none |
| EAS Update branches | `eas branch:list` empty | none |
| EAS Update channels | `eas channel:list` empty | none |
| `expo-updates` | not in `package.json`; no `updates`/`runtimeVersion` in `app.json` | none |
| Build history | 2 internal `preview` builds | lost |
| iOS credentials | present | regenerate |
| Bundle identifiers | `app.shmindmaster.rexa` on both platforms, already correct | unchanged |

So the only real cost is regenerating iOS credentials — which the hardening
work incurs anyway the moment it mints `.dev` and `.preview` variants. Doing
the re-create as hardening's first step pays that cost once instead of twice.

Note what is *not* at stake: the stale name never reaches Apple, Google, or an
end user. Both bundle identifiers are already correct. `recallforge` lives
only in expo.dev URLs. That is the whole reason deferring is safe here and
would not be safe for a name that had reached a store.

## Decision log

- **2026-08-07** Owner: exclude two products from the mobile rollout; no
  Expo/EAS/store work until refactor and new product identity are decided.
- **2026-08-08** The first of those two exited the freeze the way the schema
  intended. The owner established the new identity (`docs/lienwise/DECISION.md`,
  lienwise.ai), renamed the repository, and rewrote the retired name out of all
  296 commits — the recorded `exitCondition`, met by the owner's own artifacts —
  then ruled it in scope. Moved to `include` at **P1**; reverse-DNS is now
  `ai.lienwise.*`. Priority was my call, not the owner's: P0 is the reference
  build and the health flagship, so a fifth eligible product sits at P1. The
  native case is field capture — site photos, delivery proof, signed waivers.
  `empowera` and `documed` stay frozen.
- **2026-08-08** Owner: move `documed` from evaluate-later to frozen — dormant
  since 2026-07-18, never cloned, direction unsettled.
- **2026-08-08** Owner: rename the Rexa EAS slug now, while only internal
  preview builds exist. **Superseded same day**: Expo exposes no slug rename
  at all, so the only route is a new EAS project. Owner then chose to fold the
  re-create into the Rexa hardening work as its first step, because that work
  regenerates iOS credentials regardless.
- **2026-08-08** `subops` was absent from the owner's portfolio table, so it
  was parked in `evaluateLater` because unclassified must never resolve to
  eligible. Owner then ruled it **`include`, P1** the same day. Priority was my
  call, not the owner's: P0 is the reference build and the flagship, so a
  fourth eligible product sits with `gentlenext`.
- **2026-08-08** The guard keys on product identity, not local path, so a
  freeze binds `empowera` and `documed` despite neither being cloned.
- **2026-08-08** Accountability reuses `repo-standard.json` -> `excluded`
  rather than restating which repositories sit outside the fleet standard, so
  the two files cannot disagree.

## Discoveries

- The original design assumed a portfolio config listing repos to prune from.
  There is none — `portfolio-audit` discovers repos by scanning for `.git`. The
  enforcement therefore had to be inverted: classify everything, fail on the
  unclassified. That is stronger than a deny-list, which only blocks names
  somebody remembered to add.
- **Deploying the skill surfaced a live fleet-wide defect**, unrelated to
  mobile scope but blocking this deliverable. `Sync-Capabilities.ps1` wrote its
  ownership ledger *after* the failure gate, while the file copies happened
  earlier in the loop — so any run with a refusal deployed skills and recorded
  none of them. The live ledger had been frozen at 2026-08-05 since the
  `use-chrome-devtools-mcp` refusals appeared on 2026-08-06, silently
  stranding every skill deployed after that as unowned and unrepairable.
  Fixed at owner request: ledger writes before the gate, recording only what
  the run can honestly claim. Recovered 469 -> 501 destinations.
- `Check-RepoStandard.ps1` iterating the roster rather than the filesystem
  leaves a real gap: a newly cloned repo is invisible to it. Behavior 2 of
  `Test-MobileScope.ps1` closes that gap for mobile scope specifically.
  Whether the fleet checker itself should also detect off-roster clones is a
  separate question, not addressed here.

## Files changed

```text
registry/mobile-scope.json                                          new
registry/capabilities.json                                          managedSkillNames + contentHash
global-agent-policy.md                                              ## Mobile scope
tests/Test-MobileScope.ps1                                          new
packages/portfolio-engineering/skills/mobile-platform-standard/     new (SKILL.md + 2 references)
docs/plans/active/mobile-scope-guard.md                             this file
rexa/app.json                                                       M6 only: extra.eas.projectId
```

## Risks / rollback

- **A frozen identifier already exists remotely.** The on-disk check is the
  visible half; an EAS/Apple/Google/Firebase registration is the half that
  cannot be taken back. EAS CLI exposes no project-list command, so this was
  not verified for `empowera`/`documed`. **Open item** — audit the Expo
  dashboard and Apple/Google consoles before treating the freeze as proven
  clean rather than merely enforced going forward.
- **Rexa's stale identity is now permanent unless M6 runs.** Resolved to a
  measured decision above; the residual risk is that M6 is skipped and
  `recallforge` reaches a store URL.
- **Rexa working tree** was clean at 2026-08-08 (`670e54a`, only untracked
  RepoWise artifacts), so the active-writer warning in
  `fleet-repo-standardization.md` did not apply. Re-check before M6.
- Rollback for everything except M6 is `git revert`; the guard is declarative.
