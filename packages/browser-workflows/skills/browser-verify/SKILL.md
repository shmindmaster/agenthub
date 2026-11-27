---
name: browser-verify
description: Use when the task requires an agent to test real user journeys, verify persistence, diagnose failed screens and replay reviewed recipes.
---

Use isolated synthetic fixtures for mutations. Record app revision, starting role and record ID. Exercise the normal UI, wait for a meaningful result, reopen the same record, and compare fields. For multi-role workflows use separate profiles and verify each role independently. Test success, recovery and the expected restricted view as applicable.

Use bsk console and bsk network for passive diagnostics on authorized apps. Keep diagnostics separate from acceptance evidence. For recurring workflows draft a recipe from a completed authorized rehearsal before ending its session. Parameterize data, constrain origins and roles, set requires and until, and require a unique output. Use bsk recipe show and run; on handoff inspect the changed screen. On uncertain effects check persisted state before another run. Human approval of reduced recipe risk belongs to the operator.
