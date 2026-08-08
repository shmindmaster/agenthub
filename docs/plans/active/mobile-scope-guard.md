# Plan: Mobile Scope Guard and Platform Standard (2026-08-08)

## Purpose / outcome

No fleet product acquires a permanent mobile identity under a name that is
known to be temporary, and every product that *is* eligible for native mobile
work builds against one written baseline instead of a reconstructed-from-memory
one.

Mobile identifiers do not behave like the rest of the stack. An Apple bundle
identifier cannot be changed after the first build reaches App Store Connect,
and Android treats a changed `applicationId` as a different application. Sabhi
and Empowera are both pending refactor, repositioning, and rebranding, so any
Expo/EAS/Apple/Google/Firebase identity minted under their current names
becomes long-lived infrastructure carrying a name already known to be wrong.

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
- No mobile artifacts exist under `sabhi` (verified by behavior 5 of the new
  test); `empowera` and `documed` are not on disk to check.

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
  Maestro, Sentry, EAS Observe, `expo-doctor` CI gate).
- `abacare` `apps/mobile` (RBT session capture, caregiver workflows).
- `gentlenext` native caregiver/family experience.
- Apple App Store Connect API key; Google Play organization account and Play
  App Signing.
- Push (APNs/FCM v1) and Universal Links / Android App Links.

One carve-out is in scope: the Rexa EAS slug rename (milestone 4), separately
approved by the owner because the window closes at first store submission.

## Milestones

1. [x] `registry/mobile-scope.json` — 21 products classified, 3 frozen.
2. [x] `## Mobile scope` section in `global-agent-policy.md`.
3. [x] `mobile-platform-standard` skill + 2 references; registered in
       `capabilities.json`; `contentHash` recomputed.
4. [x] `tests/Test-MobileScope.ps1` — 5 behaviors, each verified to fail.
5. [ ] Fleet sync: instruction files rendered to all managed hosts.
6. [ ] Rexa EAS slug `recallforge` -> `rexa`.

## Validation per milestone

- M1–M3: `Validate-AgentHub.ps1` (contentHash drift is a hard failure).
- M4: `tests/Test-MobileScope.ps1` green, **and** each behavior demonstrated
  failing against a synthetic fixture — a test that has never failed proves
  nothing. Done 2026-08-08 against a scratch copy with a redirected
  `fleetRoot`; the real tree was never mutated.
- M5: `Sync-Instructions.ps1 -Audit` reports drift on every managed host and
  **zero unmanaged** hosts (an unmanaged destination is never written, so the
  guard would silently not reach that host), then `-Apply`.
- M6: `eas project:info` reports the unchanged `projectId` under the new slug
  and `eas build:list` still resolves prior builds.

## Decision log

- **2026-08-07** Owner: exclude Sabhi and Empowera from the mobile rollout; no
  Expo/EAS/store work until refactor and new product identity are decided.
- **2026-08-08** Owner: move `documed` from evaluate-later to frozen — dormant
  since 2026-07-18, never cloned, direction unsettled.
- **2026-08-08** Owner: rename the Rexa EAS slug now, while only internal
  preview builds exist.
- **2026-08-08** `subops` was absent from the owner's portfolio table.
  Classified `evaluateLater` (not eligible, identity not frozen) because
  unclassified must never resolve to eligible. **Open: owner call needed.**
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
rexa/app.json                                                       M6 only: slug
```

## Risks / rollback

- **A frozen identifier already exists remotely.** The on-disk check is the
  visible half; an EAS/Apple/Google/Firebase registration is the half that
  cannot be taken back. EAS CLI exposes no project-list command, so this was
  not verified for `sabhi`/`empowera`/`documed`. **Open item** — audit the Expo
  dashboard and Apple/Google consoles before treating the freeze as proven
  clean rather than merely enforced going forward.
- **The Rexa rename has no CLI path.** `eas project` exposes only
  `icon`/`delete`/`info`/`init`/`new`. If the dashboard offers no rename, the
  fallback (`eas project:new` + relink) discards build history and mints a new
  project ID — a different decision, to be brought back to the owner, not taken
  unattended.
- **Rexa has an active writer** per `fleet-repo-standardization.md`. Check
  `git status` before touching it; the slug change is one line and must not
  collide with in-flight work.
- Rollback for everything except M6 is `git revert`; the guard is declarative.
