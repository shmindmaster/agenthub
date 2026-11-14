# Visual bible

Read this when designing a scene or reviewing one. Distilled from the nicobailon/visual-explainer skill (MIT) and fitted to the 1600x1000 Briefing kit. The rules are borrowed; the plugin is not installed, because it targets web pages and brings its own Chrome, ffmpeg and voice stack.

## Content to figure

- One claim per figure. If a picture needs "and", it is two pictures.
- Draw the mechanism, not the name. Every arrow gets a verb.
- Every number gets a picture. Bars start at zero; small multiples share one scale.
- Cases become small multiples, not paragraphs.
- Give every fact a place in a figure before it becomes a sentence.
- Encode state in form, never colour alone: a risk is also an X or a dashed line.
- Labels sit on the data, not in a legend.
- Headings state the takeaway ("Penske declined all four trucks"), not the topic ("Equipment").

## Look

- Quiet ground, one signal: about 90% neutral, the accent on 10% or less.
- One dominant element per screen. No card inside a card. No three identical blocks in a row.
- Anti-slop, never: system-font-only type, violet or fuchsia accents on dark neon, glassmorphism, gradient text or blobs, clip-art, mascots, emoji markers, everything centred, an accent bar on a rounded card, `01 02 03` when order does not matter.
- Line weights: 1, 1.75 and 3. Use the kit's `MARK` colours for good, risk and emphasis, so the film reads as one hand.

## Video sizing

- Body text 24 px or more, labels 15 px or more, headings 48 to 88 px at 1600x1000. If a visual is small in frame, raise `visualScale` (chart about 1.3, svg and a drawing that does not fill its viewBox about 1.5, flow 1.4).
- Keep the bottom 112 px clear for captions.
- Settle each reveal within about 1.5 seconds. Add slow ambient motion so no frame is ever dead.
- The picture changes with every sentence; no scene holds one frozen picture past eight seconds.

## Review rule

Render, read the frames, fix, re-render, before any voice spend. A frame where you cannot say what the line is about at a glance has failed.
