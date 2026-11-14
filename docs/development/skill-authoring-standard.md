# Skill Authoring Standard

Applies to every managed skill under `packages/*/skills/*/SKILL.md` and `overlays/personal/packages/*/skills/*/SKILL.md`. Goal: faster, more accurate, much shorter. Write the current method only; git holds the history.

## 1. Enforced by `Validate-AgentHub.ps1` and `tests/Test-SkillAuthoringStandard.ps1`

- `name` equals the skill's directory and never contains `claude` or `anthropic`.
- `description` states the outcome, then contains `Use when` with the user's intent and concrete triggers. It has at most 300 characters (the host hard limit is 1,024; descriptions share a listing budget across every installed plugin).
- Frontmatter is valid YAML. Quote any value that contains `: `.

## 2. Names

- Use lowercase letters, digits and single hyphens, at most 64 characters.
- The plugin namespaces every skill, so never repeat the plugin name. One or two words.
- Name by what the agent does: verb or gerund first (`audit`, `search-docs`). One pattern per plugin.
- Avoid vague names: `helper`, `utils`, `tools`, `docs`, `data`, `files`.

### 2a. Which of those is enforced

Section 1 rules are hard failures in `tests/Test-SkillAuthoringStandard.ps1`. Section 2 rules are reported only, because renaming a deployed skill is an identity change: it needs its own `retiredFleetSkills` row with `supersededBy`, a version bump through `scripts/Bump-PackageVersion.ps1`, every host projection, and a `RegistryContentHash.ps1` recompute. Promote the ban-list check to a hard failure once the names it reports have been renamed. The verb-first rule is a heuristic in the checker and will stay reported.

### 2b. The plugin namespace must reach every surface

Section 2 assumes the plugin qualifies each skill, so bare names like `plan` are safe. That assumption holds only where the host or installer actually applies the namespace. A surface that lists the bare skill names makes `plan`, `review`, `design` and `build` collide with anything else that wants those words. Before relying on a bare name, check the surface it deploys to: the namespace is part of the name's safety, not decoration. If a surface cannot carry it, qualify the name there.

### 2c. Naming across the other surfaces

The skill name is one of four surfaces. Keep them derived from one identity rather than invented separately.

| Surface | Rule | Example |
| --- | --- | --- |
| Capability id | short lowercase word or hyphen phrase | `context7` |
| Package directory | equals the capability id | `packages/browser` |
| Plugin name / display | `ah-<id>` / `AH-<Title>` | `ah-browser` / `AH-Browser` |
| Skill `name` | equals its directory; one or two words; verb or gerund first; does not repeat the plugin name | `lookup` |
| MCP server id / display | `id` equals the capability id; display `AH-<Title>` | `context7` / `AH-Context7` |

The `ah-*` / `AH-*` rule and the one-version authority across host projections are set in `docs/plans/active/plugin-redesign.md`. A host projection may add host-native fields but must not diverge on `name` or `version`; the allowed extra fields are listed under `canonicalPackage` in `registry/plugin-formats.json`. If a projection needs a field outside that list, amend the list deliberately rather than adding the field quietly.

One capability owns one integration. Where both a package and an MCP server exist for the same thing, name the single owner in `registry/capabilities.json` and `registry/mcps.json` and keep them agreeing.

## 3. Descriptions

- Third person. Outcome first, then `Use when` plus triggers. Put key trigger terms early because truncation cuts the end.
- Name the outcome, never the steps. An agent that reads the steps follows them and skips the body.
- Include the words users actually type, including indirect ones. Add `Not for X; use Y` when a sibling or look-alike exists.
- No XML tags, feature lists or brand lists.

## 4. Body

- Assume a very smart reader. Include only what the agent would not already know; if removing a sentence changes nothing, remove it.
- Under 500 words; ceiling 5 KB and well under 500 lines.
- Keep the core workflow and any decision table inline. Reference files sit one level deep from SKILL.md, each introduced by a `Read when` line; never chain reference to reference.
- Give one default plus one escape hatch, not a menu.
- Match freedom to fragility. Open field: goals and heuristics. Narrow bridge: the exact command, and say not to change it.
- Long workflows get a copyable checklist. Quality-critical work gets a loop: run the validator, fix, repeat. Batch, destructive or high-stakes work: write a plan file, validate it, execute, verify.
- Match the form to the failure:
  - The agent skips a rule under pressure: state the prohibition and the tempting excuse.
  - The output has the wrong shape: give a positive recipe of the parts, in order.
  - The agent omits a required element: make it a required slot in the template.
  - Behavior depends on a condition: use a conditional on something observable, with no `unless` clauses.
- Use the imperative. Give the reason in one clause where it changes judgment. Reserve ALL-CAPS and `MUST` for a genuine hard safety rule.
- Use one term per concept, in plain English. Where style matters, show one concrete input and output.
- No dates, changelogs, `previously`, `now`, `no longer`, `retired`, incident stories or session narrative.
- Use forward slashes in every path, including machine paths such as `D:/Media-Studio`.

## 5. Scripts and tools

- Put deterministic steps in `scripts/`, and say whether to run or read each one. Run through an interpreter: `node scripts/x.mjs`, `python scripts/x.py`.
- Use skill-relative paths. Use `${CLAUDE_SKILL_DIR}` or `${CLAUDE_PLUGIN_ROOT}` only where the path must resolve on Claude Code.
- Scripts solve errors rather than deferring them and print specific messages.
- State required packages. Qualify MCP tools as `Server:tool`.

## 6. Subagents, hooks, commands

- A subagent earns its place only for verbose output or independent review.
- A command is a skill; merge commands into skills.
- A hook is for what must always happen. Add none otherwise.

## 7. Keep

- Every hard safety and owner rule, stated as a current rule.
- Every behavior a script, schema or test depends on. If a script needs a heading, field or phrase, update both sides.

## 8. Verification

`tests/Test-SkillAuthoringStandard.ps1` walks `packages/*/skills/*/SKILL.md` and fails on the §1 rules. It also reports, without failing, skills that lack numbered sections. `Validate-AgentHub.ps1` applies the same §1 rules to every package, including the private overlay.
