# Warp / Oz adapter

- Native executable: `%LOCALAPPDATA%\Programs\Warp\warp.exe`
- Oz CLI: `%LOCALAPPDATA%\Programs\Warp\bin\oz.cmd`
- MCP: `C:\Users\SaroshHussain\.warp\.mcp.json`
- Skills: repository or shared agent skills exposed through Warp's documented skill mechanism
- Cloud environments are companion execution surfaces, not capability owners
- Validation: `warp --version`, MCP JSON parsing, and account-neutral environment listing only when explicitly requested

API keys, cloud secrets, run state, and repository-specific environment identifiers remain outside generated adapter files.
