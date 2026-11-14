# ABACare capture

The product repository `C:/Repos/shmindmaster/abacare` is read-only input. Use synthetic Demo Clinic data only; never capture real patient data.

## Target

- **Deployed:** only when the user authorized that capture. Sign in at `/demo/auth?demo_role=owner` (or `admin`, `bcba`, `rbt`, `billing`, `staff`, `parent`) with an approved synthetic account. The role hint picks the landing workspace, not permissions. Do not use the account-free `/demo` preview for authenticated workflows. Verify the deployed revision against the capture plan and confirm the clinic and role in the app.
- **Local:** `pnpm dev:infra`, `pnpm qa:check-readiness`, then `pnpm dev:api` and `pnpm dev:web` in separate shells. API shell: `ABACARE_RUNTIME_PROFILE=local`, `ABACARE_LOCAL_DEMO_AUTH=1`. Web shell: `VITE_LOCAL_DEMO_AUTH=1`. Pin `DATABASE_URL` and `ABACARE_DEMO_RESEED_DATABASE_URL` to the same chosen local target; do not inherit a portfolio or production URL. Postgres is `127.0.0.1:55432`, Valkey `127.0.0.1:56379`.

A passing readiness check does not authorize a capture or reset, or establish AI-provider readiness. Never copy passwords, tokens or browser storage into the workspace, logs or media.

## Data and state

The synthetic tenant is **ABACare Demo Clinic**, ID `a11ab0ad-aba0-5eed-8000-000000000003`. Confirm visible records belong to it. `is_sandbox` is a visibility flag, not an ownership boundary.

- Session submission and queue resolution write persistent rows, even in the deployed tenant. Run only the state-changing beats in the approved plan.
- Do not reset between takes by default. Reset only an explicitly disposable, named local test database, with the guarded procedure in the product's `docs/runbooks.md`. Never target `abacare_qa`, a deployed database or production.
- After a timeout or uncertain response, inspect the record before retrying. Avoid duplicate submissions and duplicate AI calls.

## Side effects and AI

- Demo Clinic auth does not authorize a real send. Keep payer submission, parent delivery, SMS, email and payment fenced. Do not set `DEMO_EXTERNAL_SIDE_EFFECT_MODE=live` without a written release checklist for that walkthrough.
- `OPENAI_BAA_VERIFIED` and `OPENAI_BAA_SIGNED_ON` are not readiness switches. Do not set them as a workaround.
- Film only an AI result the environment actually returned. Make one request, wait, and confirm the artifact and review state. Never present a draft as human-approved. If the environment blocks the lane, record readiness feedback and move on.

## Notes

- Incident reporting has no staff web entry point; do not imply an API-only path was captured through the UI.
- A toast does not prove an external delivery. Hold the visible internal confirmation.
