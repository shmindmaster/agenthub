---
name: repo-onboard
description: Use when entering an unfamiliar repository or when its coding-agent instructions, validation commands, deployment context, or secrets posture are missing or unclear.
---

# Onboarding an unfamiliar repo

If the executing host supports a read-only exploration subagent, delegate the discovery pass to a
fresh context. Otherwise, execute the same
discovery pass directly. The worker must read the repository's current
artifacts for this task and may not assume prior session context: package
manifests/lockfiles (stack + package manager), app/package boundaries in a
monorepo, `package.json` scripts or Makefile targets for the real
lint/test/build commands, Dockerfile/deployment config, `.env.example` for
required env vars, README, applicable repository instructions, docs, and the
executing host's managed configuration.

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
