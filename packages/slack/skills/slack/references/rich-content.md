# Rich content

Blocks, attachments, and files stay on the message. Do not flatten them into
text and drop the structured fields.

- Files: `slack_file_get` / `slack_file_upload` (`file_id` required)
- Canvases: `slack_canvas_get`
- Lists: `slack_list_items`
- Pins: `slack_pin` / `slack_unpin`
- Bookmarks: `slack_bookmarks` with `action=list|add|remove`
