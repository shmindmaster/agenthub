# UI standard

Rules for the look and feel of a web interface, for `design` to specify and `verify` to check. Adapted from OpenAI's published frontend guidance, trimmed to what the other product skills do not already say.

**Precedence.** A repository's own design system, tokens, components and `AGENTS.md` win over every rule here. Where a rule below conflicts with them, follow the repository and name the exempted rule in the contract or verdict. The [portfolio standard](portfolio-standard.md) wins on architecture, truthful claims and static marketing sites. Already covered elsewhere, so not repeated: every state, reserved space for late content, container queries, WCAG 2.2 AA, focus and keyboard, no new library to restyle one flow.

## Contents

- Audience and density
- Controls
- Screens and copy
- Layout and type
- Landing and hero pages
- Games and 3D
- Checks

## Audience and density

- Judge the audience first. Operational tools (SaaS, CRM, admin, clinical or billing workbenches) are quiet, dense and work-focused: no oversized heroes, no decorative cards, no marketing copy inside the app.
- Common workflows are efficient and complete from first action to confirmation. Games and creative tools may be expressive.
- Build the usable screen first. Do not open with a landing page unless the request asks for one.

## Controls

Pick the control that matches the job:

| Job | Control |
|---|---|
| Tool or action | Icon button; add a tooltip if the icon is not universal |
| Colour | Swatch |
| Mode or view switch | Segmented control or tabs |
| On or off | Toggle or checkbox |
| Number | Slider, stepper or input |
| One of many options | Menu |

- Use a text button only for a clear command ("Save", "Send invite"). Use a familiar icon instead of a text pill.
- Use the repository's icon library; if it has none, use lucide.
- Cards have a radius of 8px or less and are never nested. Page sections are full-width bands, not floating cards.

## Screens and copy

- Build every view a user expects, with the states `design` lists.
- Do not put text in the interface that explains the feature, its shortcuts or its styling. Labels, empty and error messages, tooltips and legally or truthfully required notices (synthetic-data labels, compliance text) stay.
- Use a proven library for rules engines, physics and parsers; do not hand-roll them.

## Layout and type

- Text fits its container and never overlaps another element, at every viewport.
- Type size matches the container: compact headings in panels, display sizes only on a landing page.
- Hover, focus, loading and a changing label do not change any element's size or move its neighbours.
- No font size set in viewport units. Letter spacing is 0.
- Do not paint the whole interface in one hue family (a purple or blue gradient, beige, dark slate, or brown and orange). No decorative orbs, blurs or bokeh.

## Landing and hero pages

Only when the request asks for one; marketing sites stay static.

- The first screen is a real image, a generated bitmap or an immersive scene, full-bleed, with the text on it and not inside a card. No split card layout, no gradient or SVG stand-in.
- The brand, product or place is a signal in the first viewport. The H1 is its name or a literal offer, not a slogan.
- The next section peeks above the fold on every viewport.
- Images show the real product, place or people. Avoid dark, blurred or stock mood images.

## Games and 3D

- Use Three.js, full-bleed, unless the repository already uses another engine.
- Prove the scene on a desktop and a mobile viewport, with screenshots and canvas pixel checks.

## Checks

`verify` runs these. Report the command or measurement and its output.

Static, from source: `node scripts/check-ui-rules.mjs <repo>` from the plugin root. It flags `viewport-font`, `letter-spacing` and `card-radius` (a card rule or class with a radius above 8px). Skip a rule with `--skip <rule>` only for a repository whose design system requires it.

Measured in the running app with the repository's Playwright, at 375, 768 and 1280 px wide:

| Check | Fails when |
|---|---|
| Text fit | A visible element's `scrollWidth` or `scrollHeight` exceeds its box and it is not an intended scroll area |
| No overlap | Two text or control boxes intersect and neither is layered by design |
| Stable size | A control's bounding box differs between rest, hover, focus, loading and changed label |
| Peek | On a landing page, the next section's top is not above the viewport bottom |
| Canvas, per viewport | A pixel sample is a single colour; the subject touches the canvas edge; two frames 500 ms apart are identical in a moving scene; a model or texture request fails; the console shows an error |

Judged by the reviewer, with the evidence recorded: control choice, density for the audience, one-hue palette, hero imagery showing the real thing, H1 naming the product or offer.
