# Using Product Demo Studio against any product

One plugin, any product, any supported coding agent. The plugin carries no product-specific values; a config file in the target repository supplies them all.

## 1. Install

The plugin ships `.claude-plugin/plugin.json`. Four hosts read that layout natively — Factory translates it on cache copy, VS Code resolves it as a documented fallback, Copilot shares the format, and Qwen Code converts it on install. Nothing extra is needed for those.

`policy/host-manifests.json` records every mapped host, whether it ships a manifest or auto-detects, and where that behaviour was read from. Run `node scripts/validate-host-manifests.mjs` after any change to that inventory.

**Trim `mappedHosts` to the hosts you actually run.** Eighteen entries with seven marked `documentation-not-read` is aspirational parity for a distributed plugin. Delete the rows you do not use rather than resolving them.

## 2. Configure the target repo

```
cp product-demo-studio.config.example.yaml <product-repo>/product-demo-studio.config.yaml
```

Fill in `environment.url`, `environment.reset`, `output_root`, brand tokens, and the voice profile. The run stops rather than guessing any of them.

`product:` is free text. There is no fixed vocabulary and no per-product file inside the plugin — that is the property that lets one plugin serve every product.

**`environment.reset` is the one real prerequisite.** Without a reset-and-reseed path, `deterministic-resettable` cannot be evidenced and every assessment returns `BLOCKED`. It is the first thing to build in a repo that lacks one.

## 3. Calibrate before trusting a verdict

```
node scripts/verify-fixtures.mjs        # checksums, decode, cross-validation
# then load pipeline/commands/demo-calibrate.md (not a slash command)
```

Two fixture sets ship with the plugin: five defective web applications for demo-worthiness, six defective masters for craft. **Both run with no product and no seeded environment**, so the gates are provable on day one.

If a known-bad fixture passes, or either `clean-pass` fails, every verdict since the last successful calibration is suspect. Diagnose the rubric, the reviewer brief, the model, then the input contract. Never adjust a fixture to match a result.

## 4. Run

Assessment only, no capture:

Load `pipeline/commands/demo-assess.md` with `--repo <path>`.

Produces a demo-worthiness verdict per candidate episode and a Product-Readiness Feedback Report where any candidate failed. **This is the highest-value half of the system and it needs no capture, narration, or render.** A report naming the specific reasons a product cannot yet carry a demo, with a buildable fix for each, is a deliverable in its own right.

Public full pipeline: media-studio `/video` with kind `product-screencast`. Engine procedure: `pipeline/commands/demo-video.md`.

Or describe the intent in plain language — the `product-demo` router recognizes it, confirms the repo and environment, and dispatches. See [EXECUTION.md](EXECUTION.md) for a worked setup.

## 5. The rubric is the same everywhere

Eleven criteria, identical for every product. A legal SaaS and a healthcare SaaS both need a clear outcome, bounded waits, and a hero moment.

The plugin ships no rubric overlays. `verticalOverlay` is `null` in every review report and calibration record, and the schema already treats that as the normal case. If a specific product genuinely needs a criterion the base rubric lacks, supply an overlay from that repo and point `rubric_overlay` at it — it may only add criteria or tighten thresholds, never remove or weaken one. Its hash is then recorded and must match between calibration and review.

Resist the urge to fork the rubric per product. A rubric that can be narrowed per engagement is a rubric that will be narrowed to fit whatever needs shipping.

## What running this against several products buys you

A single-product demo pipeline is over-engineered. Several products, each needing episodes that stay current as the UI moves, is exactly the case where scripted capture and a shared gate pay for themselves: fix the hook once, re-render the whole library.

Track across runs, per product and pooled:

- **Per-criterion failure rate.** A criterion that has never failed is decoration, not a gate. Either remove it, or find out why it is not being evaluated.
- **Classification accuracy** — how often `capture-fixable` actually was fixable at capture. This is the assessor's own quality signal and the input to tuning its boundary. Repeated late craft failures on episodes marked `CONDITIONAL` mean the boundary has slipped.
- **Calibration history.** The only evidence the gates were working on any past date.

## Where the loop closes

When you own the products the demos are about, a `product-fix-required` verdict goes straight into your own backlog and comes back fixed. Most two-outcome systems hand a FAIL to someone who will not act on it. That closed loop is what makes the machinery worth its cost — so write the feedback report for your own engineers: repo paths, component names, your ticket IDs. Less explaining to a stranger, more buildable.
