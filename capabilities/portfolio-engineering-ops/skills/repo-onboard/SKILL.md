---
name: repo-onboard
description: Analyze an unfamiliar repository (stack, package manager, apps, validation commands, deployment, secrets posture, canonical docs) and propose or repair its minimal configuration for the executing host. Use when entering a repo for the first time or when its repository-instruction setup looks thin or missing.
---

# Onboarding an unfamiliar repo

Delegate the discovery pass to the `explorer` subagent: package
manifests/lockfiles (stack + package manager), app/package boundaries in a
monorepo, `package.json` scripts or Makefile targets for the real
lint/test/build commands, Dockerfile/deployment config, `.env.example` for
required env vars, README, applicable repository instructions, docs, and
the executing host's managed configuration.

## Minimal config to propose

- If the canonical repository instructions exist and are substantive: add a
  thin root host-native instruction bridge when the executing host's
  supported format needs one, plus at most 3-5 lines of host-specific notes.
  Do not duplicate the canonical instructions into the bridge.
- If the canonical repository instructions are missing or too thin (a few
  lines) to be a real guide: that's the actual gap — author real content
  there first (stack, local commands, PR conventions, repo shape), THEN add
  any required host-native bridge. A bridge to an empty file helps no one.
- Only add package-level host-native instruction/rule files for a monorepo
  package whose conventions genuinely differ from the root (different
  language, different test runner, different deploy target) — not as a
  matter of course for every subdirectory.
- Never invent build/test commands — cite the ones actually in
  package.json/Makefile/CI config.

## Output

Propose the exact files/diffs, don't apply them silently — this skill
produces a plan; use `issue-to-pr` or a direct commit (with the user's
go-ahead per that repo's own PR conventions) to land it.
