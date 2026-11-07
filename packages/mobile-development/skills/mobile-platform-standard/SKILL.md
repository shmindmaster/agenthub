---
name: mobile-platform-standard
description: Sets the eligibility gate and platform baseline for native iOS and Android work. Use when touching Expo, EAS, React Native, app.config, bundle identifiers, TestFlight, Google Play, push, deep links or store submission. Not for emulators; use mobile-device-lab.
---

# Mobile platform standard

## Workflow contract

1. Resolve product eligibility, target platform, and identity before selecting tooling.
2. Choose the approved baseline and build route, then hand device execution to `mobile-device-lab` with an explicit platform and smoke scenario.
3. Return the platform decision, build command and evidence needed for device verification.
4. If the product or bundle identity is unregistered, stop before provisioning or installing anything.

Read before writing mobile code or touching any Apple, Google, Expo, EAS or Firebase surface.

```powershell
$mobile = "$env:LOCALAPPDATA\AgentHub\capabilities\mobile-development\mobile.ps1"
pwsh -NoProfile -File $mobile scope <productId> -Json
pwsh -NoProfile -File $mobile catalog -Json
```

## 1. Eligibility gate

`registry/mobile-scope.json` is the sole authority for which products may receive mobile work. Resolve the product there first.

| Bucket | Action |
| --- | --- |
| `include` | Proceed with the baseline. |
| `noNative` | Stop. No native surface intended. |
| `evaluateLater` | Stop. Reserve no identifier. |
| `excludedPendingReposition` | Stop. Identity is frozen. |
| absent | Stop and ask the owner to classify it. |

Only an exact `include` record authorizes product-targeted mobile work. A repository, app config, existing build, domain or remembered decision is not evidence.

For a frozen product, every class in `scopePolicy.frozenIdentifierClasses` is prohibited, and a placeholder identifier is one of them. Only the owner lifts a freeze, through the product's `exitCondition`. A bundle identifier is permanent after the first App Store Connect upload.

## 4. Identity

- `registry/mobile-scope.json` is the sole product identity authority. Use the product's `mobileIdentity` exactly; never derive, normalize or improve it from this skill, another product, an old build or a dashboard.
- Treat EAS IDs and slugs, Apple team and certificate state, App IDs, profiles and devices as live facts: resolve them at execution time and do not persist a second table in a skill.
- Identity, signing, registration, submission, credential changes and profile cleanup are owner-gated. If authority and provider disagree, stop and report.

## 5. Health-sensitive products

Where `healthSensitive` is true, enable no screenshot collection, session replay or broad AI/MCP access against real patient data; review the model provider's retention policy first and use synthetic fixtures.

## References

- `references/store-compliance.md`. Read when preparing a store submission.
- `references/release-infrastructure.md`. Read when running a local build, checking signing, setting up Apple or Google accounts, API keys, beta lanes or EAS variables, installing an `.ipa`, or adding an identifier variant or EAS project.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
