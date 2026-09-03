# Execution

How to run this against a real product. Written for a Windows workstation with several product repositories checked out locally and their deployments live on public domains.

---

## 1. Install

Drop the plugin directory where your agent loads plugins from. It ships `.claude-plugin/plugin.json`; Factory, VS Code, Copilot, and Qwen Code read that layout natively, so nothing extra is needed for those. `policy/host-manifests.json` records which host does what and where that was read from.

Prerequisites on PATH: **Node 20+**, **ffmpeg**, and **ffprobe**. Verify before the first run — several gates shell out to ffprobe and fail as `BLOCKED` without it.

```powershell
node --version ; ffmpeg -version ; ffprobe -version
```

Scripts are ESM with shebangs. On Windows, invoke them through Node explicitly:

```powershell
node <plugin>\scripts\verify-fixtures.mjs
```

## 2. Calibrate — once, before trusting any verdict

Load `pipeline/commands/demo-calibrate.md` (not a slash command).

Two fixture sets ship with the plugin: five defective web applications for demo-worthiness, six defective masters for craft. **Both run with no product and no environment**, so the gates are provable before you point this at anything.

If a known-bad fixture passes, or either `clean-pass` fails, every verdict since the last successful calibration is suspect. Diagnose the rubric, the reviewer brief, the model, then the input contract. **Never adjust a fixture to match a result.**

Until this has passed once, every verdict the system produces is unproven.

## 3. Configure each product repo

One config per repo. This is the only place a product name appears anywhere in the system, which is what lets one plugin serve all of them.

```powershell
copy <plugin>\product-demo-studio.config.example.yaml C:\Repos\shmindmaster\abacare\product-demo-studio.config.yaml
```

Fill in `environment.url`, `environment.reset`, `output_root`, brand tokens, and the voice profile. The run stops rather than guessing any of them.

Repeat per product. Nothing is shared between repos — not persona, not seed data, not brand tokens — and no run should ever span two products.

## 4. Assess before you capture

Load `pipeline/commands/demo-assess.md` with `--repo C:\Repos\shmindmaster\abacare`.

Produces a demo-worthiness verdict per candidate episode and a Product-Readiness Feedback Report where any candidate failed. No capture, no narration, no render.

**Expect the first run on any product to come back feedback-only.** That is the normal result for a product that has not been through this before, and it is the more useful one — a list of specific defects with buildable fixes, ordered by how many episodes each unblocks.

## 5. Produce

Public entry: media-studio `/video` (kind `product-screencast`).
Engine procedure: load `pipeline/commands/demo-video.md` with `--repo C:\Repos\shmindmaster\abacare`.

Runs the full pipeline for episodes assessment cleared. Two valid outcomes: a fully gated video, or feedback and no video. A mediocre-but-accurate video is the defect the system exists to prevent — it will not produce one, and you should not ask it to.

---

## The thing that will bite first: production is not a demo environment

A live public deployment seeded with demo data is genuinely usable for assessment and capture. It is not a demo *environment*, and the difference shows up in three places.

**`deterministic-resettable` cannot be evidenced by reset.** There is no reset endpoint on production. The substitute is walking the flow twice and comparing — which proves reproduction, not resettability. That substitution must be recorded in the verdict, not glossed over.

**The product can change mid-run.** A deploy between capture and review invalidates the provenance binding between the master and the source commit. Either freeze deploys for the duration of a capture run, or accept that the recorded commit may not be what was filmed and say so.

**State leaks between walks.** If a demo tenant accumulates records as flows are exercised, the second walk differs from the first for reasons that have nothing to do with determinism. The seed either resets or it is append-only and the assessment has to account for it.

The clean answer is a resettable environment per product — `demo.<product>.ai` with a reset endpoint, seeded from a fixture set. **That is the single highest-value prerequisite for this whole system**, and with the repos in hand it is entirely in your control. Until it exists, run against production and record the substitution honestly.

**Hard stop:** if a deployment carries real user data alongside demo data, do not walk it. That is `PIPELINE_BLOCKED`, not a caveat to note.

## Seed data has to tell a story

Not `test@test.com`, not lorem, not `Customer 1` through `Customer 40`. The specific overdue claim from the payer that always denies. The contract with the renewal date three days out. Relatable specifics stick; random data reads as fake and costs the `clean-believable-states` criterion.

This is worth real effort per product. It is also reusable — a good seed set serves every episode that product will ever have.

## Where files go

The product repo is **read-only input**. Captures, manifests, narration, renders, evidence, and working memory go to the external video workspace. Only accepted final masters reach `output_root`. Nothing scaffolds into the product source tree.

## Running across several products

Assess all of them before producing any. The feedback reports collectively tell you which product is closest to demo-ready, and that is the one to build the first video for — not the one you most want a video of.

Track across runs:

- **Per-criterion failure rate.** A criterion that has never failed is decoration, not a gate. Either remove it or find out why it is not being evaluated.
- **Classification accuracy** — how often `capture-fixable` actually was fixable at capture. Repeated late craft failures on episodes marked `CONDITIONAL` mean the boundary has slipped toward permissiveness.
- **Calibration history.** The only evidence the gates were working on any given past date.

Because you own these products, a `product-fix-required` verdict lands in your own backlog and comes back fixed. That closed loop is what makes the machinery worth its cost — so write the feedback for your own engineers: repo paths, component names, your ticket IDs.

## Prompt shapes that work

Assessment:

> Assess demo readiness for the repo at `C:\Repos\shmindmaster\abacare`. Config is in the repo. Real screens against the live deployment, demo tenant data only. If a workflow isn't demo-worthy today, give me the feedback report and no video.

Production, after assessment cleared something:

> Produce the demo video for the episode assessment cleared in `C:\Repos\shmindmaster\abacare`. Real backend, no mocked screens, no hardcoded results. Working package to the external workspace, not the repo.

Recognizing the ask without naming a command:

> Our demos are stale — the UI moved. Which products need re-recording?

The router handles that last one: it recognizes the intent, asks which repos, and dispatches per product.

## Known limitations

- **No reviewer has run against the calibration fixtures.** Whether the gates return the expected verdicts is unproven until `pipeline/commands/demo-calibrate.md` executes.
- **No manifest has been load-tested on any host.** Static presence is not parity; `policy/host-parity.json#validationScope` says so directly.
- **`mappedHosts` lists eighteen hosts**, seven marked `documentation-not-read`. Trim it to the hosts you actually run rather than resolving rows you will never use.
- **Antigravity's root `plugin.json` may be unnecessary.** Counter-evidence from a working install without one is recorded in `policy/host-manifests.json`. The file is harmless; the test to settle it is a five-minute install.
