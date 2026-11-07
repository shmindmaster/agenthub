# Workflow detail

## Patterns

Use the repository's working pattern. If it has none, use these.

| Need | Use |
|---|---|
| Colour, spacing, type | Design tokens, no one-off values |
| Page data | Server-first rendering |
| Slow writes | Optimistic UI with rollback on failure |
| Slow reads | Skeletons matching the final layout |
| Late content | Reserved space, so nothing shifts |
| Overlays | Native `popover` and `<dialog>` |
| Layout by component width | Container queries |
| State and page changes | View Transitions, honouring `prefers-reduced-motion` |
| Release | Preview deployments and instant rollback |

## Accessibility

Meet WCAG 2.2 AA. Targets are at least 24px. Sticky UI never hides focus. Every drag has a non-drag alternative. Login never requires a cognitive test.
