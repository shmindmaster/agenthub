// Server-side approval gate for every Slack write.
//
// Before this module only slack_api_write refused an unapproved call; the
// other write tools relied on prose ("Requires explicit user authorization")
// that nothing enforced (API surface audit, M7, 2026-10-14). The gate runs in
// slack-mcp.mjs before any backend is touched, so a host or agent that skips
// the instruction still cannot write.
//
// Two rules, both fail-closed:
//   1. Every write call carries approved=true. The agent sets it only after
//      the user approved that exact destination and action.
//   2. A write never lands in the fixture workspace by accident. When no token
//      is configured the server falls back to fixtures for reads; writes are
//      refused unless the operator explicitly chose SLACK_BRIDGE_MODE=fixture.

// Tools whose every call mutates Slack.
export const WRITE_TOOLS = new Set([
  'slack_post',
  'slack_reply',
  'slack_update',
  'slack_delete',
  'slack_react',
  'slack_unreact',
  'slack_file_upload',
  'slack_pin',
  'slack_unpin',
  'slack_api_write',
]);

// Tools that read or write depending on an argument.
const CONDITIONAL_WRITES = {
  slack_bookmarks: (args) => args.action === 'add' || args.action === 'remove',
};

export function isWriteCall(name, args = {}) {
  if (WRITE_TOOLS.has(name)) return true;
  const conditional = CONDITIONAL_WRITES[name];
  return Boolean(conditional && conditional(args));
}

export function assertWriteAllowed(name, args = {}, backend = {}) {
  if (!isWriteCall(name, args)) return;
  if (args.approved !== true) {
    throw new Error(
      `${name} is a Slack write and requires approved=true, set only after the user approved this exact destination and action`,
    );
  }
  if (backend.source === 'fallback-fixture') {
    throw new Error(
      `${name} refused: no SLACK_USER_TOKEN or SLACK_BOT_TOKEN is configured, so this write would land in the fixture workspace by accident. Set SLACK_BRIDGE_MODE=fixture to write to fixtures on purpose.`,
    );
  }
}
