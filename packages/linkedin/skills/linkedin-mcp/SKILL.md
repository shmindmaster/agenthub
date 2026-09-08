---
name: linkedin-mcp
description: Use when the user explicitly asks for LinkedIn profile, company, job, post, feed, inbox, recruiting, or outreach data through the LinkedIn MCP server.
---

<!-- skill-kind: provider-reference -->
<!-- provider-channel: mcp -->

# LinkedIn MCP

Official server: `mcp-server-linkedin@4.24.0` (https://github.com/stickerdaniel/linkedin-mcp-server).
Fleet id: `linkedin` in `registry/mcps.json`. Plugin package: `packages/linkedin`.

Do **not** persist this server in host MCP config. A stdio MCP named in a host
config starts at session start. Enable the `linkedin` plugin (or OpenCode
`mcp.linkedin.enabled`) only for an explicit LinkedIn request; disable when done.

## Operating rules

- Start with the smallest read that answers the request.
- Treat results as live LinkedIn evidence. Distinguish retrieved facts from inference.
- Keep searches modest. Do not bulk scrape.
- If the plugin or MCP is disabled, say so and stop. Do not enable it, edit host
  config, or start a login merely because LinkedIn might be useful.
- `send_message` and `connect_with_person` are writes. Use them only when the
  user authorizes the exact recipient and action.

## Auth

The server uses a managed Chromium session under `~/.linkedin-mcp/`. First data
request may import a local browser session or open a login window. Captcha or
2FA: stop and ask the user to finish it. Do not clear the user's profile.

## Tools

- Profiles: `get_my_profile`, `get_person_profile`, `search_people`, `get_sidebar_profiles`
- Companies: `get_company_profile`, `get_company_posts`, `search_companies`, `get_company_employees`
- Jobs: `search_jobs`, `get_saved_jobs`, `get_job_details`
- Content: `get_feed`, `search_posts`
- Messages: `get_inbox`, `get_conversation`, `search_conversations`
- Writes: `send_message`, `connect_with_person`
- Cleanup: `close_session` when the LinkedIn task is finished
