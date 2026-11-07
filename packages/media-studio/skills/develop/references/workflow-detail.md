# Workflow detail

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll write narration straight away." | Beats with pictures first, or the script will describe things no one can see. |
| "A bullet list is a script." | A script has a turn. Find it. |
| "The hook can come after the context." | The hook is the first five seconds. |
| "I'll round the number." | Locked facts are locked. |


## 1 Logline and concept check

Write the logline: who, wants what, against what, with what at stake. Then test the concept with three questions and rewrite until all three are yes:

1. Is there a hook that works in five seconds, a pain or a payoff the viewer feels?
2. Does the promise say what the viewer can do or stop doing afterwards?
3. Can you say what is on screen for the opening, in nouns?

## 2 Treatment

150 to 400 words, present tense: the opening image, what changes, the proof, the close. A treatment reads like a trailer in prose. It names the turn, because a piece with no turn is a list.

## 3 Beat sheet

`story/beat-sheet.json`, 3 to 12 beats. Each beat has `id`, `role`, `summary` and `picture`:

- `role` is one of hook, before, tension, reveal, proof, trust, hero, payoff, cta, bridge (`schemas/storyboard.schema.json`).
- `picture` is what the viewer sees, in nouns: "four truck outlines crossed out". If it could be the line again, it is not a picture.
- Exactly one `hero` beat, the moment the piece exists for.
- No role three times in a row; the viewer's question changes every beat.

Shapes that work: problem, stakes, mechanism, proof, call to action (explainer); before, turn, after (story); question, evidence, answer (briefing); setup, escalation, reversal, payoff (documentary or drama).

## 4 Screenplay

`story/screenplay.json` per `schemas/screenplay.schema.json`: `title`, `kind`, `hook`, `audience`, `viewerPromise`, and `scenes` each with `id`, `speaker`, `narration`, and `sceneRole`, `wiifm`, `emphasis` where useful. One scene per beat or per turn of a conversation.

Write for the ear (`../video/references/story.md`): short sentences, concrete nouns, one idea per line, numbers said once. No fluff: no greeting, no recap, no talk about how the film was made. For a dialogue or simulated call, one scene per turn, one voice per character, the spoken thing in the picture and not the speakers (`../video/references/scenes.md`).

Facts are locked: each number, date and name traces to the case's sources. Never invent a metric, a customer or a product behaviour.
