# Search parameters

Pass any of these as `--name value`; dashes become underscores. Sources: the Brave Search API documentation and the MIT-licensed brave/brave-search-skills repository.

## Shared

| Parameter | Applies to | Notes |
|---|---|---|
| `count` | all | `context` 1-50 (default 20), `web` 1-20, `news` and `videos` 1-50, `images` 1-200, `suggest` 1-20 |
| `offset` | `web`, `news`, `videos` | page 0-9 |
| `country` | all | 2-letter code or `ALL` (default `US`) |
| `search-lang` | all | language code (default `en`); `suggest` and `spellcheck` use `lang` |
| `safesearch` | all | `off`, `moderate`, `strict`; images accept only `off` and `strict` |
| `freshness` | `context`, `web`, `news`, `videos` | `pd` 24 h, `pw` 7 d, `pm` 31 d, `py` 365 d, or `YYYY-MM-DDtoYYYY-MM-DD` |
| `spellcheck` | most | `true` by default; corrected query appears as `corrected_query` |
| `extra-snippets` | `web`, `news` | up to 5 more excerpts per result |
| `goggles` | `context`, `web`, `news` | inline definition, URL, or `@file` |

## context (default)

| Parameter | Range | Use |
|---|---|---|
| `maximum-number-of-tokens` | 1024-32768, default 8192 | total content budget |
| `maximum-number-of-urls` | 1-50 | sources considered |
| `maximum-number-of-tokens-per-url` | 512-8192 | per-page cap |
| `maximum-number-of-snippets` | 1-256 | total snippets |
| `context-threshold-mode` | `strict`, `balanced`, `lenient`, `disabled` | `strict` for fewer, tighter hits |

## web

- `result-filter web,news,videos,discussions,faq,infobox,locations` limits the buckets returned.
- Location-aware ranking: `--loc-lat 37.77 --loc-long -122.42`.
- Operators work inside the query: `site:`, `ext:`, `filetype:`, `intitle:`, `inbody:`, `inpage:`, `lang:`, `loc:`, `+term`, `-term`, `"exact phrase"`, and uppercase `AND`, `OR`, `NOT`. Pass `--operators false` to treat them as plain text.

## Goggles

A Goggle re-ranks or filters results. Inline form, one rule per line:

```text
$discard
$site=docs.rs
$site=rust-lang.org
```

A bare `$discard` drops every result that no later `$site=` rule allows. Rules take comma-separated options: one action (`discard`, `boost=N`, `downrank=N`, N from 1 to 10) and `site=DOMAIN`. Block list: `$discard,site=pinterest.com`. Boost: `$site=docs.python.org,boost=3`. Save the rules in a file and pass `--goggles @rules.txt`. A hosted Goggle URL must be registered with Brave; inline rules need no registration.

## Other commands

- `suggest "rus" --count 5` returns completions; `--rich true` adds entity data and needs a paid plan.
- `spellcheck "recieve"` returns corrected queries.
- `images` rows carry `title`, `source`, `page` (the hosting page), `image` (full-size URL) and `thumbnail`.
- `videos` rows carry `duration` and `creator`.
