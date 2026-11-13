# Consolidation and naming — review and recommendations

Review of `packages/`, `registry/`, and the `agenthub-private` overlay from a
simplification and consolidation standpoint. Evidence is file-linked; every
claim below names where it was checked.

## Summary

The instinct that AgentHub is bloated is correct. The cause is **not** the one
expected: media-studio does not duplicate `packages/browser`, the marketplace
Remotion plugin, or the provider packages. The real costs are (1) media-studio
acting as a consolidation sink plus two unrelated products bundled in its
`kit/`, (2) seven thin wrapper packages that duplicate native/vendor plugins the
fleet already has, (3) skill names that carry no brand on four of five naming
surfaces, and (4) the private overlay drifting toward a second control plane.

Nothing here requires rewriting the registry design. The design is sound; the
work is deletion, extraction, and one naming convention applied consistently.

## What is *not* duplicated (correcting the hypothesis)

Checked and absent — not "did not check":

| Suspected overlap | Finding | Evidence |
| --- | --- | --- |
| media-studio vs `packages/browser` | **No code overlap.** `ah-browser` does interactive automation/QA on signed-in profiles or isolated `agent-browser` sessions. media-studio `kit/screencast/record-lib.mjs` does deterministic receipt-bound WebM takes plus Recast pointer finishing (cursor approach, click ripple, punch-in zoom) — that finishing is unique. Both consume the `playwright` library for different outputs. | `packages/browser/skills/automate/SKILL.md`; `packages/media-studio/kit/screencast/record-lib.mjs:1-11,196-198` |
| media-studio vs Remotion marketplace | **No policy contradiction.** `bundles.json` says do not vendor Remotion *rules*; `kit/` vendors a *project* — its own `Briefing`/`MarketingAd` compositions and 22 scene archetypes, which `remotion-dev/skills` cannot supply. Authoring guidance routes to the official skills and does not restate them. | `registry/bundles.json`; `kit/src/Root.tsx`; `kit/scene-archetypes.json`; `skills/generate/references/provider-plugins.md` |
| media-studio vs `assemblyai` / `descript` packages | **No code overlap.** Those two are hosted-MCP routing wrappers. media-studio holds governed spend adapters (`governed_elevenlabs/deepgram/azure_speech.py`) behind a ledger. Provider packages explicitly route media work to media-studio. | `packages/assemblyai/skills/assemblyai/SKILL.md`; `packages/media-studio/scripts/governed_*.py` |

So the Remotion and browser instincts point at real symptoms but the wrong
layers. Fix the layers that are actually wrong.

## Finding 1 — media-studio is a consolidation sink with two foreign products inside

313 tracked files, 10 skills, ~85 scripts, ~50 tests. Two mechanisms:

**Sink growth.** 26 of the 57 `retiredFleetSkills` rows name `media-studio` as
`supersededBy` (product-demo*, media-writer/storyboard/director, story-series,
technical-explainer, elevenlabs-*, local-ai-stack). Retiring a media-shaped
skill has been answered by folding it into media-studio since 2026-08-25.

**Foreign products in `kit/`.** The genuine seams are not in `scripts/` (one
coherent brief→plan→capture→compose→review pipeline) but in `kit/`:

- `kit/marketing/` — 40 files, a complete ad generator (`mvg`) with its own
  schema, gates, spend ledger and OpenAI vision QA. Not film composition.
- `kit/cloud/` — 9 files, ~120 KB: Azure Container Apps render worker
  (`cloud-render.mjs`, `worker.mjs`, `Provision-CloudRender.ps1`),
  `runware-image.mjs` (45 KB) and `cloud-ai.mjs` (34 KB). Render infrastructure,
  not composition code.

Keep as-is: `kit/src/` + `scene-archetypes.json`, `kit/screencast/` (Recast +
receipts are the moat), `kit/code-stage/` (git-object line hashing).

## Finding 2 — the thin wrappers duplicate native/vendor plugins

The fleet's own native-first audit already recorded this:

> Four read-only audits found native or vendor plugins already carry linear,
> notion, sentry, context7, exa, clerk, daytona, remotion and canva on most
> hosts; only `ah-sarosh`, `ah-media-studio`, `ah-product`, `ah-browser`,
> `ah-assemblyai` and `ah-descript` have no vendor equivalent.
> — `docs/current-state.md` (fleet refresh, 2026-11-09)

That makes five public packages redundant on most hosts (`ah-linear`,
`ah-notion`, `ah-context7`, `ah-exa`, `ah-daytona`), plus `ah-aws`, whose 32
unmanaged AWS/Remotion/agent-browser/lottie skills were already removed from
`~/.agents/skills` by owner decision. `registry/mcps.json` `retiredMcpIdsNote`
is explicit: "Hosts use their own browser. Do not register chrome-devtools-mcp,
@playwright/mcp." `docs/fleet/context-reduction.md` repeats it: "Native host
tools own browser automation."

Each wrapper is 12 files / ~6 KB of near-identical boilerplate: root
`plugin.json`, 4-5 host projections, `assets/icon.svg`, one `SKILL.md`, and
`tests/workflows.json`. The `SKILL.md` is a routing document over a hosted MCP
the host already provides. `packages/daytona` is the extreme case: 292 tracked
files, of which ~268 are **vendored SDK reference docs**
(`skills/daytona/references/{typescript,java,ruby,go,python}-sdk`, `api`,
`platform`). That is the single largest file count in the repository and it is
third-party documentation.

`packages/browser` is a partial exception: native tools own browser automation,
but the signed-in-profile lane and the isolated clean-state lane are not
something every host provides. That residue is worth keeping.

## Finding 3 — one capability, up to five names

| Package dir | Plugin `name` | Skill `name` | MCP id / display |
| --- | --- | --- | --- |
| `context7` | `ah-context7` | `docs` | `context7` / "Context7 Docs" |
| `brave-search` | `ah-brave-search` | `search` | — |
| `exa` | `ah-exa` | `research` | `exa` / "Exa Research" |
| `linear` | `ah-linear` | `issues` | `linear` / "Linear" |
| `notion` | `ah-notion` | `workspace` | `notion` / "Notion" |
| `aws` | `ah-aws` | `cloud` | — |
| `descript` | `ah-descript` | `edit` | `descript` / "Descript" |
| `browser` | `ah-browser` | `automate` | — |
| `media-studio` | `ah-media-studio` | `brief, capture, compose, develop, generate, plan, review, studio, video, visuals` | `descript` / "Descript" |
| `product` | `ah-product` | `audit, build, demo, design, verify` | — |

The plugin layer is already consistent: `docs/plans/active/plugin-redesign.md`
sets "`ah-*` IDs and `AH-*` display names with distinct icons", and all 67 host
projections agree on `name`/`version`. The inconsistency is everywhere else:

1. **Package directory** lacks the `ah-` prefix, so `packages/context7` and
   plugin `ah-context7` do not match.
2. **Skill names are unbranded generic verbs.** They deploy as bare names —
   verified in `~/.mimocode/skills`, which holds `brief`, `capture`, `compose`,
   `develop`, `generate`, `plan`, `review`, `studio`, `video`, `visuals`
   alongside `plan-application`, `prioritize`, `scout`, `dispatch`. Meanwhile
   other skills *do* get prefixed on deploy (`clerk-*`, `product-design`,
   `memory-search`, `mimo-desktop-guide`). The convention is applied
   inconsistently.
3. **MCP display names** follow a third convention ("Context7 Docs",
   "Exa Research", "RepoWise Workspace").
4. **Ownership is ambiguous.** MCP `descript` is
   `owner: {type: capability, id: media-studio}` while `packages/descript` is
   its own capability `descript`. Two owners for one integration.

The collision risk is real, not cosmetic: `plan`, `review`, `design`, `build`,
`search`, `edit`, `demo`, `verify`, `capture`, `generate` are exactly the names
a host, a user, or another plugin will also want.

## Finding 4 — the overlay is the right design, but has drifted

The mechanism is correct and worth keeping: `scripts/lib/CapabilityGraph.ps1`
resolves `AGENTHUB_OVERLAY` → `overlays/personal` → the sibling
`agenthub-private` recognised by its `overlay.json`, then merges only
`enabledCapabilityIds` rows. Public is the control plane; private is data. That
matches AGENTS.md ("There is no second control-plane repo. Do not recreate
one."). Capability ids do not collide (private: `sarosh`, `docwise`, `linkedin`).

Drift toward a second control plane:

- **`global-agent-policy.md` exists in both repos and they disagree** —
  similarity 0.337. Private has "Personal hosting" and "Load detailed policy"
  that public lacks; public has "Mobile scope" that private lacks. Same
  filename, two different truths, and the overlay-wins rule means hosts read the
  private one.
- **`packages/linkedin/mcp.json` restates** the public `registry/mcps.json`
  linkedin row verbatim (same `uvx mcp-server-linkedin@4.24.0`, args, env).
- **`overlay.json` claims `privateMarketplacePlugins: [sarosh, linkedin,
  docwise]`** but both `.claude-plugin/marketplace.json` files omit `linkedin`.
- **Misfiled product code.** `knowledge-os/` is a full Python 3.12 product
  ("MahumTech Knowledge OS", ~35 modules, own `pyproject.toml`, migrations,
  tests) referenced by **nothing** in either repo — grep-verified zero hits.
  Also `plans/active/storage-closeout/` session scratch and `tests/sarosh/`
  sitting at repo root instead of beside `packages/sarosh`.

## Finding 5 — smaller surface issues

- `registry/bundles.json` has drifted: the `slack-workspace` bundle `requires`
  a `slack` package that exists in neither repository. Either add it or retire
  the bundle.
- `packages/descript` ships **three** MCP config files for one server
  (`.mcp.json`, `mcp.json`, `mcp_config.json`). The per-host projection is
  legitimate (`plugin-formats.json` `canonicalPackage` documents it), but the
  projections could be generated from root `plugin.json` instead of 67
  hand-maintained files.
- Two test roots: `test/` (doctor) and `tests/` (suite).
- 16 packages carry `plugin.json`; `packages/security` does not (it is a git
  pre-push hook, not a plugin) — worth labelling so it stops looking like a
  missing manifest.

## Recommendations

Ordered by value/risk. Nothing here needs the registry redesign; each item is
deletion, extraction, or a convention fix.

### R1. Fix naming first — it is cheap and unblocks everything else

Adopt one identity per capability and derive every surface from it:

- **Canonical id**: the short name (`context7`, `media-studio`).
- **Plugin name**: `ah-<id>`, **display** `AH-<Title>` — already true, keep it.
- **Skill name**: `<id>-<verb>` or `<id>:<verb>`, never a bare verb. So
  `media-studio`'s `plan` becomes `media-plan` (or `media-studio:plan`),
  `product`'s `design` becomes `product-design`, `context7`'s `docs` becomes
  `context7-docs`.
- **MCP id**: `<id>`; **display**: `AH-<Title>`.

Renaming deployed skills is a breaking change, and
`docs/plans/active/plugin-redesign.md` says "keep stable plugin and skill
identities." Use the mechanism the repo already has for renames: record the old
name in `retiredFleetSkills` with `supersededBy` pointing at the new one, the
same way `product-demo-studio-capture` → `media-studio:capture` was handled.
Bump versions with `Bump-PackageVersion.ps1` so all 67 projections move
together.

Also resolve ownership: either `packages/descript` owns MCP `descript`, or
media-studio does — not both. Given `packages/descript` is a thin router and
media-studio holds the spend adapters, make `media-studio` the owner and retire
the standalone `descript` capability into it (its skill already says "for a film
from a brief use the media-studio video skill").

### R2. Retire the wrappers a vendor plugin already covers

This is **not** a blanket retirement. Per-host evidence gathered 2026-11-12
from 
egistry/mcps.json -> pluginOwnersByHost and

egistry/capabilities.json -> hostMappings shows the AgentHub wrappers are
load-bearing on very few hosts:

| MCP | h-* wrapper owns | Vendor owns | Wrapper hostMappings |
| --- | --- | --- | --- |
| linear | **amp** | antigravity, codex, copilot, cursor, devin, factory, grok, vscode-insiders (8) | mp only |
| context7 | **amp** | antigravity, codex, copilot, cursor, devin, factory, grok, opencode, vscode-insiders (9) | mp only |
| 
otion | **amp, grok** | antigravity, claude, codex, copilot, cursor, devin, factory, vscode-insiders (8) | grok, amp, warp |
| exa | **amp, antigravity** | codex, copilot, cursor, devin, factory, grok, vscode-insiders (7) | antigravity, amp, warp |
| clerk | none | 9 hosts, all vendor | — |

So retiring h-linear and h-context7 is a decision about **one host
(mp)**, not the fleet.

- **Retire, vendor replacement exists.** h-linear, h-context7 (each:
  mp only), h-notion, h-exa. For each host that would lose a route,
  confirm the vendor plugin is installed and enabled — the registry records
  *ownership*, not installation state — then retire and record
  
etiredFleetSkills with supersededBy: external:<vendor>.
- **Check one host live first.** h-daytona is mapped to 8 hosts in
  hostMappings, yet the native-first audit says daytona is carried natively on
  most hosts. Either the registry deploys a wrapper nobody needs, or the vendor
  route is not actually wired. Separately it is 292 tracked files, of which
  ~268 are vendored SDK reference docs — waste either way.
- **Owner call.** h-aws (skill-only, 11 hosts) and h-brave-search
  (skill-only, 13 hosts) wrap capabilities several hosts already have built in.
- **Keep.** h-assemblyai, h-descript, h-media-studio, h-product,
  h-browser, h-sarosh have no vendor equivalent (the audit's own list).
  h-repowise is already correctly handled: Claude and Codex use the vendor
  plugins and the AgentHub wrapper stays uninstalled there.

Do not delete on the audit alone. Before retiring h-daytona, extract anything
in its single script (skills/daytona/scripts/) that is not vendor
documentation. Report before/after tracked file and line counts.

Run the SH-4544 plugin redeploy first: 	ests/Test-InstalledPluginFreshness.ps1
currently fails on exactly this class of drift (h-coding-agent-dispatch
installed at 0.8.2/0.8.1/0.8.10 against source 0.8.11, 10 file differences per
host), which would otherwise mask real drift behind stale installs.

### R3. Extract the two foreign products out of media-studio's `kit/`

- `kit/marketing/` → `packages/marketing` (or retire it if the mvg ad generator
  has no current user). It is a self-contained product with its own schema,
  gates and ledger.
- `kit/cloud/` → `packages/cloud-render`, or move it under
  `%LOCALAPPDATA%`/D: runtime as infrastructure rather than a shipped package.
  It is an Azure Container Apps worker plus Runware stills, not composition.

This is a split, not a dedupe: the code is not duplicated, it is misplaced. Keep
`kit/src/`, `scene-archetypes.json`, `kit/screencast/`, `kit/code-stage/`
together — that cluster is the actual film product and its moat.

### R4. Narrow `packages/browser` to the residue native tools cannot do

Retire the general "click through, fill a form, smoke test" lane — native host
tools own that (`context-reduction.md`, `mcps.json`). Keep only the signed-in
existing-profile lane and the isolated clean-state capture lane. Fold the
capture-relevant parts into media-studio `skills/capture` if they are already
there, and let `ah-browser` become small and specific rather than a parallel
browser stack.

### R5. Shrink `agenthub-private` to exactly what the overlay consumes

Keep: `packages/{sarosh,docwise,linkedin}`, their three `capabilities.json`
rows, `policy-fragment.md`, `guidance/`, `privacy-denylist.txt`, `overlay.json`,
and the marketplace role (that is distribution, not registry).

Then:

- **Delete `agenthub-private/global-agent-policy.md` as a stored copy.** Generate
  it at sync time from `policy-core.md` + `policy-fragment.md`, or keep it but
  mark it generated and validate it against sources. Right now it has already
  diverged from public (missing "Mobile scope"), and overlay-wins means hosts
  read the drifted version.
- **Deduplicate the linkedin MCP contract.** `registry/mcps.json` is canonical;
  `packages/linkedin/mcp.json` should reference it or be hash-validated against
  it, not restate it.
- **Move `knowledge-os/` to its own repository.** It is a Graph product with its
  own packaging and tests, referenced by nothing here.
- **Move `tests/sarosh/` beside `packages/sarosh/`**, and clear
  `plans/active/storage-closeout/` session scratch per the leave-nothing-behind
  rule.

End state: public `agenthub` is the only control plane; private is three
packages, three rows, a policy fragment and guidance.

### R6. Stop the sink from re-growing, and clean the small drift

- Change the retirement reflex: a new media-shaped capability should not default
  to "fold into media-studio". Require an explicit decision recorded in the
  registry (a `capabilityType` of `plugin+skills` at 313 files is already past
  the point where folding in is free).
- Fix `registry/bundles.json`: add the `slack` package or retire the
  `slack-workspace` bundle. Re-read all four bundles against the current package
  set; three of them still say `requires: [media-studio]` and reference
  `learning-studio`/`browser-toolkit` retirements in their notes, which is
  history that belongs in `retiredFleetSkills`, not in a recipe.
- Consider generating the 67 host projections from root `plugin.json` (the
  `canonicalPackage` block already defines root as "the single version
  authority"). `Bump-PackageVersion.ps1` already walks them; generation would
  remove the drift surface entirely.
- Merge `test/` into `tests/`, and mark `packages/security` as a hooks package
  (no `plugin.json`) in the registry so it stops reading as a broken manifest.

## Suggested sequence

1. R1 naming + R6 drift cleanup — no capability removed, low risk, unblocks the
   rest.
2. R5 private-overlay shrink — reversible, and it removes the two-truths policy
   problem.
3. R2 wrapper retirement — needs per-host evidence first; do one package end to
   end as a canary (`ah-context7` is the smallest and the audit's clearest hit).
4. R3 media-studio split + R4 browser narrowing — the largest changes; do last,
   with `Validate-AgentHub.ps1` and `tests/Run-AllTests.ps1` green at each step.

Each step is independently shippable and independently reversible. None of them
changes the registry schema or the overlay mechanism, which are working as
designed.
