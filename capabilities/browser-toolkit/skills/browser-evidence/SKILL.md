---
name: browser-evidence
description: Capture controlled live-browser evidence for an authorized product workflow using a dedicated Chrome profile. Use for accessibility snapshots, screenshots, console and network records, Lighthouse, performance traces, and reproducible observations consumed by owning audit or demo skills.
---

# Browser Evidence

This skill captures evidence; it does not own product audit/remediation or video production.
Route product decisions to `product-experience-engineering` and demo/media decisions to
`product-demo-studio`.

## Procedure

1. Read repository instructions and record build SHA, environment, role, URL, synthetic dataset,
   locale, timezone, viewport, zoom, color scheme, and reduced-motion setting.
2. Confirm the connected browser is a dedicated QA profile. Never connect to the normal personal
   Chrome instance. Shared mode permits one interactive agent; parallel agents require isolated
   profiles/ports and distinct server-side seed namespaces.
3. Take a page/accessibility snapshot before interaction.
4. Exercise the authorized workflow naturally with accessible names and visible text.
5. Record loading, empty, partial/stale, success, failure, recovery, and permission states requested
   by the owning skill.
6. Capture console messages, network requests/responses with headers redacted, runtime errors,
   screenshots, Lighthouse results, and performance traces relevant to the question.
7. Record observed behavior before code changes. Distinguish observation from inference.
8. Sanitize evidence for credentials, cookies, personal data, tenant identifiers, and unrelated
   tabs before handoff.

Never classify product defects, approve demo readiness, or create a polished master inside this
skill. Those decisions remain with their canonical owners.
