# Local-AI image (progressive load)

Load only when the task needs Visual Bank image generation or enrollment.
Control plane remains `ai.ps1` / `$LocalAiControl`.

## Image — FROZEN Visual Bank (parity with voice)

> **The asset is the asset; the model is only the renderer.** Visual Bank ids are
> model-independent (`person-sarosh`, never `sarosh-flux`). FLUX.2 Klein 4B is
> the local default via ComfyUI. Escalate technique before model. Exact logos /
> QR / legal text = compositor. Face restoration OFF for enrolled people by
> default. No silent cloud or oversized-model fallback. **Never synthesize
> product UI, metrics, customer evidence, or testimonials** — those are capture
> or compositor type, not diffusion.

Authoritative disk policy (do not fork a second catalogue into AgentHub):

- `$LocalAiRoot\data\artifacts\media\visual-corpus\PRODUCTION-IMAGE-POLICY.md`
- `$LocalAiRoot\data\artifacts\media\visual-corpus\VISUAL-MAP.md`
- `$LocalAiRoot\data\artifacts\media\visual-corpus\library.json`
- `$LocalAiRoot\data\artifacts\media\visual-corpus\AGENTS.md`

Architecture:

```text
VISUAL BANK → ASSET ROUTER (people/products/styles/places/brands/…)
  → CONDITIONING (multi-ref | LoRA | Control | mask | preset | prompt)
  → MODEL (Klein local ★ | Z-Image stub | FLUX Pro/Max/Flex stub)
  → 5060 Ti BF16 → FP8 → vetted FP4
  → POST (mask helper | inpaint | Real-ESRGAN/Lanczos | composite)
```

### Callable today vs planned

| Lane | Status |
| --- | --- |
| Preset + bucket snap + catalog visuals | **LIVE** (`--preset`, `ai.ps1 catalog`) |
| Multi-ref identity (`--asset` / `--ref-*`) | **LIVE** (needs ComfyUI + ReferenceLatent) |
| Design factory + enroll | **LIVE** (`image design` / `image enroll`) |
| Mask helper + inpaint (`image mask` / `--edit`) | **LIVE** (ML mask needs Grounded-SAM/transformers; `--fallback` ok) |
| ControlNet (`--control` + `--controlnet`) | **LIVE when weights/nodes present** (opt-in) |
| Post upscale + exact composite | **LIVE** (`image post`; Real-ESRGAN optional) |
| Prepare cache / model goldens | **LIVE** (`prepare-cache` / `goldens`) |
| Batch job grouping | **LIVE** (default on) |
| LoRA load | **LIVE path**; only when adapter enrolled under Comfy `loras/` |
| Z-Image / FLUX Pro/Max/Flex | **STUB** — loud fail until enrolled (no silent swap) |
| LoRA training on 5060 Ti | **NOT supported** (train Base off-box ≥24 GB) |

### STOP — first-class visual assets

| Display | Canonical id | Default render |
| --- | --- | --- |
| **Sarosh** | `person-sarosh` | multi-ref → Klein |
| Photo Editorial / Ecommerce / Cinematic | `preset-photo-*` | Klein + preset |
| Illustration Editorial / Flat Vector | `preset-illustration-*` | Klein + preset |
| Product 3D render language | `preset-render-product-3d` | Klein + preset |

Never invent per-model identities. Resolve via `library.json` / `VISUAL-MAP.md` /
`ai.ps1 catalog --resolve-visual …`. Canonical `references/` are sacred.

### Router

1. Generic look → `--preset` → Klein
2. Enrolled asset → `--asset` multi-ref (≤4 slots; declare roles)
3. Exact structure → `--control` + `--controlnet` (opt-in)
4. Surgical edit → `image mask` then `single --edit --mask`
5. Chronic drift → `--lora` only if adapter enrolled
6. Still insufficient → stub stacks fail loud (enroll Z-Image / premium first)

```powershell
& $LocalAiControl image single --preset photo-editorial --prompt "…" --out out.png
& $LocalAiControl image single --asset person-sarosh --prompt "…" --out out.png
& $LocalAiControl image design --brief "…" --out-dir candidates --candidates 8
& $LocalAiControl image enroll --id char-x --type characters --name "X" --refs a.png b.png
& $LocalAiControl image post --image in.png --out out.png --upscale 2
& $LocalAiControl image goldens --skip-existing
```

Quality ladder: new seed → better refs → control/mask → LoRA → model escalate.

## Media Studio visual bible

When `media-studio-generate` calls this file, the prompt comes from
`visual-bible.json` (`brollPlan` / `imagePrompts`), not a free rewrite.

1. Use the bible `prompt` and `subject`. Honor `refuse` verbatim.
2. Problem / outcome / context / texture B-roll only. Not a fake screenshot.
3. Exact logos, numbers, legal lines, and UI chrome stay compositor-set type.
4. Enrolled people use `--asset` (e.g. `person-sarosh`), never a lookalike prompt.
5. Write the still into the **external job workspace**. Bind path + SHA-256 on
   the generation receipt.

Prefer:

`--preset photo-editorial --prompt "<bible prompt>" --out <job>\broll\<beat>.png`

Avoid:

prompting "Acme dashboard with 12.4% conversion" / inventing a product window /
ignoring `refuse`.

### Ops

- Keep Klein resident for image batches; batch groups by stack/bucket/mode/lora.
- `prepare-cache` writes derived refs under each asset `cache/`.
- IP-Adapter is optional, not foundation (prefer FLUX native multi-ref).
- Post-process for size/quality; do not regenerate a good composition just to
  enlarge it.

### Invoke canvas (paint-mask, not Visual Bank)

Visual Bank generation stays `ai.ps1 image` / ComfyUI. For interactive
paint-mask inpaint/outpaint, start Invoke beside it:

```powershell
& $LocalAiControl start invokeai
```

Invoke is on-demand (not in `start all` / `start media`). It uses the same
FLUX.2 Klein 4B BF16 transformer, Qwen3 4B encoder, and F2K VAE as Comfy —
full standalone, not the starter Q4 pack, not Klein 9B. Do not run a heavy
Klein job in Comfy and Invoke at the same time on the 16 GB card.
