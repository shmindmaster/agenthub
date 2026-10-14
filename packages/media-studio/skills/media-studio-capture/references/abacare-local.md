# ABACare capture notes

The product repository at `C:\Repos\shmindmaster\abacare` is read-only input. Keep capture work and all generated files in the external AgentHub Media Studio job workspace. Use synthetic Demo Clinic data only; never capture real patient data. The ABACare pronunciation lexicon is `abacare-lexicon.json` beside this guide; pass it to `Generate-OwnerVoice.ps1` as `-PronunciationLexicon` when that separately authorized workflow is used.

## 1. Choose and verify the capture target

An authenticated deployed capture is allowed only when the user has authorized that capture. Sign in through the deployed app at `/demo/auth?demo_role=owner` (or the approved role) with an approved synthetic Demo Clinic account. Supported role hints include `owner`, `admin`, `bcba`, `rbt`, `billing`, `staff`, and `parent`. The role hint chooses the landing workspace; it does not grant membership or permissions. Verify the deployed revision against the capture plan, then confirm `/auth/me` reports `metadata.demo_mode = "demo_clinic"` and the authenticated user's expected role before recording. Never use local-demo JWT auth against a deployed app.

For local capture, use the repository's local-only auth switches. `ABACARE_LOCAL_DEMO_AUTH=1` is accepted only for a local, non-production API; `VITE_LOCAL_DEMO_AUTH=1` lets the web app use that local session. These switches are disabled in production. Start with the default local infrastructure ports: Postgres on `127.0.0.1:55432` and Valkey on `127.0.0.1:56379`.

```powershell
cd C:\Repos\shmindmaster\abacare
pnpm dev:infra
pnpm qa:check-readiness
```

Run `pnpm dev:api` and `pnpm dev:web` in separate shells for local capture. In the API shell, set `ABACARE_RUNTIME_PROFILE=local` and `ABACARE_LOCAL_DEMO_AUTH=1`; in the web shell, set `VITE_LOCAL_DEMO_AUTH=1`. Pin `DATABASE_URL` and `ABACARE_DEMO_RESEED_DATABASE_URL` to the same explicitly chosen local target; do not inherit a portfolio or production database URL. Any local recording that writes rows must use a separately provisioned disposable named test database. Keep the shared local QA database at port `55432` intact.

`pnpm qa:check-readiness` requires `DATABASE_URL`, `REDIS_URL`, Clerk issuer/JWKS settings and secret, and `CONTACT_RELAY_URL`; it checks database, cache, and Clerk JWKS connectivity. Missing Stripe settings produce a warning that blocks billing QA. A passing result does not authorize a capture or reset, establish AI-provider readiness, or permit external delivery.

## 2. Authenticated Demo Clinic behavior

The deployed synthetic tenant is entered through the identified Demo Clinic sign-in at `/demo/auth`; do not use the account-free `/demo` preview for authenticated workflows. Use only an approved synthetic identity and confirm the resulting clinic and role in the app before capturing. Do not copy passwords, tokens, browser storage, or other authentication state into the guide, capture workspace, logs, or media.

The local-only JWT path is a development convenience. It is not a deployed sign-in method and does not change downstream authorization. In both environments, the app's normal role and clinic checks remain in force.

## 3. Synthetic data and state changes

The canonical synthetic tenant is **ABACare Demo Clinic**, ID `a11ab0ad-aba0-5eed-8000-000000000003`. Confirm that the visible records are synthetic and belong to this clinic before recording. Capture actions such as session submission or queue resolution can write persistent rows, including in the deployed synthetic tenant. Run only the state-changing beats included in the user's approved capture plan.

Do not reset between takes by default. The bounded capture-reset command changes allowlisted mutable rows for the canonical synthetic clinic. Use it only when a reset is necessary and only against an explicitly disposable, named local test database whose exact database name is passed to the command. Never target the shared `abacare_qa` database, any deployed database, or production. Follow the guarded reset procedure in `docs/runbooks.md`; do not use SQL, full-tenant reseeds, or volume deletion to rewind a capture. If deployed demo state has already been consumed, stop and ask the operator to prepare an approved state; do not reset or replay it.

Before retrying any action after a timeout or uncertain screen response, inspect the existing record and status. Avoid duplicate submissions and duplicate AI calls.

## 4. External side effects

Demo Clinic auth does not authorize a real-world send. Keep payer submission, parent-facing delivery, SMS, email, and payment lanes fenced during capture. Do not set `DEMO_EXTERNAL_SIDE_EFFECT_MODE=live` unless a written release checklist authorizes that exact walkthrough. Prefer visible internal workflow changes that remain inside the synthetic Demo Clinic.

## 5. AI and readiness boundaries

AI generation is governed by the runtime kill switch, the required active disclosure consent for the artifact scope, and the supported provider route. PHI-bearing generation requires the supported direct OpenAI route and configured credentials; unsupported routes, missing consent, or the kill switch fail closed. `OPENAI_BAA_VERIFIED` and `OPENAI_BAA_SIGNED_ON` are not application readiness switches and must not be set as a workaround.

Only film an AI result that the target environment actually returns for the synthetic client. Make one request, wait for its result, and confirm the generated artifact and review state before continuing. Do not invent a successful response, retry an uncertain request, or present a generated draft as human-approved. Human review or attestation remains required before a payer- or parent-visible release. If the environment blocks the lane, record Product-Readiness Feedback and move on.

## 6. Capture notes

- Rehearse the route and expected screen state before recording; selectors and workflows can change with product releases.
- Incident reporting has no staff web entry point; do not imply that an API-only path was captured through the UI.
- `is_sandbox` is a visibility flag, not an ownership boundary. Use the canonical clinic identity and guarded runbook checks to establish the target.
- Wait for a visible confirmation after an internal action, then hold the frame long enough for the result to be legible. A toast alone does not prove an external delivery occurred.
