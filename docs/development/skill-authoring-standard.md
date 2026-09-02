# Skill Authoring Standard

Applies to every managed skill under `packages/*/skills/*/SKILL.md`. Keeps
skills discoverable, unambiguous about their own scope, and consistent enough
that an agent can trust the shape of one it has never read before.

## 1. Identity

- Frontmatter `name` equals the skill's own directory name
  (`packages/<pkg>/skills/<name>/SKILL.md` → `name: <name>`). A mismatch
  breaks host-side skill discovery, which resolves by directory.
- Frontmatter `description` starts with `Use when` and names concrete
  triggers — task shapes, file types, or keywords an agent would actually
  see — not a vague category. `Use when reviewing a Supabase migration` beats
  `Use for database work`.

## 2. Structure

- Body organized into numbered sections (`## 1. ...`, `## 2. ...`), so a
  reader or a later edit can address "section 3" unambiguously.
- Where the skill prescribes style or wording, show concrete `Prefer:` /
  `Avoid:` (or `Good:` / `Bad:`) example pairs rather than describing the
  preference only in the abstract.
- A skill that produces or hands off an artifact (a document, a render, a
  registry entry, a deployed file) closes with a final-check list the agent
  runs before calling the work done.

## 3. Scope

- If a skill's domain could be confused with a neighboring skill — written
  vs. spoken, short-form vs. long-form, draft vs. delivery — state the split
  explicitly and name the other skill by id. Never leave the boundary
  implicit ("this is obviously just the writing part").
- A skill that hands off to another skill for part of the work says so by
  name near the top, not buried mid-document.

## 4. Verification

`tests/Test-SkillAuthoringStandard.ps1` walks every `packages/*/skills/*/SKILL.md`
and asserts the two identity rules (§1) as hard failures — they are
mechanically checkable and load-bearing for discovery. It reports, but does
not fail on, skills that lack numbered sections (§2), since older skills
predate this standard and a blanket rewrite is its own separate task. Treat a
reported gap as a backlog item for that skill's own next edit, not something
this checker's presence obligates an immediate fix for.
