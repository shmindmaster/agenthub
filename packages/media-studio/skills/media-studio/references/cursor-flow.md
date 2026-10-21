# Cursor and flow

The cursor is the viewer's eye. It moves only to the next thing the narration names, in one direction per beat,
and it rests when the line rests. Nothing on screen moves that the narration is not about. The eye is led along
one flow; it is never asked to go back.

`direction.md` plans it, `media-studio-capture` performs it, `scripts/validate-pointer-path.mjs` measures it
from the capture receipt, and `media-studio-qa` refuses a take that breaks it.

## Eye path per scene

Every screen scene (and every static scene with a guided highlight) has a planned eye path, recorded on the
storyboard beat and in `direction.json`:

```json
"eyePath": { "start": "the Today list, wide", "move": "down the list to the Carter renewal row", "rest": "the 12-of-176 units line, punched in" }
```

- `start`: where the eye already is when the line begins (usually where the previous beat rested).
- `move`: **the one move** this beat makes, toward the thing the line names. One direction. One target.
- `rest`: where the eye holds while the result is named and held (≥ 1.5 s).

A beat that needs two moves is two beats. A beat with no named target has no cursor motion at all.

## The rules the gate measures

| Rule | What fails | Default allowance |
| --- | --- | --- |
| Purpose | A pointer move that is not followed by a named click, point or typing (wandering) | `maxUnnamedMoves` 0 |
| One direction | A turn sharper than 120° between consecutive moves or approaches: flicking, up-and-down, going back the way it came | `maxReversals` 0 |
| Shortest path | Pointer travel more than 1.35× the straight polyline through the named targets | `maxTravelRatio` 1.35 |
| Scroll once | A scroll that changes direction, or scrolls past and returns to where it started before the next named action | `maxScrollReversals` 0 |

The allowance lives on the cue plan (`story/cue-plan.json` → `beats[id].pointer`) or the storyboard beat
(`pointer`) and loosening a default requires a `reason`. A take over its allowance is re-recorded; it is not
excused in the review.

## How to perform it (capture)

- One `h.approach` / `h.click` / `h.pointAt` per named target, from wherever the pointer already is. Never
  pre-position the pointer, never park it off to the side, never circle a control.
- Scroll with one `h.smoothScroll` toward the named element and stop there. If the element is above, scroll up
  once; do not overshoot and come back. If you are unsure where it is, find out before the take (exploratory
  looks are not recorded).
- Static scenes (dashboards, diagrams, architecture): `h.pointAt` the exact element as it is named, hold, then
  the next named element. No sweeping, no "look around".
- Typing: click the field, type at the human cadence, stop. The cursor does not leave the field until the
  result is named.
- The result holds with the cursor at rest. The next beat's approach starts from that rest point.

## What the eye must never be asked to do

- Follow a cursor that moves while nothing is being named.
- Read a build chip, version chip, environment badge or debug label. Nothing on screen says which revision this is.
- Watch the same control twice because the pointer went past it.
- Chase a scroll that overshot.
