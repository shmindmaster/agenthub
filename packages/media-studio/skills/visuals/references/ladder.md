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
| A place, a prop, or fictional adult office context no diagram can carry | An approved generated still, with text/branding added in the kit; never an invented app screen | `still` | Governed Azure or tested Runware stills; model-specific alternatives only after adapter, quote and sample review | Quote first; free kit/source footage wins when sufficient |
| A non-claim cinematic context moment | Optional 4–8s generic adult/workplace b-roll; real UI immediately before/after | `broll` | IrukaDark conditional; H3 Lite/Highspeed and Gemini Omni candidates only until governed video adapter, pricing and approval; Higgsfield/Runway frozen | Optional; compare image-to-video vs free Remotion first; see `../../generate/references/provider-cost-quality-routing.md` |
| What other sources say, a topic to learn from | A NotebookLM draft to read, not to ship | none (a draft) | notebooklm-py | free tier |
| A name, a quote, an opening or a close | A card | `hero`, `quote`, `cta`, `chapter`, `lower-third` | kit | free |

**Humanization guardrail:** a fictional adult office coordinator can make
a buyer problem relatable. Marketing specs require explicit
`broll.actor` provenance (`fictional-adult`, no real identity, no
patient/minor). Keep that visual short and do not let the generated shot
pretend to show ABACare results. Real screens, values and authorization
behavior stay under captured UI receipts. GPT-Image 2.6 Sunburst can
produce SVG and GIF output, but those specialty modes cannot take
reference images and the SVG authoring call has its own token charge;
prefer designed SVG/Lottie/Remotion unless there is a clear creative need.
Seedream 5.5's advertised layer extraction is **coming-soon**, not a
callable production lane as of 2026-11-10.

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
