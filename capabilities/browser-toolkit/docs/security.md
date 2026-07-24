# Security and privacy

Primary risk: a connected DevTools agent can control every tab and read the
DOM, accessibility tree, cookies/storage-derived application state, console,
requests/responses, and authenticated data available to that browser profile.

Mitigations:

- never connect to the normal Chrome instance on port 9222;
- use the dedicated shared profile on 9333 or isolated profiles on 9341–9344;
- use synthetic accounts/data and distinct server-side namespaces;
- close unrelated tabs and disable notifications/sync;
- keep CDP loopback-only and do not expose it through a firewall, tunnel, or
  container port;
- disable MCP usage statistics, CrUX lookup, and redact network headers;
- keep experimental flags off;
- require `ask` or equivalent permission for browser actions;
- sanitize screenshots, traces, logs, videos, captions, and manifests;
- never hardcode tokens; rotate any token exposed in terminal/transcript
  output;
- use Qwen Computer Use only for justified native UI and keep Windows-control
  MCPs absent.

Remaining exposure includes visible synthetic session data, server-side
mutations made by the agent, browser extensions/VPN behavior installed in that
QA profile, and any secrets the application itself renders. Human review is
required before external release.
