# ABACare local capture (product-specific notes)

Product repository `C:\Repos\shmindmaster\abacare` is read-only input. Everything below runs from the
external job workspace (`%LOCALAPPDATA%\AgentHub\media-studio\<job>`); nothing is written into the repo.
Pronunciation lexicon for this product: `abacare-lexicon.json` beside this file (pass it as
`-PronunciationLexicon` to `Generate-OwnerVoice.ps1`).

## 1. Stack

Local only. Production Clerk cannot sign in on `localhost`, and the production tenant must never be
captured. The local stack is Postgres + Valkey in Docker, the FastAPI API on 8000, Vite web on 8080.

```powershell
cd C:\Repos\shmindmaster\abacare
$env:POSTGRES_PORT = '9202'          # 55432 sits inside a Windows excluded port range (55377–55476)
pnpm dev:infra                        # abacare_qa-postgres-1 (127.0.0.1:9202), abacare_qa-redis-1 (56379)
$env:DATABASE_URL = 'postgresql://abacare_qa:abacare_qa@127.0.0.1:9202/abacare_qa'
$env:ABACARE_DEMO_RESEED_DATABASE_URL = $env:DATABASE_URL
$env:ABACARE_ENV_PINNED = 'DATABASE_URL,ABACARE_DEMO_RESEED_DATABASE_URL'   # stops an ambient portfolio DATABASE_URL from retargeting seeds
$env:ABACARE_RUNTIME_PROFILE = 'local'
uv run --directory apps/api alembic upgrade head
pnpm qa:check-readiness; pnpm seed:catalogs; pnpm seed:synthetic
pnpm qa:sync-local-users -- --ensure-parent-link --replace-roles
```

API and web, each in its own shell, with the capture auth switches on:

```powershell
$env:ABACARE_LOCAL_DEMO_AUTH = '1'; pnpm dev:api       # mounts POST /api/local-demo-auth/session {persona}
$env:VITE_LOCAL_DEMO_AUTH = '1'; $env:VITE_API_URL = 'http://localhost:8000/api'; $env:VITE_APP_URL = 'http://localhost:8080'; pnpm dev:web
```

The repo's `.env.local` points `VITE_APP_URL` at production and `DATABASE_URL` at 9202; the API loads
`.env.local` before `.env`, so pin the variables above in the shell rather than editing either file.

## 2. Auth for capture

`apps/api/src/core/auth/local_demo_auth.py` mints a short-lived JWT for one of the fixed QA personas when
`ABACARE_LOCAL_DEMO_AUTH=1` and the environment is not production. The web (`hooks/authSource.ts`) reads
`?persona=<id>` from the URL, stores it in `localStorage['abacare_local_demo_persona']`, and boots without
Clerk when `VITE_LOCAL_DEMO_AUTH=1`. Downstream authorization is the unmodified production path, so a
capture shows exactly what that role sees.

| Persona | `?persona=` | Lands on | Use for |
| --- | --- | --- | --- |
| RBT (technician) | `rbt` | `/home/rbt` → `/rbt/today` | session capture, goal progress |
| BCBA (supervising clinician) | `bcba` | `/home/bcba` | review queue, Review Studio, co-sign, parent summary |
| Billing | `billing` | `/home/billing` | hold queue, Ready to Bill, denials |
| Owner / admin | `owner`, `admin` | `/home/owner`, `/home/admin` | authorization risk, exceptions, onboarding |
| Parent | `parent` | `/parent` | family portal |

In `capture/scenes.mjs`, open the first route of each take as `h.go('/rbt/today?persona=rbt')`; the persona
sticks for the rest of the context. No storage state file is needed.

## 3. Canonical demo data

Tenant: **ABACare Demo Clinic** (`CANONICAL_DEMO_CLINIC_ID = a11ab0ad-aba0-5eed-8000-000000000003`).
Caseload: Carter Bennett (hero client), Amara Collins, Liam Jensen, Nadia Kim, Mateo Rivera, Sofia Delgado,
Elijah Brooks. All synthetic. Carter's live hero session is seeded `SCHEDULED`, CPT 97153, 4 units, with
**zero** pre-seeded data-collection rows, so the goal graph genuinely fills during the take. The separate
"Carter continuity" spine (submitted note, held claim, authorization) feeds the BCBA, billing and
authorization beats.

## 4. Reset between takes (mandatory)

Capture beats write real rows (a submitted session, a resolved hold, a scanned exception queue). Before every
take set, rewind the canonical tenant's mutable state:

```powershell
pnpm seed:synthetic:capture-reset --expected-database abacare_qa --confirm-canonical-demo-clinic
```

It refuses any clinic other than the canonical tenant, restores the RBT session to `SCHEDULED` with no
data-collection rows, the BCBA review to pending, the parent acknowledgement to `PENDING`, held-claim
readiness, the authorization successor, clears `/exceptions`, and rewinds onboarding to `DRAFT`. The
`/exceptions` scan is idempotent, so a retake without a reset shows no change on screen. The authorization
successor and its baseline are mutually exclusive states: film them as separate takes with a reset between.

## 5. AI lanes on a local stack

- RBT session note draft (`session_notes.py`) uses the ungoverned chat tier and works with a DigitalOcean
  Inference key (`ABACARE_DO_INFERENCE_CREDENTIALS`). Real latency; keep the wait in the take and compress
  it only with a `speed` hint and `speedReason` in the manifest.
- Parent summary, treatment-plan generation, document intelligence and appeal drafting are PHI lanes behind
  `assert_phi_safe_to_generate`; locally they return 403 unless the operator sets `OPENAI_BAA_VERIFIED=true`,
  `OPENAI_BAA_SIGNED_ON`, and a real OpenAI key in the shell. That is an operator decision, not a repo change.
  Without it, do not film those beats; report them as Product-Readiness Feedback (environment), never fake the response.

## 6. Known traps

- Bug-magnet pages: `RbtSession.tsx`, `BcbaReviewStudio.tsx`, `BillingHoldQueue.tsx`. Rehearse a take headed before recording it.
- Incident reporting has no staff entry point in the web app (API only); not filmable.
- `is_sandbox` is a visibility flag, not an ownership fence; do not reason about resets from it.
- Ids collide across seed spaces (sandbox vs seeded, capture vs billable session); a 404 in psql is usually that.
- Toasts are the visible proof for resolve/submit actions; wait for them with `h.expect(page.getByText(/Hold resolved/), 'hold resolved')` and hold ≥ 1.5 s.
