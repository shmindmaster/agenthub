# Story craft (viewer-facing films)

Load this with `engagement.md` for every **viewer-facing** media-studio job that is not a product screencast. Product screencasts stay on the PDS story-experience gate. Series episodes still use `story-series` for bible/continuity; this file is the reusable tension craft those episodes and every other film share.

A scene is a designed viewer experience, not narration with a slide attached.

## Dramatic spine

Use this order unless the brief is a single-beat clip (then: question → reveal → takeaway):

```text
Question → Stakes → Wrong intuition → Complication → Reveal → Demonstration → Implication → Takeaway
```

Map onto scenes with `sceneRole`:

| Role | Viewer job |
| --- | --- |
| `hook` | Payoff or pain in 5–8s. No greeting, logo, agenda. |
| `before` | Felt current cost. The viewer recognizes Monday. |
| `tension` | The normal process breaks. Open a loop. |
| `reveal` | Show the change. Picture first, name it after. |
| `proof` | Hard case, number, or evidence. One claim. |
| `trust` | Human control, limit, or what it does not do. |
| `hero` | Exactly one protected hero moment per film. |
| `payoff` | Close the loop. Hold. |
| `cta` | One next step. Designed last frame. |
| `bridge` | Only when the cut would otherwise confuse. |

Conflict logic (same machinery as story-series, without becoming an episode):

```text
goal → obstacle → escalation → complication → reversal → payoff
```

If a stretch has no obstacle or reversal, it is a lecture. Cut it or give it stakes.

## Scene contract (writer + storyboard)

Every viewer-facing scene sets:

- `sceneRole`
- `viewerQuestion`
- `wiifm` (outcome or identity, not a feature name)
- `story.beforeState` / `story.tension` / `story.openLoop` / `story.payoff` as they apply
- exactly one `emphasis`
- `truth`

The film has:

- one `hook`
- one `emotionalTarget`
- one `viewerPromise`
- **exactly one** `heroMoment: true`

Prefer:

`Can it actually handle the messy case?` / `I don't spend Monday fixing this by hand.`

Avoid:

`Welcome to the fleet briefing.` / `Next we will cover architecture.`

## Explainer path

`technical-explainer` still owns comprehension (core idea → plain explanation → analogy → example → misconception → takeaway). For a **film**, wrap that explanation in the dramatic spine above. Do not ship the comprehension block as sequential slides.

## Filler test

A beat that is not hook, before-state, tension, reveal, proof, trust, hero, required transition, or CTA is filler. Kill it.
