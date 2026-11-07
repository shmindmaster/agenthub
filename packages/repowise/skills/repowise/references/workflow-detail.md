# Workflow detail


## Query

Read the exact file you are editing; use the index for orientation and impact.

| Situation | First | Then |
| --- | --- | --- |
| Unfamiliar repo | `get_overview` | `search_codebase`, `get_context` |
| Code question | `search_codebase` | `get_context`; `get_answer` only for a how/why question search cannot settle (paid model call) |
| Before editing | `get_context` | hotspot: `get_risk` |
| Working tree or PR | `get_risk` with `changed_files` | read `directive` |
| Commit range | `get_change_risk` | `risk_percentile` |
| Why it is shaped this way | `get_why` | |
| Cleanup | `get_dead_code` with `safe_only=true` | |

Pass `repo=<alias>` or `repo=all`. Wrap noisy commands in `repowise distill <cmd>`; recover omitted output with `repowise expand`.
