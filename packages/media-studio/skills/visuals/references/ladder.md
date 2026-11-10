# Visual asset ladder

Read this when choosing the picture for a beat. Start at the first row that matches what the line says. Cost and status come from `policy/provider-routing.json`; run `scripts/route_media.py` for today's answer.

| The line says | Show | Kit visual | Source | Cost |
| --- | --- | --- | --- | --- |
| A number, a share, a comparison of amounts | Bars growing from zero, or 100 squares for a percentage | `chart` (`bars`, `waffle`), or `stat` for one hero number | kit | free |
| How something works, a path, a mechanism | Hand-drawn figure, every arrow a verb | `svg`, or `flow` / `layers` / `sequence` / `map` for boxes and lanes | kit, hand-drawn | free |
| Before and after, old and new | Two states side by side | `beforeafter`, `split` | kit | free |
| Steps over time, a deadline, a history | A line with events | `timeline` | kit | free |
| An event, success, a handoff, a warning | A small moving mark: check, pulse, arrow | `lottie` | kit/public/lottie, text-to-lottie skill | free |
| Code, a command, a config | Highlighted lines revealed in order | `code` | kit | free |
| A real product screen | The captured screen | `screen-in-context` | skills/capture, Playwright plus Recast | free |
| A place, person, patient journey, invented interface or world that calls for imagery | Generated realistic or stylized still, including readable designed concept UI when desired | `still` | Governed Azure or tested Runware stills; model-specific alternatives only after adapter, quote and sample review | Quote first; free kit/source footage wins when sufficient |
| A narrative or speculative cinematic moment | Realistic people, invented world, envisioned future UI, action or other generated video; verified functionality shown separately when promised | `broll` | IrukaDark conditional; H3 Lite/Highspeed and Gemini Omni candidates only until governed video adapter, pricing and approval; Higgsfield/Runway frozen | Optional; compare image-to-video vs free Remotion first; see `../../generate/references/provider-cost-quality-routing.md` |
| What other sources say, a topic to learn from | A NotebookLM draft to read, not to ship | none (a draft) | notebooklm-py | free tier |
| A name, a quote, an opening or a close | A card | `hero`, `quote`, `cta`, `chapter`, `lower-third` | kit | free |

**Synthetic subjects and formats:** Media Studio can generate full,
realistic scenes featuring people of any age, fictional families,
patients, clinicians, futuristic interfaces, readable UI, objects,
buildings and invented technologies. Use them as much or as little as
the approved film's format needs. No automatic blur, adult-only
qualification or synthetic-screen ban. Mark factual current-product
claims as verified and speculative capabilities as envisioned. A
product may have an all-synthetic future-vision film without
any existing-product capture. Actor continuity and rights/consent
apply only where relevant (e.g. licensed real-person likeness).
Consult `../../video/references/creative-formats.md` before selecting
visuals. GPT-Image Sunburst has specialist SVG/GIF modes (with
model-specific limitations); Seedream 5.5 is coming-soon as of
2026-11-10, not a callable lane.

## How to decide

1. **Can a drawing show it?** Almost always yes. Draw it.
2. **Is it a number?** Make it a chart. Never leave a number as a sentence.
3. **Does it need to move to mean something?** A path that is followed, a state that changes, a check that lands: animate it with `at` pinned to the word.
4. **Is it a real thing you cannot draw?** A captured screen if it is a product; a generated still if it is a scene. Priced and shown first.
5. **Is the beat only a label?** Then it has no picture. Rewrite the beat.

## Who writes the spec

The rows above say what to show. Who writes each kit spec is a separate choice.

- **A few pictures:** write them straight into the kit.
- **Many pictures, or pictures drawn from a large context** (a codebase, a transcript, a screen recording): design the style and a few worked examples once, then let a small text model fill the rest as specs the kit renders. Read `model-written-specs.md`. `py -3 scripts/route_media.py diagram-spec` says whether the lane is usable.
- This adds to captured screens, narration and the cue sheet; it never replaces them. The model never draws and never supplies a product claim. A captured screen is still captured.

## Mix

Aim for a run that alternates: a picture, a number, a mechanism, a state change. Three text cards in a row is a failure. `check_visual_variety.py` enforces it.
