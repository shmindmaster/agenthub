# Workflow detail


## 2. Drive the isolated browser

Run every command through the wrapper. It names your session, hides the window, caps output and exits idle browsers.

```bash
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" doctor
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" open <url>
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" snapshot -i
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" click @e3
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" fill @e2 "text"
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" snapshot -i
node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" close
```

`CLAUDE_SKILL_DIR` is filled in when this skill loads. Use that path. Do not call `agent-browser` directly and do not pipe it. Other commands: `press`, `select`, `check`, `upload`, `wait`, `screenshot <path>`, `console`, `network requests`, `set viewport <w> <h>`, `set device <name>`, `set media dark`, `find role button click --name "Save"`, `get text @e1`, `record start`. For any command or flag not listed, run `node "${CLAUDE_SKILL_DIR}/scripts/browse.mjs" skills get core --full`.
