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
| A place, an object, a mood no diagram can carry | A generated still, with text added in the kit | `still` | Azure image | Azure credit, priced first |
| A cinematic moment | A generative video hero shot | `broll` | Higgsfield, Runway, Vertex: frozen | owner approval first |
| What other sources say, a topic to learn from | A NotebookLM draft to read, not to ship | none (a draft) | notebooklm-py | free tier |
| A name, a quote, an opening or a close | A card | `hero`, `quote`, `cta`, `chapter`, `lower-third` | kit | free |

## How to decide

1. **Can a drawing show it?** Almost always yes. Draw it.
2. **Is it a number?** Make it a chart. Never leave a number as a sentence.
3. **Does it need to move to mean something?** A path that is followed, a state that changes, a check that lands: animate it with `at` pinned to the word.
4. **Is it a real thing you cannot draw?** A captured screen if it is a product; a generated still if it is a scene. Priced and shown first.
5. **Is the beat only a label?** Then it has no picture. Rewrite the beat.

## Mix

Aim for a run that alternates: a picture, a number, a mechanism, a state change. Three text cards in a row is a failure. `check_visual_variety.py` enforces it.
