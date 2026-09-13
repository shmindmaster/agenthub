# Writes

Authorized writes: `slack_post`, `slack_reply`, `slack_update`, `slack_delete`,
`slack_react`, `slack_unreact`, `slack_file_upload`, pins, bookmarks.

`slack_api_read` is the read escape hatch (allowlisted Web API methods).
`slack_api_write` is the write escape hatch. It refuses unless `approved=true`
and `SLACK_BRIDGE_ALLOW_API_WRITE=true`.

Prefer the semantic tools. Use the escape hatch only for a method the
canonical surface does not expose.
