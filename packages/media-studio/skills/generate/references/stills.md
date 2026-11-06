# Stills: quote, generate, cache

`scripts/generate_stills.py <jobRoot>` turns every `still` scene in `story/picture-plan.json` into a real picture. It quotes by default and spends nothing; `--run` makes the calls.

```text
py -3 scripts/generate_stills.py <jobRoot>                       # quote only
py -3 scripts/generate_stills.py <jobRoot> --run --lane azure-image
py -3 scripts/generate_stills.py <jobRoot> --run --lane runware-image --public-dir <kit>/public
```

- Lanes: `azure-image` (gpt-image-2.5-flare, about $0.007 low and $0.014 medium at 1536x1024, best photographic quality) and `runware-image` (about $0.006, the cheap draft lane). Both were verified by real calls on 2026-11-06. The quote is the measured price times 1.5, never a worst case.
- Each still needs `visual.prompt` (what the photograph shows). Text, logos and real people are always ruled out in the composed prompt; words go in the kit.
- A picture is never bought twice: the cache key is the prompt, size, quality and lane. A changed prompt pays again and the old file moves to `assets/stills/superseded/`.
- `--max-usd` (default 2.00) and `--max-images` (default 24) stop a run before any call when the quote is over.
- Output: `assets/stills/<sceneId>.png`, `assets/stills/manifest.json` and one `image` line per picture in `qa/spend-ledger.jsonl`. `visual.src` in the plan is rewritten to the file.
- A provider safety flag fails that scene only. A missing key fails clearly without a call.
- Layout: a still renders as a full-bleed photo scene (`layout`, `focus`) in the kit; judge the Remotion frame, never the raw PNG.
- A generated clip, not a picture, goes through `irukadark.md`.
