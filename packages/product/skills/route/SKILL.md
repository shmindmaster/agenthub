---
name: route
description: Selects the specialist, skills, tools and checks for the repository in front of you. Use when a task starts, or when choosing which skill, tool or review a change needs. Not for writing the change; use build.
---

# Route

Runs standalone: start from the bare repository; no earlier files are needed.

## Checklist

- [ ] Read the repository root instructions and `git status`. Work in one repository only.
- [ ] Name the product from those instructions. If they name a deferred alternative, follow the current runtime, not the alternative.
- [ ] Pick one lane. A UI journey uses `audit` then `design`. An accepted change uses `build`. A finished change uses `verify`. A demo uses `demo`. A structure or quality scan uses `engineer`.
- [ ] Load a tool only when that lane needs it. Keep repository knowledge in the checkout instructions and the wiki already configured on this host. Do not send a private repository through a public wiki.
- [ ] Keep the account model default. Do not start a GPU, download weights, or enable a model that is switched off.
- [ ] State the lane, the checks the repository names, and anything still blocked.

Read when the checkout is a portfolio product and you need its domain, boundary and check command: [portfolio routes](../../../../docs/architecture/portfolio-routes.md).

Next: the skill named in the lane you picked.
