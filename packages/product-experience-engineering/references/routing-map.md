# Product Experience Reference Routing

Load only the material needed for the current task.

| Task | Required references | Conditional references |
|---|---|---|
| Prepare a product for demo or video | `product-experience-audit-remediation-guide`, `artifact-contracts`, `application-surface-coverage` | Numbered references for additional depth; `media-studio` only after the handoff validates |
| Route broad app improvement work | `artifact-contracts`, `application-surface-coverage` | The specialized references below |
| Discover an existing application | `00`, `01`, `03`, `09`, `application-surface-coverage` | `02` for AI behavior; `05` for an established visual system |
| Audit an existing application | `01`, `03`, `06`, `09`, `application-surface-coverage` | `02` for agentic interactions; `05` for visual and interaction quality |
| Design workflows or features | `01`, `03`, `04` | `02` for AI-assisted work; `05` for detailed interaction choices |
| Write an implementation specification | `04`, `05`, `07` | `02` for agentic states; `03` for complex application shells |
| Implement an approved improvement | `05`, `07` | The approved audit, workflow design, and repository instructions |
| Validate an implementation | `05`, `06` | `02` for AI behavior; `08` when verifying external standards |
| Design a greenfield application | `00`, `01`, `03`, `04`, `05`, `07` | `02` when AI is material to the experience |
| Define outcome measurement | `01`, `04`, `06` | Existing telemetry and research plans |

The numbered files live in `product-experience-system/`. Treat them as generally applicable product-experience guidance, not a fixed checklist. Preserve repository-native conventions when they meet the intent; document deviations when they do not.
