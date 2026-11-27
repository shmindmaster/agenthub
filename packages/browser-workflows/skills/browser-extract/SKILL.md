---
name: browser-extract
description: Use when the task requires an agent to collect and reconcile structured browser data, paginated reports and downloads.
---

Start with the background session launcher in `../browser-operate/SKILL.md` and address only the task session. Discover loaded tables with bsk extract --help. Select the intended table or list and retain its source, units, period and row labels. Check coverage, pagination and virtual scrolling. Record each page deliberately, deduplicate by stable record ID and reconcile totals before calling a result complete.

Use bsk read for individual fields, bsk observe for context and bsk download for an authorized export. Verify the downloaded format, date range and row count. Keep personal records and raw downloads in the task workspace. Return the requested summary, comparison or file.
