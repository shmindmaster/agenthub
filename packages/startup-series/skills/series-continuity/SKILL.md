---
name: series-continuity
description: Use when locking characters, voice IDs, avatars, aliases, motifs, or diagram conventions across episodes before render.
---
# Series Continuity

## Owns

characters, voice IDs, avatar refs, local-model seeds/LoRAs, costumes, colors,
UI styling, Slack/company/customer aliases, music motifs, running jokes,
recurring animations, technical terminology, diagram conventions.

## Character package layout

```text
characters/<slug>/
  character.yaml
  reference/
  voice.yaml
  avatar/
  prompts/
  continuity.md
```

## Template

Copy `characters/_template/` for new cast. Never change voice ID / avatar mid-season
without an explicit continuity note in `continuity.md`.

## Cross-episode check

Before render: same fictional name, avatar, voice, personality, Slack icon treatment.
