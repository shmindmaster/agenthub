# Portfolio routes

Read the checkout `AGENTS.md` before this page. It wins on commands, boundaries and current outcome. This page only names the lane. Paths are under `C:/Repos/shmindmaster/`.

| Checkout | What it is | Do not cross | Checks named by the repo |
| --- | --- | --- | --- |
| `abacare` | ABA clinic operations: authorizations, session capture, claims, denials, parent summaries. AWS. Synthetic data until PHI boundaries are verified. | Clinic isolation, PHI, claim math, signed-note approval | `pnpm verify`; API domain pytest; web filter typecheck |
| `coledger` | Operating-review evidence for private-equity portfolios. One synthetic sponsor slice. | Portco isolation, financial math, closed periods, source citations | `pnpm verify` |
| `revolva` | Mobility operations workspace. The old delivery application is gone from the tree. | Case and field authorization, immutable source evidence, real worker data | `npm run lint`, `npm run typecheck`, `npm test` |
| `subops` | Contract-grounded statement recovery for FedEx Ground contractors. The HCBS lane is closed. | Tenancy, settlement math, driver PII, billing gates | `pnpm verify` |
| `lawli` | Guided legal self-help. Current proof is the Dallas eviction workflow. | Unauthorized practice, tenant ownership, tier checks on the API | `pnpm verify` |
| `lexalign` | Texas claim-assurance workbench. The policy-impact alternative is deferred. | Matter isolation, explicit trust posture, no production data mutation | `.\scripts\verify.ps1 -Steps verify` |
| `docwise` | Local document workbench over the MahumTech OneDrive library. No hosted service. | Live library apply, protected folders, secret and document text in logs | `uv run python -B -m unittest discover -s tests -v` on synthetic copies |
| `rexa` | One Expo app for interview and product study packs. Offline study is the product. | False card content, lost progress, paid narration masters | `npm test`, `npm run typecheck`, `npm run verify` |
| `lienwise` | Construction payment protection: jobs, deadlines, notices, waivers, evidence. | State-law deadlines, tenant scope, document access | `./scripts/verify` |
| `verigence` | Ambulatory administrative work with approvals and evidence. Stage 1 only. The generic evidence-packet alternative is deferred. | Tenant and location isolation, PHI serialization, approvals | `pnpm ci:prepare`, then `pnpm source-quality` |
| `agenthub` | Fleet capability, host deployment and drift control. | Credentials, private product data in the public tree, invented host formats | `pwsh -NoProfile -File .\scripts\Validate-AgentHub.ps1` |

Shared rules:

- One repository per task. Claim the Linear issue that repo names before editing.
- Mobile work is allowed only where `registry/mobile-scope.json` says the product is eligible.
- Public wiki is the door already configured on the host. Private wiki stays on the hosts that already retrieve credentials dynamically. Do not add client repositories to an index.
- Paid model defaults stay as they are. A disabled specialist route stays disabled until that model answers.
- `audit`, `design`, `build`, `verify`, `demo` and `engineer` are the shared lanes. Do not add a second agent framework.
