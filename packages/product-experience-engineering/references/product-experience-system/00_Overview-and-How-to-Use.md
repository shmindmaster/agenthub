# Product Experience System

## What this is

This is an application-agnostic reference for making software more useful, understandable, efficient, coherent, and satisfying. It covers ordinary application UX and, where a demonstrated user need exists, agentic AI behavior. It turns those principles into a repeatable method for auditing and improving one repository at a time.

The system is deliberately not a universal visual theme, fixed technology stack, or portfolio-wide compliance checklist. Each application keeps its own users, domain, product identity, architecture, and constraints. The shared material supplies questions, patterns, and specification quality so teams do not repeatedly invent basic interaction behavior.

## Applicability and modular use

Use only the parts that improve the application and its users' work. The core principles, application patterns, workflow method, visual system, audit method, and specification templates apply broadly. The agentic interaction library is a conditional module for workflows in which AI assistance, tool use, background execution, or generated artifacts create clear user value. An application does not need an assistant, chat surface, autonomous behavior, or generative UI merely because this reference includes those patterns.

Framework and library examples are implementation profiles, not required foundations. During repository work, translate each durable experience requirement into the application's existing architecture unless a change is justified by measurable user or engineering value.

## Choose a reading path

### Product strategy and feature work

1. [Product Experience Principles](01_Product-Experience-Principles.md)
2. [Feature and Workflow Design Method](04_Feature-and-Workflow-Design-Method.md)
3. [Core Application UX Patterns](03_Core-Application-UX-Patterns.md)

Use this path to decide what the product should do, which capabilities matter, and how a workflow should improve.

### Agentic product work

1. [Product Experience Principles](01_Product-Experience-Principles.md)
2. [Agentic Interaction Patterns](02_Agentic-Interaction-Patterns.md)
3. [Implementation Specification Template](07_Implementation-Specification-Template.md)

Use this path for assistants, background agents, tool execution, generative UI, plans, evidence, approvals, and recovery.

### Interface and design-system work

1. [Core Application UX Patterns](03_Core-Application-UX-Patterns.md)
2. [Visual Design and Interaction System](05_Visual-Design-and-Interaction-System.md)
3. [Research Synthesis and References](08_Research-Synthesis-and-References.md)

Use this path when refining application shells, navigation, data-heavy screens, forms, responsive behavior, component states, visual hierarchy, or design tokens.

### Repository audit and implementation

1. [Product Experience Audit Method](06_Product-Experience-Audit-Method.md)
2. [Repository Audit Template](09_Repository-Audit-Template.md)
3. [Implementation Specification Template](07_Implementation-Specification-Template.md)

Use this path to inspect an application, identify opportunities, specify improvements, implement them, and validate the outcome.

## How repository work proceeds

Applications are handled sequentially. For each repository:

1. Understand the product, users, domain, architecture, existing instructions, and current experience.
2. Run representative workflows with realistic synthetic data where feasible.
3. Inventory routes, screens, features, information, components, and important states.
4. Identify strengths, friction, missing utility, confusing behavior, feature gaps, and visual inconsistency.
5. Prioritize findings by user value, frequency, workflow impact, severity, confidence, dependencies, and implementation effort.
6. Write decision-complete experience specifications before broad implementation.
7. Implement in small slices using repository-native patterns.
8. Validate behavior, responsiveness, keyboard operation, state handling, and critical journeys with repeatable evidence.
9. Add only genuinely reusable lessons back to this central reference.

No other repository is changed while the active repository is being deeply audited and refined.

## Pattern quality standard

A useful pattern explains more than appearance. It should identify:

- the user need and intended outcome;
- when the pattern helps and when it does not;
- required information and controls;
- normal, empty, loading, partial, error, interrupted, and recovery states;
- responsive, keyboard, and accessibility behavior;
- content and labeling requirements;
- implementation implications;
- common failure modes;
- acceptance and validation scenarios.

## Research basis

[Research Synthesis and References](08_Research-Synthesis-and-References.md) reconstructs the original agentic UI/UX research, identifies what was preserved, explains the gaps added in this rebuild, and links the current sources behind the recommendations.
