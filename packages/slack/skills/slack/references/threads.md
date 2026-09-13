# Threads

A thread is `channel_id` + parent `ts`. Replies use that parent `ts` as
`thread_ts`.

`slack_reply` requires both. Posting without `thread_ts` creates a new top-level
message.

When investigating an incident: search, open the full thread, read reactions
and files, then reply in the same thread. Do not start a new channel message.
