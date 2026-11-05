# Answers

`answers` calls Brave's OpenAI-compatible chat endpoint and returns written text grounded in search results.

```bash
node scripts/brave.mjs answers "How does the James Webb telescope work?"
node scripts/brave.mjs answers "Recent breakthroughs in fusion energy" --citations
node scripts/brave.mjs answers "Compare vector databases for 10M documents" --research --research-maximum-number-of-seconds 120
```

| Mode | Flag | Behavior |
|---|---|---|
| Single search | none | one search, fast, blocking JSON; prints the answer text |
| Citations | `--citations` | streams one search with inline `<citation>` tags |
| Research | `--research` | iterative multi-search; prints the final answer, any blind spots, and the request cost |

Constraints: research and citations both stream; research cannot be combined with citations.

Tuning flags are sent in the request body: `--max-completion-tokens`, `--country`, `--language`, `--safesearch`, and for research `--research-maximum-number-of-queries` (1-50), `--research-maximum-number-of-iterations` (1-5), `--research-maximum-number-of-seconds` (1-300), `--research-maximum-number-of-results-per-query` (1-60), `--research-maximum-number-of-tokens-per-query`.

Verify any claim that matters against the cited URL before relying on it.
