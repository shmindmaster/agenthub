# Workflow detail

Choose the film's creative form *before* deciding its beat structure.
Read `../../studio/references/creative-formats.md`. Build the requested structure. Use `schemas/creative-storyboard.schema.json` for free-form scenes. Use the classic structure below when the brief chooses it or the job calls for a verified product demonstration.

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll write narration straight away." | Beats with pictures first, or the script will describe things no one can see. |
| "A bullet list is a script." | A script has a turn. Find it. |
| "The hook can come after the context." | A verified feed demo needs an early hook; a documentary, slow drama or abstract film may intentionally build context or reveal its point later. |
| "I'll round the number." | Locked facts are locked. |


## 1 Logline and concept check

Write the logline: who, wants what, against what, with what at stake. Then test the concept with three questions and rewrite until all three are yes:

1. Is there a hook that works in five seconds, a pain or a payoff the viewer feels?
2. Does the promise say what the viewer can do or stop doing afterwards?
3. Can you say what is on screen for the opening, in nouns?

## 2 Treatment

150 to 400 words, present tense: the opening, how the piece progresses, and the intended close. A short lesson or simple slide sequence can use a brief treatment.

## 3 Beat sheet

`story/beat-sheet.json`, 3 to 12 beats. Each beat has `id`, `role`, `summary` and `picture`:

- `role` is one of hook, before, tension, reveal, proof, trust, hero, payoff, cta, bridge (`schemas/storyboard.schema.json`).
- `picture` is what the viewer sees, in nouns: "four truck outlines crossed out". If it could be the line again, it is not a picture.
- **Verified-demo template:** one hero beat, with a purposeful progression.
- **Flexible story/vision/abstract:** no mandatory hero count or fixed beat
  labels. Use atmosphere, characters, scenes, non-linear concepts, parallel
  storytelling or montage as the project needs. Judge the intended visual
  experience, not a universal checklist.

Possible shapes include a worked example for a lesson, question-and-answer chapters for a briefing, and chronological, character-driven or thematic scenes for a documentary or drama.

## 4 Screenplay

`story/screenplay.json` per `schemas/screenplay.schema.json`: `title`, `kind`, `hook`, `audience`, `viewerPromise`, and `scenes` each with `id`, `speaker`, `narration`, and `sceneRole`, `wiifm`, `emphasis` where useful. One scene per beat or per turn of a conversation.

Write for the ear (`../../studio/references/story.md`): short sentences, concrete nouns, one idea per line, numbers said once. No fluff: no greeting, no recap, no talk about how the film was made. For a dialogue or simulated call, one scene per turn, one voice per character, the spoken thing in the picture and not the speakers (`../../studio/references/scenes.md`).

Represent real people, reported results and current product behavior accurately. Invent characters, dialogue and events when the brief calls for fiction or illustration.
