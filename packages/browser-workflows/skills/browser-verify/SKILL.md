---
name: browser-verify
description: Use when the task requires an agent to test real user journeys, verify persistence, diagnose failed screens and replay reviewed recipes.
---

Use isolated synthetic fixtures for mutations. Record app revision, starting role and record ID. Exercise the normal UI, wait for a meaningful result, reopen the same record, and compare fields. For multi-role workflows use separate profiles and verify each role independently. Test success, recovery and the expected restricted view as applicable.

### Walkthrough acceptance

For an operator or teaching walkthrough, verify the complete route from each role's actual post-login home. Follow the instructions in a fresh role session without direct links to intermediate screens, hidden navigation, API setup, scripts, or coaching. Every menu opening, selection, scroll, field entry and action in the instructions must be visibly enacted in order. Keep the complete application viewport in view; for each emphasized step or result require a full-viewport frame before and after its highlight. Confirm the synthetic fixture is plausible, consistent and unmistakably synthetic, then reopen the target through the UI and verify persistence. Track instruction-to-screen/action-to-result coverage in an evidence map. Record ambiguous or missing steps, correct the walkthrough and replay the affected path before acceptance. Missing role coverage or a missing independent replay is an explicit verification gap.

Use bsk console and bsk network for passive diagnostics on authorized apps. Keep diagnostics separate from acceptance evidence. For recurring workflows draft a recipe from a completed authorized rehearsal before ending its session. Parameterize data, constrain origins and roles, set requires and until, and require a unique output. Use bsk recipe show and run; on handoff inspect the changed screen. On uncertain effects check persisted state before another run. Human approval of reduced recipe risk belongs to the operator.

BrowserSkill navigation can invalidate element references. Before shared-tab input, synchronize and inspect the current page, then pass the new context ID and observation ID. Re-observe after navigation when a read races a document change. Retry an input only when the tool explicitly confirms it was never dispatched. A busy recorder can belong to another session; wait for it or report contention and leave that session alone.

## Verification after a redesign

Independently replay from each actual role home on the capture build using only the candidate and the documented starting fixture. Check record identity, workspace, permissions, exact UI labels and the observable effect of each consequential action. Verify persisted state by reopening the same record when appropriate. A route, role or outcome mismatch blocks the affected film and needs a fresh replay after recapture.
