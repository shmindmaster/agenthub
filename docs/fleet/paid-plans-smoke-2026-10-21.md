# Paid-plan dispatcher smokes — 2026-10-21

Each row is one invocation of the installed `use-coding-agent` dispatcher with
the prompt `reply with the single word ok`, the AgentHub repository as `-Cwd`,
and a 120-second timeout. Durations include dispatcher startup.

| Host | Selected model | Exit code | Duration | Result |
| --- | --- | ---: | ---: | --- |
| cline | `cline-pass/qwen3.8-max` | 0 | 16.2 s | Returned `ok` |
| opencode | `opencode-go/hy3` | 1 | 26.3 s | Failed; dispatch remains disabled |
| copilot | `auto` | 0 | 14.3 s | No response text captured by dispatcher |
| codex | `gpt-6.1-sol` | 0 | 9.0 s | No response text captured by dispatcher |
| devin | `swe-2-medium-lightning` | 0 | 4.7 s | Returned `ok` |
| factory | `openai-latest-balanced` | 0 | 15.2 s | Returned `ok` |
| windsurf | `swe-2-medium-lightning` (Devin alias) | 0 | 3.9 s | Returned `ok` |
| gemini | configured CLI default | 0 | 7.8 s | Returned `ok` |
| grok | configured CLI default | 0 | 10.3 s | Returned `ok` |
| antigravity | configured CLI default | 0 | 14.9 s | Returned `ok` |

OpenCode remains disabled in `registry/fleet-profile.json` pending owner
verification and another authorized smoke. Copilot and Codex exited
successfully, but their dispatcher stdout did not contain a standalone `ok`.
The prior Gemini `ok` was from its configured default route and does not
establish account-authenticated access. Cursor routes to `cursor-agent`; its
new account-mode smoke returned no response text. The earlier `cursor` refusal
was superseded by the direct `cursor-agent` smoke below; dispatch remains
disabled because the requested response was not captured.

## Account-mode follow-up

These checks used the dispatcher from the source checkout, a temporary empty
working directory, and the prompt `Reply with the single word ok.`. The
account-authenticated host API-key overrides were removed by the dispatcher.

| Host | Model | Auth mode | Smoke result | Current status |
| --- | --- | --- | --- | --- |
| cursor-agent | Not established | account | Exit 0, 23.4 s; no response text | Disabled |
| amp | Not reported | account | Exit 0, 22 s; MCP OAuth prompts, no task response or plan | Disabled |
| gemini | CLI default not established | account | Exit 1, 1.6 s; no response | Disabled |
| opencode | `opencode-go/hy3` | account | Not run; auth file has no Go-plan account entry | Disabled; awaiting Go login |
| warp | Not established | account | Not run; `warp auth status` unsupported and local-only mode unverified | Disabled |
| codex | `gpt-6.1-sol` | account | Not run; quota exhausted at 22:00 CT | Enabled as directed; quota blocks use |

CodeRabbit CLI is review-only, not a general-purpose coding host. Its attempted
help probe launched a repository review, so it was not added to the dispatcher
or invoked again. Other inventory items absent from `managedHosts` are GUI,
research, indexing, search, companion, or device-control tools without a
verified coding-task contract.

No deployed copies under `%LOCALAPPDATA%\AgentHub` were changed; deployment is
a separate step.
