# Gemini CLI adapter

- Native home: `C:\Users\SaroshHussain\.gemini`
- Settings: `settings.json`
- Instructions: generated `GEMINI.md`, with repository `AGENTS.md` authoritative
- Skills: shared `.agents\skills` plus Gemini-only `.gemini\skills`; duplicate names are not deployed twice
- MCP: `mcpServers` in `settings.json`
- Model mapping: `gemini-3.6-flash-high` resolves to `gemini-3.6-flash` with `thinkingLevel=HIGH` through dynamic model configuration
- Autonomy mapping: launcher flags implement the selected local profile; the canonical profile remains in `profiles/`
- Validation: `gemini --version` and a JSON prompt whose stats report the expected model

Gemini credentials, sessions, caches, and provider state remain host-local.
