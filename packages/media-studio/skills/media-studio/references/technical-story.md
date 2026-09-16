# Technical story (product / engineering change films)

Load this for any film whose subject is a product or engineering change — a fix, a new capability, an incident, a behavior nobody expected. Set `programForm: technical-story` on `job.json`. Kind is `product-screencast` when the picture is a running product (the normal case), `explainer` when no product can be shown. Screencast craft, capture, and QA gates stay with `killer-demo-production-guide.md` plus `product-picture.md` (WebM + Recast; overlays and code cards serve the product, they do not replace it). This file is the **story shape and markup rules** for this form. It does not replace `story-craft.md` — it is the concrete instance of that spine for this subject.

Guiding principle, in the owner's words:

> Show me what happened. Explain why it happened. Show me where it happens. Tell me why I should care.

## 1. What it is

- A **short technical story**, 5–8 minutes. A mini technical documentary, not a tutorial.
- Evidence (screens, code, logs, PRs, diagrams) **serves the story**. It is never the story.
- One change per film. If a second change needs its own "what is actually happening", it is a second film.

Prefer:

`A ticket arrives, the agent replies, and the Zendesk tag never lands. Why?`

Avoid:

`In this video we walk through the tool-service, the integration layer, and the new settings page.`

## 2. Structure (target timestamps)

| Time | Beat | What the viewer gets |
| --- | --- | --- |
| 0:00 | **Hook** — what changed and why anyone should care. The problem, not the UI. 10–20 s. | A reason to stay |
| 0:20 | **Real product scenario** with realistic synthetic data | Recognizes the situation |
| 1:00 | **The weird / problematic behavior** | Tension: something is off |
| 1:45 | **What is actually happening** — a small flow overlay (e.g. `User → Web App → Tool Service → Integration → Zendesk`) | The mechanism, located |
| 2:30 | **Code reveal** — only the 5–20 lines that matter, one highlighted section at a time. Sequence: product behavior → question → code → explanation → product result | Where it happens |
| 4:00 | **The fix / change** — before/after | What moved |
| 5:00 | **Replay the product** | Proof it now behaves |
| 6:00 | **What this means** — implications, edge cases, uncertainty, what becomes possible | Why they should care |

Timestamps are targets, not a grid. A 5-minute film compresses every beat; it does not drop one. The hook and "what this means" are the two beats most often cut and the two that decide whether anyone remembers the film.

## 2b. Cast (multi-voice Q&A)

Host is Sarosh (~70–80% of lines, `qwen-clone` style bank). Stakeholder questions use Remotion labeled question cards + `qwen-role`:

| Speaker | Role on card | Typical beat |
| --- | --- | --- |
| `ryan` | Engineering skeptic | Mechanism / correctness objection |
| `vivian` | Product · CSM | Customer / handoff consequence |
| `aiden` | Ops · Audience | “What do I do Monday?” |

Set `speaker` on the scene; leave host scenes as `sarosh` or omit. See `scene-archetypes.md` § Stakeholder Q&A.

## 3. Rules

1. **Visual markup, aggressively.** Box the important element, dim the rest, arrows for cause → effect, zoom, labels such as `User action`, `Webhook`, `DB write`, `Async job`. When the story crosses systems, put a tiny flow diagram on screen. The compositor's annotation layer (`kit/screencast/render-overlay.mjs`) is the tool; `media-director` decides the markup per beat.
2. **Explain what → why → consequence.** Every code or log beat answers all three. A beat that only says *what* is a screenshot with narration.
3. **Before/after comparisons.** The fix beat is a comparison, not a description of the new code.
4. **Small moments of tension.** "It should have worked here — it did not." Let the viewer feel the gap before you close it.
5. **Translate technical consequences into human consequences.** A dropped webhook is a customer waiting; a retry storm is a bill; a missing field is an agent who cannot act.
6. **Meaningful visual change every 5–15 s, never manufactured.** A cut, a build, a highlight move, a new box — because the story moved, not because a timer fired.
7. **Never narrate what the viewer can already see.** Name the result after it appears. Read the log line only if the reading adds meaning.
8. **Code reveal discipline.** Real source excerpt, real line numbers, the commit named on the card (`kit/screencast/render-code.mjs`). One highlight band at a time. Never a full-file scroll.
9. **Local Docker with synthetic data.** Create the failure, the retry, the edge case, the persona locally. Never record live production or real user data (`PIPELINE_BLOCKED`).
10. **Never make an addendum video.** If a section is wrong, re-record that section and re-cut the master. A correction clip is a defect.

## 4. Crew mapping

| Skill | This form adds |
| --- | --- |
| `media-writer` | Hook = problem, not feature. Every technical beat carries what/why/consequence and its human consequence. `truth: FACT` on every code/log claim. |
| `media-storyboard` | Beats follow §2. Each code/log/diagram beat names the markup (`box`, `dim`, `arrow`, `label`, `flow`) and the single highlight. Before/after is one beat with two states. |
| `media-director` | Specifies the overlay per beat for the compositor; picks the 5–20 lines; sets the flow-diagram nodes when systems are crossed. |
| `media-studio-capture` | Local prod-sim, synthetic personas, deterministic replays; product-specific operator notes live in that skill's `references/`. |
| `media-studio-compose` | Applies overlays per segment (`overlay` hint), code cards, flow cards; manifest hints `trimStart`, `trimEnd`, `speed`, `skip`, `fit`. |
| `media-studio-qa` | product-picture plus: hook is a problem; one highlighted section at a time; no narrated chrome; no addendum. |

## 5. Final check

- [ ] Hook states the problem and why anyone cares within 20 s
- [ ] Flow overlay appears before the code reveal when systems are crossed
- [ ] Code beats: 5–20 lines, one highlight at a time, product behavior → question → code → explanation → product result
- [ ] Fix beat is before/after; product replay follows
- [ ] "What this means" beat exists, including uncertainty and edge cases
- [ ] Every technical consequence has a human consequence
- [ ] Visual change every 5–15 s, all motivated; nothing narrated that is already visible
- [ ] Synthetic local data only; no addendum clip
