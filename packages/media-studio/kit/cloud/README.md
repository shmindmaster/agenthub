# cloud-render: shared cloud rendering for media-studio films

Owner direction (2026-10-26): voice and rendering run in the cloud; screen capture and mouse movement stay local.
`cloud-render.mjs` is the one render path every film session calls: it uploads the inputs from this machine,
renders in Azure, and downloads the result into your job folder.

```
node "%LOCALAPPDATA%\AgentHub\media-studio\briefing-kit\cloud\cloud-render.mjs" <mode> ...
```

| Mode | What runs in the cloud | Example |
|---|---|---|
| `ffmpeg` | Any FFmpeg command. The **last argument is the local output**. Local inputs, and every file an ffmpeg concat list names, are uploaded and rewritten. | `cloud-render.mjs ffmpeg --name qa1 -- -f concat -safe 0 -i list.txt -i voice.wav -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:v libx264 -preset veryfast -tune stillimage -crf 20 -pix_fmt yuv420p -r 30 -c:a aac -b:a 160k -shortest -movflags +faststart "C:\job\out\film.mp4"` |
| `remotion` | `remotion render src/index.ts <comp>` in the media-studio kit (your local kit `src/` is overlaid on the cloud kit). | `cloud-render.mjs remotion --comp MarketingAd --props compose\16x9\props.json --public-dir compose\16x9\public --out compose\16x9\silent.mp4 -- --codec=h264 --muted --crf=17` |
| `recast` | The kit's `renderRecast` (cursor, click ripple, auto-zoom) over a raw Playwright capture directory. | `cloud-render.mjs recast --raw capture\take-01 --out capture\take-01\recast.webm` |
| `exec` | Any command (`ffmpeg`, `ffprobe`, `node ...`) with explicit outputs. | `cloud-render.mjs exec --out mix.wav -- ffmpeg -i a.wav -i b.wav -filter_complex amix=inputs=2 mix.wav` |

**Long Remotion films: `--chunks N` (2-16).** Each chunk is its own execution and renders one frame range. The ranges come from the Remotion CLI, so the kit's own `remotion.config.ts` applies. The CLI joins the chunks with a stream-copy concat and checks the joined frame count against the ranges. Render the picture `--muted` and mux audio afterwards with `cloud-render ffmpeg`, because per-chunk AAC does not join gaplessly. Measured 2026-10-26 on a 1,920-frame Briefing: 4 chunks took 96 s end to end against 160 s for one job, at the same cost (/usr/bin/bash.04). Across seams the result matches a single render (SSIM 0.995 or higher). A 9-minute 1080p film (~16k frames) at about 6 chunks should take roughly 12-15 min instead of about an hour.

Options: `--name <label>` (job id label), `--cpu <1-4>` and `--memory <Gi>` (default 4 vCPU / 8 GiB),
`--kit <dir>` (kit to overlay; defaults to the kit this file sits in), `--dry-run` (print the plan, no cloud calls),
`--keep` (keep the local temp dir). Housekeeping: `doctor`, `status <jobId>`, `logs <jobId>`, `bootstrap`, `sync-worker`.

Each run prints a JSON summary (wall time split into upload / cloud / download, worker timings, upload reuse,
billed seconds and USD) and writes it next to the first output as `<output>.cloud-render.json`, with the cloud log
as `<output>.cloud-render.log`. Exit code is 0 only when the command succeeded and every output came back.

## Hosted AI steps: cloud-ai.mjs

```
node cloud-ai.mjs align  --take <take.wav> --script <locked-script.txt> --out voice/align/<id>.json   # or qa/encoded-alignment.json
node cloud-ai.mjs review --files <script.md> [...] --rubric <text|file> --threshold 85 --out review.json
node cloud-ai.mjs qa     --images <contact-sheet.jpg> [...] --prompt <context> --out qa.json [--client]
```

* **align**: Azure fast transcription (sh-speech F0, then sh-azai S0, then Deepgram) word times, anchored token by
  token to the locked script. Exact matches keep the acoustic onset. Numbers, currency, contractions and hyphenated
  compounds are matched by spoken form. A word the ASR heard differently gets a precisionLimited onset bounded by
  its neighbours. The report is `cloud-speech/script-alignment/1` with method **`asr-anchored-alignment`**, on the
  native 80 ms grid with take/script SHA-256 binding and an `agreement` block. It is not forced alignment: the
  picture, cue-sheet, word-sync and release gates refuse it unless the job opts in with
  `job.json` `"clockPolicy": { "allowAsrAnchored": true }`. Even then the sync gate re-checks at least 90% exact
  onsets and no precisionLimited run over 6. Without the opt-in, treat it as a cross-check.
  * Measured 2026-10-26 against Local-AI forced alignment: exact-word onsets agreed to a median of 0–80 ms, p90 80 ms.
  * Coverage: 214/232 exact on an 89 s narration, and 100% on two lab takes.
  * Word-sync: offset 0 ms and drift 0 ms.
* **review / qa**: Anthropic (latest Opus) first, then Azure OpenAI (gpt-5-mini in this resource group, Entra auth,
  key auth disabled), then Gemini on rate limits or exhausted quota. `--client` material never goes to Anthropic and
  defaults to Azure OpenAI in the owner's tenant. The report has score 0–100, pass, findings with fixes, provider,
  model and usage. Exit 0 means pass.
* Keys are read by name from the environment, then the Windows user environment, and are never printed.

## What to keep local

Screen capture (Playwright WebM, mouse movement) stays local: it needs the signed-in browser and the real screen.
Everything after the capture (Recast finishing, Remotion composition, FFmpeg encode/mix/loudnorm) can run here.
Voice stays on the Azure HD TTS voice kit; this tool does not synthesize speech.

## Cost

Azure Container Apps consumption pricing, Central US list price (prices.azure.com, 2026-10-26):
$0.000024 per vCPU-second + $0.000003 per GiB-second, billed only while a job runs.

* Default 4 vCPU / 8 GiB = **$0.0072 per minute of job time** (~$0.43/hour).
* The first 180,000 vCPU-s and 360,000 GiB-s each month are free (≈12.5 job-hours at 4 vCPU).
* Every job pays ~60–80 s of fixed overhead (image start, runtime download and unpack) before the command runs.
* Idle cost: none for compute (scale to zero). Blob storage is cents per GB-month; `jobs/` expires after 7 days,
  `cas/` (uploaded inputs, deduplicated by SHA-256) after 30. Downloads to this machine are internet egress
  (first 100 GB/month free).
* A $20/month budget on `rg-media-render` e-mails the owner at 50% and 90% actual and 100% forecast.

## How it works

```
this machine                               Azure (owner tenant, rg-media-render, Central US)
-----------                                ------------------------------------------------------
cloud-render.mjs                           Storage stmrender<sub8> (shared key off, no public access)
  hash + upload inputs  ────────────────▶    cas/<sha256>           content-addressed inputs
  write jobs/<id>/job.json ─────────────▶    jobs/<id>/             manifest, outputs, log, result
  ARM: start job execution ─────────────▶  Container Apps job caj-media-render (manual trigger, 0 replicas idle)
                                             image mcr.microsoft.com/playwright:v1.63.0-noble
                                             loader -> runtime/worker.mjs (managed identity)
                                             worker: unpack runtime/runtime-*.tgz to /opt/rt
                                                     (kit node_modules, Remotion headless Chrome, static FFmpeg)
                                                     download inputs, run command, upload outputs
  poll result.json, download outputs ◀───
```

* Auth: the local CLI uses Azure CLI tokens (`az account get-access-token`) in process; the job uses its
  system-assigned managed identity. There are no keys, SAS tokens or connection strings anywhere.
* No container registry: the public Microsoft Playwright image supplies Node and every Chromium system library;
  the runtime tarball in Blob supplies the rest. A registry would bill about $5/month while idle.

## Setup and maintenance

1. `pwsh -File Provision-CloudRender.ps1` (idempotent). Pass `-SubscriptionId`/`-TenantId` or set
   `CLOUD_RENDER_SUBSCRIPTION_ID`/`CLOUD_RENDER_TENANT_ID`; it refuses a subscription outside that tenant.
   Writes the non-secret config to `%LOCALAPPDATA%\AgentHub\media-studio\cloud-render.json`.
2. `node cloud-render.mjs bootstrap` builds the runtime tarball in the cloud (about 2 minutes, about $0.02).
   Re-run it when the kit's `package-lock.json` changes; `doctor` reports `kitLockMatchesRuntime`.
3. `node cloud-render.mjs sync-worker` ships a change to `worker.mjs` / `blob.mjs` without a rebuild.

## Limits

* Path rewriting covers command arguments, `--flag=path` values and ffmpeg concat lists. Paths inside filter graphs
  (`subtitles=`, `movie=`) or inside JSON props are not rewritten: use `--public-dir` + `staticFile()` for Remotion,
  or pass the file as a separate `-i` input.
* Ephemeral disk in the container is 8 GiB at 4 vCPU; inputs + runtime (~1.2 GB unpacked) + outputs must fit.
* Fonts: the cloud has the Playwright image's Linux fonts, not Windows fonts. Ship brand fonts through the
  composition's font files (`MarketingAd` already does); a composition that relies on a Windows system font will
  render with a fallback.
* One execution has a 2-hour timeout. Several executions can run at once.
