# Verification report — 2026-07-23

## Outcome

The canonical toolkit and four enabled adapters are configured in `Shared` mode
on dedicated QA Chrome port 9333. Cursor is staged but not activated because its
provider hold remains active. No product demo was produced because no real
product repository/workflow was placed in scope; the correct outcome is
readiness infrastructure only.

| Component | Status | Command/evidence |
| --- | --- | --- |
| Toolkit schemas/files | Verified | `npm run check` — 45 files |
| Dependency security | Verified | `npm audit --audit-level=moderate` — 0 vulnerabilities |
| Chrome DevTools MCP 1.6.0 | Verified | shared-profile smoke at `reports/browser-toolkit/20260723-191708`; final clean-profile smoke at `reports/browser-toolkit/20260723-194036` |
| Snapshot, fill, click, submit | Verified | smoke report business outcome `Submitted: Ada Lovelace` |
| Screenshot | Verified | `smoke.png` in evidence folder |
| Console/network | Verified | one expected info message; GET/POST 200 |
| Lighthouse | Verified | accessibility/best-practices/agentic-browser audit captured |
| Shared QA Chrome | Partially verified | Chrome 150 on `127.0.0.1:9333`; earlier full smoke passed, while the final rerun reached the asserted result but its screenshot request timed out. Treat the shared profile as single-owner and use an isolated profile when it is busy. |
| Two-agent isolation | Verified | concurrent Claude/Qwen profile smokes on 9341/9342; `reports/browser-toolkit/concurrency-20260723-192916` |
| Claude MCP discovery | Verified | `claude mcp list`: Chrome DevTools connected |
| OpenCode MCP discovery | Verified | `opencode mcp list`: Chrome DevTools connected |
| Hermes MCP discovery | Verified | `hermes mcp test chrome-devtools`: 29 tools |
| Qwen extension/skills | Verified | `qwen --list-extensions`: browser/product skills including `product-demo-studio-visual-assets` |
| Qwen MCP through agent CLI | Partially verified | MCP configuration and extension discovery pass; interactive `/mcp` remains to be exercised because the noninteractive `qwen mcp list` command is not supported by this installed CLI shape |
| Qwen model response | Verified | `qwen -p "Reply with exactly: QWEN_AUTH_OK" --output-format text` returned the exact expected result using `QWEN_API_KEY` |
| Claude model response through QwenCloud | Verified | `claude -p ...` returned the exact expected result using the required `ANTHROPIC_AUTH_TOKEN` alias synchronized from `QWEN_API_KEY` |
| OpenCode model response through QwenCloud | Verified | `opencode run --model qwen-token-plan/qwen3.7-max ...` returned the exact expected result |
| Hermes model response through QwenCloud | Verified | `hermes -z ...` returned the exact expected result |
| Cursor adapter | Blocked | provider hold; no Cursor invocation, activation, or provider mutation |
| Product Demo Studio 0.6.1 | Verified | guide hash validator and `claude plugin validate`; Claude cache updated, prior disabled state preserved |
| Product Experience Engineering 1.1.0 | Verified | complete plugin test suite; Claude cache updated, prior disabled state preserved |
| Qwen native extension propagation | Verified | junction inventory contains new/updated skills |
| OpenCode/Hermes loose-skill propagation | Verified | targeted sync with backups under `%LOCALAPPDATA%\AgentHub\handoff-skill-backups` |
| Playwright | Partially verified | existing installations preserved; this toolkit neither installs nor owns them |
| Computer Use | Partially verified | Qwen 0.20.1 setting enabled; native desktop action not run because no justified workflow was in scope |
| Vite integration | Not verified | conditional fragment supplied; no Vite repository was placed in scope |
| Next.js integration | Not verified | no plugin applied; no Next.js repository was placed in scope |
| WSL/container/monorepo/path-with-spaces | Not verified | documented, but no target fixtures/environments were supplied |
| Real product audit/remediation | Not verified | no product repository/workflow supplied |
| Demo/video | Not verified | fail-closed: no current product audit/readiness handoff, so no video |

## Credential incident

An obsolete, noncanonical Qwen/Anthropic alias value was inadvertently echoed
in local command output during diagnostics. It differed from the user's
canonical `QWEN_API_KEY` and is no longer referenced by Qwen Code, OpenCode, or
Hermes. The canonical value was not printed. Active configurations now use
`QWEN_API_KEY`, with only Claude's required `ANTHROPIC_AUTH_TOKEN` compatibility
alias synchronized to the same value. The obsolete
`BAILIAN_TOKEN_PLAN_API_KEY` user variable should be removed after confirming
that no unrelated local application still uses it.

## Known unrelated observations

Claude MCP health reported its GitHub connector unavailable. Qwen/OpenCode
reported a Notion MCP issue. These pre-existing, non-browser connectors are
outside this toolkit and do not invalidate the isolated Chrome smoke.
