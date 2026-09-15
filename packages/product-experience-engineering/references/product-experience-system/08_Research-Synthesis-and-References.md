# Research Synthesis and References

## Purpose and method

This document records the research foundation for the Product Experience System. It combines two bodies of material:

1. A thematic reconstruction of four substantial agentic UI/UX reports previously reviewed in this workspace.
2. A July 2026 review of authoritative product-design, accessibility, human-AI interaction, frontend, and agent-interface sources.

The original reports are no longer available as files. Their titles, section inventories, scope, distinctive recommendations, and research caveats were captured before removal. The reconstruction below preserves those contributions without claiming to reproduce their wording or every cited fact.

## Reconstructed original research

### Broad SMB agentic UI architecture

The first source treated agentic software as a shift from static command/response interfaces toward systems that act asynchronously on a user’s behalf. Its strongest contribution was a catalog of interaction patterns: streaming output, progress for multi-step work, stages and timelines, activity summaries, tool execution, editable plans, evidence, proposed next steps, action previews, human approvals, interruption, retry, resumption, undo, and rollback.

It argued for low-chrome interfaces in which data and agent activity remain primary. It also distinguished a shared cross-industry core from domain-specific workflow and compliance layers, compared frontend/component approaches, proposed stack choices for teams at different maturity levels, and ended with a practical small-team implementation sequence.

### Multi-vertical agentic business-software playbook

The second source’s central thesis was that the agent should appear as an operator inside a business workspace—not as a full-screen chatbot that replaces the product. It treated state visibility as the main agentic UX problem and proposed a persistent workspace with an activity rail, structured task states, evidence, previews, approvals, and recovery controls.

It introduced risk-sensitive confirmation: read-only work can usually proceed; internal writes need visible review proportional to impact; external communications, money movement, publication, or regulated consequences require explicit approval and a clear final payload. It also proposed shared UI and agent packages, vertical adapters, representative workflows, stack recommendations, and an adopt/customize/build/avoid decision model.

### AI-native React and Next.js design-system evaluation

The third source evaluated one modern web implementation profile by accessibility, maintainability, AI interaction support, implementation speed, complex-data capability, and domain suitability. For compatible applications, it recommended a server-first, open-code, accessibility-centered architecture: Next.js and React for the application, Tailwind plus a copy-owned component layer, one accessible primitive family, one AI runtime or event contract, and specialized libraries only where they supply a category-defining capability. These technology choices are preserved as researched options, not universal requirements.

Its sharpest warning concerned stack overlap. Combining several component systems, styling layers, grids, and AI UI frameworks as coequal foundations creates incompatible abstraction levels and makes the product harder to evolve. It also warned that attractive AI suggestions can weaken oversight when they are easy to accept but cognitively expensive to inspect. It recommended a thin reference implementation and validation across representative regulated-domain workflows.

### Comprehensive agentic UI/UX synthesis

The fourth source was the broadest and most heavily referenced. It combined interaction contracts—preview, approval, undo, audit—with low-chrome visual design, reusable frontend architecture, multi-vertical guidance, and a detailed component/pattern inventory. It emphasized streaming, progress, task control, evidence, provenance, action boundaries, accessible custom interactions, domain-specific review, and the need to measure correction, override, false acceptance, and comprehension rather than treating visual polish as proof of usability.

### What the original research did well

- Recognized that agency changes the interaction model, not merely the chat component.
- Made progress, evidence, action previews, approvals, and recovery first-class UI concerns.
- Connected interaction design to frontend architecture and event/state modeling.
- Preserved domain variation while seeking reusable patterns.
- Treated accessibility and human oversight as part of interaction quality.
- Recommended a narrow reference workflow before platform-wide abstraction.

### Gaps this rebuild closes

The reports were comparatively light on ordinary application UX. The rebuilt system therefore adds detailed guidance for navigation, search, dashboards, tables, forms, filters, saved views, bulk actions, documents, settings, responsive layouts, content design, perceived performance, visual hierarchy, feature discovery, and complete state behavior. It also adds a repeatable method for deciding which features are useful, mapping workflows, specifying changes, implementing them, and validating the outcome in a real repository.

## Human-centered AI findings

### Start with the user outcome, not the model capability

Google’s [People + AI Guidebook](https://pair.withgoogle.com/guidebook-v2/) organizes AI product work around user needs, success definition, mental models, explainability, feedback/control, data, and graceful failure. The durable lesson is that AI should be used where its variability creates value a deterministic workflow cannot provide—or where it removes meaningful effort while preserving user control. “Add an assistant” is not a product outcome.

Microsoft’s [HAX Toolkit](https://www.microsoft.com/en-us/haxtoolkit/) provides 18 research-backed guidelines across initial interaction, normal use, failure, and learning over time. The pattern library supports explicit capability framing, limitation disclosure, context-aware behavior, understandable reasoning, efficient correction, scoped memory, and failure recovery. These findings inform the lifecycle structure in the agentic-pattern library.

### Calibrate mental models continuously

Users need to know what the system can do, what it cannot do, what information it used, and when it needs help. This is not solved by a one-time disclaimer. Capability framing belongs at onboarding, at the point of action, in progress feedback, in explanations, and in recovery states. The UI must also expose boundaries: which records are in scope, which tools are available, which action will be taken, and which state will change.

### Design for inevitable failure

The HAX Playbook and PAIR guidance both assume AI systems will fail in foreseeable classes: wrong intent, missing context, inappropriate scope, incorrect content, poor timing, or unavailable capability. Product teams should simulate these failures before full implementation. Recovery must preserve user work, explain what remains valid, show what the system needs, and avoid repeating an action with unchanged inputs.

### Explanations must support a decision

Explanations are useful when they help a person judge, correct, or act. A generic “AI generated this” label is insufficient. Depending on the task, useful evidence may include source records, document passages, assumptions, calculations, tool results, conflicts, freshness, and omitted inputs. Raw internal reasoning is neither necessary nor appropriate; concise decision-relevant rationale is.

### Feedback and control form a learning loop

Feedback controls need clear consequences. Apple’s [machine-learning interaction guidance](https://developer.apple.com/design/human-interface-guidelines/machine-learning) recommends specific feedback labels, voluntary participation, immediate visible effect, and persistence of the resulting preference. A thumbs-down with no explanation of what changes is weak product behavior.

## General product-experience findings

### Purpose and focus

Apple’s current [design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles) begin with value: ask what the product is for, prioritize the most important capabilities, keep the interface out of the way, preserve agency, help people recover, and use consistent familiar concepts. This aligns with the original reports’ low-chrome recommendation but broadens it beyond visual minimalism. A focused product can still be information-dense; it simply makes the user’s current goal and next useful action obvious.

### Visibility and feedback

Apple’s [feedback guidance](https://developer.apple.com/design/human-interface-guidelines/feedback) recommends matching the prominence and interruption level of feedback to its significance. Status is often best near the affected object; critical, actionable warnings justify interruption. Significant completion deserves confirmation, while routine success should not create notification noise.

### Perceived performance is designed behavior

Apple’s [loading guidance](https://developer.apple.com/design/human-interface-guidelines/loading) favors immediate meaningful content, background work, accurate determinate progress when duration is knowable, and continued access to other tasks. React’s [Suspense guidance](https://react.dev/reference/react/Suspense) similarly warns against replacing already visible content with jarring fallbacks during updates. Preserve useful stale content, show localized pending states, and reveal content in coherent sequences.

Google’s [Core Web Vitals](https://web.dev/articles/vitals) measure loading, responsiveness, and visual stability through LCP, INP, and CLS. These metrics are valuable signals, but they do not replace workflow-level measures such as time to complete, error recovery, or successful task outcomes.

### Forms and validation

The [GOV.UK validation pattern](https://design-system.service.gov.uk/patterns/validation/) provides concrete behavior: accept reasonable input variations, preserve entered values, explain what is wrong and how to fix it, connect summary errors to fields, and avoid premature validation unless research shows it helps. This informs the form, error, and recovery patterns.

### Tables, search, and navigation

Operational applications depend on structured data. The [U.S. Web Design System table guidance](https://designsystem.digital.gov/components/table/) distinguishes genuine tabular comparison from layout, addresses sorting semantics and narrow-screen behavior, and emphasizes testing the final implementation. Its [search](https://designsystem.digital.gov/components/search/) and [pagination](https://designsystem.digital.gov/components/pagination/) guidance likewise connect components to user intent rather than treating them as decoration.

### Accessibility is the quality of the implemented interaction

[WCAG 2.2](https://www.w3.org/TR/WCAG22/) supplies normative conformance criteria. The [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/) provides informative patterns for semantics, keyboard interaction, names, focus, and complex widgets. APG is not itself a design system and a library cannot guarantee that an application is accessible. The product must test its actual content, focus movement, live updates, responsive behavior, and end-to-end workflows.

## Agent interface and frontend findings

### Structured events enable truthful interfaces

The [AG-UI event model](https://docs.ag-ui.com/concepts/events) separates run lifecycle, steps, streamed messages, tool calls, results, state snapshots/deltas, activities, errors, and custom events. A product does not need to adopt AG-UI to benefit from this structure. The key is to avoid deriving task status from prose. A typed event/state contract lets the UI show progress, reconnect, reconcile partial updates, and distinguish what happened from what the model said.

### Generative UI should render trusted components from validated data

[AI SDK UI generative interfaces](https://ai-sdk.dev/docs/ai-sdk-ui/generative-user-interfaces) connect tool results to React components. The useful pattern is constrained generation: the model selects a known tool or view, validated data drives a trusted component, and the user can inspect or act on the result. Arbitrary interface generation makes consistency, accessibility, testing, and safe action boundaries harder.

### Accessible primitives reduce work but do not remove ownership

[Radix Primitives](https://www.radix-ui.com/primitives/docs/overview/accessibility) implement many expected ARIA, focus, and keyboard behaviors. [shadcn/ui](https://ui.shadcn.com/) keeps generated component code in the application. Together they support a copy-owned component approach, but teams remain responsible for labels, composition, styling states, responsive behavior, upgrades, and testing.

### Framework behavior should support the experience

Next.js distinguishes expected errors from uncaught exceptions and supports route-level recovery through [error handling conventions](https://nextjs.org/docs/app/getting-started/error-handling). React transitions can keep already visible UI usable during background updates through [useTransition](https://react.dev/reference/react/useTransition). These are implementation tools for experience goals; they are not substitutes for deciding what users should see, retain, or do next.

## AI risk findings relevant to product behavior

The [NIST Generative AI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) frames generative-AI risk across governance, context mapping, measurement, and management. For product experience, the important implication is that intended use, affected users, failure modes, measurement, and escalation must be explicit.

The [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/) identifies product-relevant threats such as prompt injection, sensitive-information disclosure, improper output handling, excessive agency, and overreliance. User-facing controls cannot replace backend enforcement, but the interface must not imply powers, safety, or certainty the system does not possess.

## Synthesis decisions

1. The canonical experience is a task-centered workspace with agent capabilities embedded where they create value.
2. Product usefulness precedes visual refinement and AI novelty.
3. Every important workflow needs explicit states, recovery, and evidence—not only a happy path.
4. Agent activity is represented through structured lifecycle and state data.
5. Consequential actions require a preview proportional to impact and a clear user decision.
6. A shared pattern library supports consistency, while domain workflows and product identity remain local.
7. Server-first, copy-owned, accessibility-centered frontend architecture is one strong implementation profile for compatible web applications, not a universal default.
8. Repository changes begin with user and workflow understanding, then move through specification, implementation, and validation.

## Source index

### Product and human-AI design

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Google People + AI Guidebook](https://pair.withgoogle.com/guidebook-v2/)
- [Microsoft HAX Toolkit](https://www.microsoft.com/en-us/haxtoolkit/)
- [GOV.UK Design System](https://design-system.service.gov.uk/)
- [U.S. Web Design System](https://designsystem.digital.gov/)
- [Nielsen Norman Group usability heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)

### Accessibility and performance

- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [ARIA Authoring Practices Guide](https://www.w3.org/WAI/ARIA/apg/)
- [Core Web Vitals](https://web.dev/articles/vitals)

### Agentic systems and risk

- [NIST AI RMF Generative AI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
- [AG-UI documentation](https://docs.ag-ui.com/introduction)
- [AI SDK UI documentation](https://ai-sdk.dev/docs/ai-sdk-ui/overview)

### Optional frontend implementation profiles

- [React documentation](https://react.dev/)
- [Next.js documentation](https://nextjs.org/docs)
- [Tailwind CSS documentation](https://tailwindcss.com/docs)
- [shadcn/ui](https://ui.shadcn.com/)
- [Radix Primitives](https://www.radix-ui.com/primitives)
- [Base UI](https://base-ui.com/)

## Freshness and confidence

Research reviewed July 2026. Durable interaction principles have high confidence where several independent sources converge. Library APIs, release status, licensing, and protocol details are time-sensitive and must be checked against current official documentation during repository implementation. Domain-specific legal or regulatory implications require project-specific review and are not inferred from this product-experience reference.
