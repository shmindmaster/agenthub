# Forge plan routes (MiMo and Qwen token plans)

Read when: choosing a Forge launcher for a lane, or checking which client was smoke-tested on which plan.

Every launcher lives in `/srv/work/agenthub-runner/.local/bin/`, reads its plan key from
`~/.config/agenthub/credentials/{mimo-token-plan,qwen-token-plan}` (mode 0600, runner account only) and
exports it into the child process only. No key is stored in a config file; the opencode-family configs use
`{env:...}`. Cline has no environment key route, so its launcher hands the key once to `cline auth` and keeps it
in a per-plan 0700 data directory (`~/.local/opt/cline-<plan>`).

- MiMo: Singapore Token Plan, `https://token-plan-sgp.xiaomimimo.com/v1` (Anthropic route `/anthropic`). Models `mimo-v2.6-pro` (default), `mimo-v2.6-flash`. The pay-as-you-go API and `sk-` keys are never used.
- Qwen: `https://token-plan.maas.qwencloudapi.com/compatible-mode/v1` (Anthropic route `/apps/anthropic`). Default `qwen4-max-preview`; `qwen3.8-max` and `qwen3.8-flash` also pass. Night (CST) discounts apply to `auto`, `qwen3.8-max` and `qwen3.8-flash`, so batch non-urgent lanes overnight.

Headless one-shot form (run as `agenthub-runner` in a Forge worktree under `/srv/work/agenthub-runner/worktrees/`):

| Host id | Headless command |
|---|---|
| `claude-mimo` / `claude-qwen` | `claude-<plan> -p "<task>" --model <model> [--permission-mode plan]` |
| `codex-mimo` / `codex-qwen` | `codex-<plan> exec [-s read-only] "<task>"` |
| `opencode-mimo` / `opencode-qwen` | `opencode-<plan> run -m <provider>/<model> [--agent plan] "<task>"`; providers `mimo-token-plan`, `qwen-token-plan` |
| `kilo-mimo` / `kilo-qwen` | `kilo-<plan> run -m <provider>/<model> [--agent plan] "<task>"` |
| `mimo-code-mimo` | `mimo-code-mimo run -m mimo-token-plan/<model> [--agent plan] "<task>"` |
| `qwen-mimo` / `qwen-qwen` | `qwen-mimo -p "<task>"` / `qwen-plan -p "<task>" -m <model>` (`--approval-mode plan` is read-only) |
| `cline-mimo` / `cline-qwen` | `cline-<plan> -y -c <dir> "<task>"` (`-p` for plan mode) |

Not routed: MiMo Desktop and ZCode are GUI applications. ZCode on Forge is an AppImage that fails to start
(`libfuse.so.2` missing) and has no CLI entry point. The Qwen `auto` model is refused on the Anthropic route used
by opencode and kilo (`auto does not support parameter(s): tool_choice`); use a named model there.
