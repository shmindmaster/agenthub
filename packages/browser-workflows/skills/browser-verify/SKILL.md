---
name: browser-verify
description: Use when the task requires an agent to test real user journeys, verify persistence, diagnose failed screens and replay reviewed recipes.
---

Use isolated synthetic fixtures for mutations. Record app revision, starting role and record ID. Exercise the normal UI, wait for a meaningful result, reopen the same record, and compare fields. For multi-role workflows use separate profiles and verify each role independently. Test success, recovery and the expected restricted view as applicable.

Use bsk console and bsk network for passive diagnostics on authorized apps. Keep diagnostics separate from acceptance evidence. For recurring workflows draft a recipe from a completed authorized rehearsal before ending its session. Parameterize data, constrain origins and roles, set requires and until, and require a unique output. Use bsk recipe show and run; on handoff inspect the changed screen. On uncertain effects check persisted state before another run. Human approval of reduced recipe risk belongs to the operator.

BrowserSkill navigation can invalidate element references. Before shared-tab input, synchronize and inspect the current page, then pass the new context ID and observation ID. Re-observe after navigation when a read races a document change. Retry an input only when the tool explicitly confirms it was never dispatched. A busy recorder can belong to another session; wait for it or report contention and leave that session alone.
