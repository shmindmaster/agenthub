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
The dispatcher refused `cursor` under its interactive autonomy profile;
`cursor-agent` remains disabled by its existing policy gate.

No deployed copies under `%LOCALAPPDATA%\AgentHub` were changed; deployment is
a separate step.
