---
inclusion: fileMatch
fileMatchPattern: ["**/*.ps1", "**/*.psm1", "tests/Test-*.ps1"]
---

# PowerShell in AgentHub repositories

The repository's `AGENTS.md` and `docs/development/agent-change-contract.md` are the authority. Read them first; this file adds only reminders.

- Match the style of a neighbouring script and test before writing a new one.
- Tests print per-check PASS/FAIL lines and end with a `RESULT: N passed, M failed` line and a non-zero exit on failure.
- Test against a temporary directory or a synthetic fixture. Never point a test at a real user profile, credential or production resource.
- Launch child processes windowless and never kill a process by image name.
- Run the repository's validator and the affected `tests/Test-*.ps1` before declaring done.
