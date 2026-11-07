---
name: daytona
description: Creates and manages isolated cloud sandboxes (secure code execution environments with dedicated runtimes) on the Daytona platform. Use when a task needs an isolated runtime, sandbox, secure compute, or Daytona SDK/API/CLI operations. Covers Python, TypeScript, Java, Go, and Ruby SDKs.
---

# Daytona

## Workflow contract

1. Resolve the approved project, image, resource limits, time budget, and artifacts before requesting a sandbox.
2. Create an isolated sandbox with the approved limits, run the requested code, retrieve only the agreed artifacts, then stop or remove the sandbox this run created as authorized.
3. Return the sandbox ID, command exit status, artifact paths and final lifecycle state.
4. If cost or scope is unclear, stop before creating resources. If execution fails, save allowed diagnostics and clean up only the sandbox this run created.

Read when you need exact setup, SDK commands, limits or lifecycle details. [Daytona SDK workflows](references/sdk-workflows.md)
