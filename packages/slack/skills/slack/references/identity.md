# Identity

One AgentHub-owned Slack app and user OAuth. Every host uses that identity.

`actor_mode`:

- `user` (default) — the authenticated human (Sarosh)
- `agent_bot` — the AgentHub bot token, only when the task says so

Do not infer actor from Claude vs Codex vs Cursor. Host is not identity.

`slack_whoami` returns `user_id`, `bot_id`, `team_id`. Names are additive.

Tokens are environment references only: `SLACK_USER_TOKEN`, optional
`SLACK_BOT_TOKEN`. Never write values into the registry or a host config.
