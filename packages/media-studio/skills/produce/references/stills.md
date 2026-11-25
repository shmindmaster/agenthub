# Stills: quote, generate, cache

`scripts/generate_stills.py <jobRoot>` turns every `still` scene in `story/picture-plan.json` into a real picture. It quotes by default and spends nothing; `--run` makes the calls.

```text
py -3 scripts/generate_stills.py <jobRoot>                       # quote only
py -3 scripts/generate_stills.py <jobRoot> --run --lane azure-image
py -3 scripts/generate_stills.py <jobRoot> --run --lane runware-image --public-dir <kit>/public
py -3 scripts/generate_stills.py <jobRoot> --lane openai-image          # quote; OPENAI_API_KEY, ABACare grant
```

- Lanes: `azure-image` (gpt-image-2.5-flare, about $0.007 low and $0.014 medium at 1536x1024, best photographic quality) and `runware-image` (about $0.006, the cheap draft lane). Both were verified by real calls on 2026-11-06. The quote is the measured price times 1.5, never a worst case.
- `openai-image` (OpenAI direct `gpt-image-2.6-flare`, or `-sunburst` through `MEDIA_STUDIO_OPENAI_IMAGE_MODEL`) is chosen automatically only for ABACare jobs while the OpenAI grant lasts (to 2026-11-26) and by name for anyone else; after the grant an ABACare job is refused, not billed. It takes `quality` low to `max`, and `visual.complexity` low, medium or high (omitted means the API default, high). Prices are $5 text in, $8 image in and $30 image out per 1M tokens, recorded from the real usage; the quote is a planning estimate with a 1.5x margin. Azure has no 2.6 deployment, so every other entity keeps `azure-image`. It makes PNG stills only: SVG, animated GIF and markup edits are API features this kit does not drive, and exact diagrams and screens stay in the kit.
- Each still needs `visual.prompt` (what the photograph shows). Text, logos and real people are always ruled out in the composed prompt; words go in the kit.
- A picture is never bought twice: the cache key is the prompt, size, quality and lane. A changed prompt pays again and the old file moves to `assets/stills/superseded/`.
- `--max-usd` (default 2.00) and `--max-images` (default 24) stop a run before any call when the quote is over.
- Output: `assets/stills/<sceneId>.png`, `assets/stills/manifest.json` and one `image` line per picture in `qa/spend-ledger.jsonl`. `visual.src` in the plan is rewritten to the file.
- A provider safety flag fails that scene only. A missing key fails clearly without a call.
- Layout: a still renders as a full-bleed photo scene (`layout`, `focus`) in the kit; judge the Remotion frame, never the raw PNG.
- A generated clip, not a picture, goes through `irukadark.md`.
