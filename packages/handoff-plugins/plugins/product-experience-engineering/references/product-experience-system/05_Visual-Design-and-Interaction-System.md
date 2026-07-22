# Visual Design and Interaction System

## Purpose

A strong visual system helps users find, understand, compare, and act. It creates coherence without making every application look identical. Product identity, domain tone, and information density can vary; hierarchy, state clarity, interaction behavior, accessibility, and token discipline should remain deliberate.

## 1. Begin with information hierarchy

Visual design follows the user’s decision:

1. What is this page or object?
2. What state is it in?
3. What requires attention?
4. What information supports the decision?
5. What action is primary?
6. What detail is available if needed?

Use size, weight, position, spacing, contrast, grouping, and repetition to answer those questions. Do not rely on color or decoration alone. Reduce competition: a page cannot have five equally prominent primary areas.

## 2. Layout and composition

### Page structure

Use a stable content grid with intentional maximum widths. Long reading surfaces need narrower measures; tables and operational workspaces may need the full viewport. Keep page headers, filters, content, and action regions aligned so users can scan vertically.

### Regions

Prefer a small number of meaningful surfaces over nested cards. Use containment when it communicates grouping, state, selection, or interaction—not to put a border around every paragraph. Separate persistent workspace areas from transient overlays.

### Responsive composition

Define layout behavior at content breakpoints, not only device labels. Decide what wraps, stacks, scrolls, collapses, moves into a drawer, or becomes a different component. Preserve task sequence and primary actions. Test compact laptops and zoomed desktop layouts, not only phone and wide monitor.

## 3. Spacing and density

Use a documented spacing scale and align repeated anatomy. Spacing communicates relationship: less space within a group, more between groups. Avoid arbitrary one-off values unless content genuinely requires them.

Density is a product decision. Operational experts may need compact tables and panels; occasional users may benefit from more explanation and larger grouping. Offer comfortable/compact modes only when both are designed and tested. Touch targets and focus visibility remain adequate in dense modes.

## 4. Typography

Define roles, not a collection of font sizes:

- display/page title;
- section heading;
- object title;
- body and long-form reading;
- label and control text;
- metadata and helper text;
- numeric/tabular values;
- code or identifiers.

Keep hierarchy restrained and predictable. Body text needs readable line height and measure. Metadata can be quieter but must remain legible. Use tabular numerals for columns that compare values. Avoid all-caps for long labels and excessive weight changes.

## 5. Color and semantic state

Separate brand color from semantic color. Define tokens for background, surface, text, muted text, border, focus, selection, link, accent, and status. Status palettes cover information, success, warning, danger, and neutral states across background, text, border, and icon use.

Every semantic state needs text or iconography in addition to color. Check contrast in all states, including disabled, selected, hover, dark mode, charts, badges, and data visualization. Avoid using red for routine required fields or green for ordinary completion when it creates alarm/noise.

## 6. Icons and imagery

Use icons to reinforce a known action or object, not to replace unfamiliar language. Pair ambiguous icons with labels or tooltips and accessible names. Use one icon family and consistent stroke/fill treatment. Distinguish navigation, status, and actions through context.

Illustrations and imagery should clarify onboarding, empty states, or product identity. Do not use generic AI sparkle/robot imagery to imply capability. Operational products often benefit more from useful examples or previews than decorative art.

## 7. Surfaces, borders, radius, and elevation

Choose a small surface hierarchy: application background, primary work surface, raised/overlay surface, selected/active surface, and semantic surface. Use borders for structure and separation, shadows/elevation for layering and transient overlap, and radius consistently according to component family.

Avoid stacking card inside card, heavy shadows on static content, and excessive rounded containers that weaken alignment. A restrained system tends to make dense data feel calmer.

## 8. Controls and action hierarchy

Define primary, secondary, tertiary/ghost, link, and destructive action treatments. Visual priority follows task priority. Keep destructive actions explicit and separated from routine actions. Disabled controls need sufficient legibility and an explanation when users need to understand availability.

Controls require default, hover, active, focus-visible, disabled, pending, selected, and error states where applicable. A pending button should retain its label context, prevent duplicate action, and not change width unexpectedly.

## 9. Focus, selection, and hover

Focus is an interaction state, not an accessibility afterthought. Use a highly visible focus token that works across surfaces. Do not remove outlines without an equivalent.

Selection should remain distinct from focus and hover. Tables, lists, trees, canvases, and multi-select controls need clear models for current item, selected items, and active keyboard target. Hover reveals supplemental affordance only; required actions remain available to touch and keyboard users.

## 10. Motion and transition

Motion should explain continuity, hierarchy, entry/exit, progress, or cause and effect. Keep durations short and consistent. Avoid animation that delays action, masks unstable layout, or suggests progress inaccurately.

Provide reduced-motion behavior. Streaming, progress, skeletons, and agent activity should remain comprehensible without shimmer or continuous animation. Preserve spatial continuity when opening detail panels or moving between related states.

## 11. Content design

Use product language that is concise, specific, and consistent. Titles identify objects or outcomes. Buttons describe actions. Helper text explains format or consequence, not obvious control behavior. Error copy states the problem and correction. Empty-state copy reflects why the state is empty.

Define terminology centrally per product. Maintain status labels as a controlled set with clear transitions. Avoid anthropomorphizing agents in ways that overstate understanding or responsibility.

## 12. Data visualization

Start with the question the visualization answers. Use tables for exact comparison, line charts for change, bars for categorical comparison, and simple indicators for a small number of meaningful metrics. Label values, time ranges, units, sources, and freshness.

Do not use pie/donut charts for many categories, dual axes without strong justification, or color palettes that cannot be distinguished. Provide accessible summaries and underlying data where practical. Charts should link to the records behind a decision.

## 13. Tables and dense operational surfaces

Use alignment, whitespace, typography, sticky headers/identity, and restrained status tokens to aid scanning. Avoid turning every cell into a pill. Reserve badges for categorical state or attention. Keep row actions predictable and prevent hover-only discovery.

Support column priority, resizing or configuration when justified, and readable empty/loading rows. Use truncated content only with a reliable reveal. Density should not reduce targets or obscure focus.

## 14. Documents and long-form reading

Long-form surfaces need readable measure, clear headings, stable anchors, source/version context, selection/copy behavior, and navigation among sections. Place comments, evidence, citations, or agent activity in secondary panes that can collapse without reducing the document width below usability.

Generated documents need draft/final state, edit history, and source visibility. Avoid styling generated content so confidently that users cannot distinguish it from approved material.

## 15. Agentic surfaces

Agent UI uses the same system as the product. Plans, activity, evidence, proposals, diffs, and approvals are product components—not a separate visual universe. Use semantic states consistently with task and record status.

Keep conversational content readable but place structured outputs in native components. Distinguish user text, agent explanation, tool/system status, evidence, and durable product data. Avoid excessive avatars, chat bubbles, gradients, and animation that make operational work feel like a demo.

## 16. Design tokens and component ownership

Tokens should describe role rather than raw appearance: `text-muted`, `surface-raised`, `border-danger`, `focus-ring`, `space-section`, `radius-control`. Build raw scales underneath and semantic tokens above them. Product themes can change values without changing component meaning.

Own component composition and variants in the repository. Accessible primitives can provide behavior, but local components define product anatomy, tokens, copy, responsive rules, and tests. Avoid multiple competing component foundations.

## 17. Visual review procedure

Review representative screens as a system:

1. Home/dashboard.
2. Dense list/table.
3. Object detail/workspace.
4. Form or multi-step flow.
5. Document/content surface.
6. Agent task with plan, progress, evidence, and approval.
7. Empty, loading, error, partial, and success states.
8. Narrow, medium, wide, zoomed, dark/high-contrast, and reduced-motion contexts where supported.

Inspect alignment, hierarchy, density, action priority, terminology, component state, and continuity across screens. A polished isolated screenshot is insufficient evidence.

## Visual acceptance checklist

- Page purpose and primary action are visually obvious.
- Content hierarchy matches user decision importance.
- Repeated components and states are consistent.
- Dense information remains scannable.
- All interactive states, including focus and pending, are designed.
- Responsive layouts preserve task completion.
- Color is not the only meaning carrier.
- Loading and transitions avoid disruptive shifts.
- Agent surfaces feel native to the application.
- Product identity is coherent without interfering with utility.
