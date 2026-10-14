# Writes

Authorized writes: `slack_post`, `slack_reply`, `slack_update`, `slack_delete`,
`slack_react`, `slack_unreact`, `slack_file_upload`, pins, bookmarks.

The approval gate is enforced in code (`mcp/write-gate.mjs`), not only here:

- every write call must carry `approved=true`, set only after the user
  approved that exact destination and action; anything else is refused before
  the backend is touched
- `slack_bookmarks` is gated for `add` and `remove`; `list` stays a read
- with no `SLACK_USER_TOKEN`/`SLACK_BOT_TOKEN` and no explicit
  `SLACK_BRIDGE_MODE=fixture`, reads fall back to fixtures but writes are
  refused, so a write never lands in the fixture workspace by accident
- `tools/list` carries `annotations` (`readOnlyHint`, `destructiveHint`,
  `idempotentHint`, `openWorldHint`) so a host can prompt before a write

`slack_api_read` is the read escape hatch (allowlisted Web API methods).
`slack_api_write` is the write escape hatch. It refuses unless `approved=true`
and `SLACK_BRIDGE_ALLOW_API_WRITE=true`.

Prefer the semantic tools. Use the escape hatch only for a method the
canonical surface does not expose.
