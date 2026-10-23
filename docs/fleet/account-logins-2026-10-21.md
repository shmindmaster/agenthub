# Owner-only account login checklist — 2026-10-21

The 2026-10-21 owner direction is to use account/subscription authentication
where a supported CLI offers it. These logins are interactive and must be
completed by the owner in a private terminal. No login command was run during
this change. Account-authenticated dispatcher smokes were attempted only where
the owner authorized them; failures remain disabled in `dispatchPolicy`.

Gemini's local `~/.gemini/settings.json` selects
`security.auth.selectedType: "oauth-personal"`. The bounded account-mode smoke
exited 1 without a response. Its dispatcher child had `GOOGLE_API_KEY` and
`GEMINI_API_KEY` removed; no API-key fallback was used.

## Verified host gates

| Host | State on 2026-10-21 |
| --- | --- |
| Cursor Agent | Account-mode dispatcher smoke exited 0 in 23.4 s, but returned no response text. Disabled pending verified model access. |
| Amp | Account-mode dispatcher smoke exited 0 in 22 s, but stopped at MCP OAuth prompts. The plan was not reported; disabled. |
| Gemini CLI | Account-mode dispatcher smoke exited 1 in 1.6 s without a response; disabled. |
| OpenCode Go | `~/.local/share/opencode/auth.json` has no Go-plan account entry. Disabled pending Go login. |
| Warp/Oz | `warp auth status` is not supported. Oz CLI help lists agent/run and cloud-run surfaces; local-only account access was not established, so no smoke was run. |
| Codex | Remains enabled as directed. The ChatGPT-plan quota was exhausted at 22:00 CT; see `dispatchPolicy.codex.knownIssue`. |

1. **Gemini CLI** — verify the selected Google account OAuth login using
   `gemini`. The latest dispatcher smoke failed; confirm account
   authentication and model access before another authorized smoke. Do not
   enter an API key.
2. **OpenCode Go** — run `opencode auth login`. Select the OpenCode Go account
   flow and complete the browser/account prompt. The current auth file has no
   Go-plan entry. Keep the existing DeepSeek secondary provider configuration.
3. **Grok CLI** — run `grok login --oauth`. Complete the xAI account OAuth
   prompt in the browser.
4. **Devin CLI** — run `devin auth login`. Complete the Devin account sign-in.
5. **Windsurf alias** — this fleet entry routes to the same local Devin CLI.
   Run `devin auth login` once; it is not a separate Windsurf credential flow.
6. **GitHub Copilot CLI** — first run `gh auth status`. The active `shmindmaster`
   account was previously verified for this checkout. If it is no longer the
   intended account, run `gh auth login`, select GitHub.com, and complete the
   browser flow.
7. **Codex CLI** — run `codex login`. Select the ChatGPT account/subscription
   flow and complete browser sign-in.
8. **Claude Code** — run `claude auth login` with the normal default config
   directory and complete Claude.ai account sign-in. Do not set
   `CLAUDE_CONFIG_DIR` to `~/.claude-api`; that directory remains for explicit
   API-key runs only.
9. **Cline** — run `cline auth`. Complete the interactive account/provider
   authentication flow; use the account-backed Cline plan rather than an API
   key for the primary provider.
10. **Factory Droid** — run `droid`, then enter `/login` at its interactive
    prompt. Complete the Factory account sign-in.
11. **Cursor Agent CLI** — run `cursor-agent login` if account access needs
    repair. The latest smoke returned no response text; keep dispatch disabled
    until model access and a requested response are verified.
12. **Antigravity CLI** — run `agy`. Complete its interactive Google account
    sign-in.
13. **Amp CLI** — run `amp login` if account access needs repair. The latest
    smoke stopped at MCP OAuth prompts and did not report an account plan.
14. **Warp CLI** — run `warp login` only after a supported account-status and
    local execution path are established. The current Oz CLI help did not
    expose an auth-status command.

The registry records each supported CLI's `authMode` and login command in
`registry/fleet-profile.json` -> `hostSettings`. Account login does not by
itself establish model access, included allowance, or dispatch readiness.
