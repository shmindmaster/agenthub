# Product-pipeline compatibility

Version: 1.8.3
Owner: AgentHub `handoff/product-demo-studio`

This matrix maps known repository-native product-video pipelines to the canonical Product Demo
Studio contract. It is a compatibility layer, not permission to copy product code, media, data,
authentication state, or credentials into AgentHub.

Always run `repo-registry.mjs --repo <path>`, read the repository's instructions and video README,
and inspect current files. These are observed shapes, not permanent assumptions.

| Legacy pipeline shape | Migration treatment | Canonical contract mapping |
|---|---|---|
| ABACare `studio` | Retire after preserving accepted media and any independently useful product tests | Convert useful manifests/reports to canonical evidence in the external workspace; do not retain studio code |
| Verigence `packages/videos` | Retire after preserving accepted media and product test coverage | Recreate candidates from product Playwright traces with the external Recast adapter |
| LienWise `studio` | Retire repo-local catalog, capture, narration, composition, mux, QA, delivery, and video-only CI | Keep the canonical truth/review contracts in this plugin and accepted media in mapped OneDrive |
| Lawli or WarrantyGains `apps/videos` | Retire the repo-local package and repair workspace/lockfile references | Use product behavior as read-only input; traces and all video production stay external |
| SubOps Playwright + FFmpeg | Keep only Playwright tests that are independently valuable product QA; retire video-only capture/render scripts | Recast consumes external or existing test traces; canonical preflight owns media checks |
| CrewScore release demo | Keep product fixtures only when useful outside video; retire narration/render/output trees | Synthetic product state remains product-owned; all production artifacts stay external |
| LexAlign `apps/videos` | Retire the empty/partial video catalog and video-only capture commands | Start any future episode from readiness and an external Recast workspace |
| Dormant `*_Video_Program` scaffold | Remove after preserving any accepted outputs | It is not evidence or a product capability |
| Generic `apps/videos`, `packages/videos`, or `studio` | Preserve only until migration is explicitly authorized, then remove | Never expand it; new production uses the external workspace and canonical contracts |
| Playwright + FFmpeg without Remotion | Keep product Playwright coverage only when independently useful; retire product-local assembly | Recast is the default compositor; FFmpeg remains its external system dependency and canonical QA tool |
| No video infrastructure | External AgentHub video workspace only when an approved episode is demo-worthy | Use the scaffold only after discovery/readiness; never create a generic runtime in the product repo |

## Required adapter behavior

A plugin-owned adapter in the external workspace may transform legacy manifest field names into the canonical JSON contracts.
It must:

- be stateless and external to the product repository;
- read source artifacts without moving or duplicating them;
- preserve original checksums and record the transformation version;
- fail on unknown required fields, stale candidate IDs, missing evidence, or unverifiable paths;
- never fabricate privacy, compliance, or synthetic-data evidence, and never self-authorize
  external publication;
- never make the product build depend on AgentHub at runtime.

The canonical schemas are the cross-host contract. Product repositories remain the authority for
product behavior, reusable fixtures, and build/test constraints—not video composition or generated media.
