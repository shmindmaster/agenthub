---
name: slack
description: Use when searching, reading, posting, reacting, or threading Slack from any coding-agent host. AgentHub owns Slack read/write; host-native Slack plugins are optional UX only.
---

<!-- skill-kind: provider-reference -->
<!-- provider-channel: mcp -->

# Slack (AgentHub)

Fleet id: `slack` in `registry/mcps.json` and `registry/capabilities.json`.
Package: `packages/slack`. Canonical tools and input schemas:
`packages/slack/schemas/tools.json`.

Do not treat Claude, Cursor, Codex, Gemini, or any other host plugin as the
Slack integration. Those may add commands. They do not own identity, schemas,
or fidelity.

## 1. When to load

Load this skill for workspace Slack work: find a report, read a thread, see
who is on it, correlate with GitHub, reply in the same thread.

If the Slack MCP plugin is disabled, say so and stop. Do not enable it, edit
host MCP config, or start a second Slack login to be helpful.

## 2. Contract

Use AgentHub tools only (`slack_search`, `slack_thread`, `slack_reply`, ...).
Keep Slack IDs (`channel_id`, `ts`, `thread_ts`, `user_id`, `file_id`).
Hydration is additive: names never replace IDs. Expect a `raw` object on
every message.

Prefer:

`slack_thread` with `channel_id=C0REPORTS` and `ts=1789051234.123456`

Avoid:

a Markdown summary that drops `ts`, reactions, files, bot/app authors, or edits

Details: [threads.md](references/threads.md), [messaging.md](references/messaging.md),
[search.md](references/search.md), [identity.md](references/identity.md),
[rich-content.md](references/rich-content.md), [writes.md](references/writes.md).

## 3. Identity

One AgentHub Slack identity. Default `actor_mode=user` (Sarosh). `agent_bot`
only when the task says the bot should speak. The coding host must not change
the actor.

## 4. Writes

Reads are the default. Post, reply, edit, delete, react, upload, pin, and
`slack_api_write` need the user to authorize the exact destination and action.
`slack_api_write` also needs `approved=true` and `SLACK_BRIDGE_ALLOW_API_WRITE=true`.

## 5. Official Slack MCP / plugin

Slack's hosted MCP is optimized for human-readable answers and is not this
contract. `slackapi/slack-skills-plugin` is optional UX. Do not install it to
"fill a gap" on Codex, Gemini, or OpenCode. The gap is AgentHub's to close.

## 6. Final check

- Used AgentHub tools, not a host-native Slack MCP
- Kept `channel_id`, `ts`, `thread_ts`, authorship, reactions, files, permalink
- Did not enable the plugin or invent a second Slack login
- Writes were explicitly authorized
