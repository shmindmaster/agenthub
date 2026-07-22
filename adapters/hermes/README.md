# Hermes Agent adapter

- Native Windows home: `%LOCALAPPDATA%\hermes`
- Executable: `%LOCALAPPDATA%\hermes\hermes-agent\venv\Scripts\hermes.exe`
- Configuration: `config.yaml`
- Native instructions/personality: `SOUL.md`; generated policy is appended without replacing Hermes' unique personality
- Skills/hooks: `skills\` and `hooks\`
- Validation: `hermes --version`, `hermes config check`, and `hermes doctor`

Windows is authoritative. No intentional Hermes WSL installation is registered. `.env`, auth, sessions, memories, and state databases remain unmanaged.
