# Cursor adapter

Use one `.cursor-plugin` package per capability owner when Cursor-specific installation is needed. Place skills, rules, and MCP configuration in that package; do not duplicate shared API implementation.

Operational hold (2026-07-22): Cursor IDE agents, Cursor Agent CLI,
Cloud/Background Agents, and API sessions are retained but disabled because
quota/spend headroom is exhausted. Do not invoke or probe them until the owner
explicitly re-enables Cursor.
