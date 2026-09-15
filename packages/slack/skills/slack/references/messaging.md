# Messaging

`slack_messages` reads channel history. `slack_thread` reads one thread by
`channel_id` + `ts`. Pagination uses `cursor`; the same cursor must yield the
same page.

A message always includes `channel_id`, `ts`, `thread_ts`, `author.user_id`,
`text`, `blocks`, `attachments`, `files`, `reactions`, `metadata`, `subtype`,
`edited`, `permalink`, and `raw`.

Bot and app authors keep `bot_id` / `app_id`. Edits stay on `edited`.
