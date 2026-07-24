# Hermes adapter

Hermes uses `~/.hermes/config.yaml`, its native `custom_providers` format, and
`QWEN_API_KEY`. The configuration script removes an inline
`model.api_key` after confirming the environment variable exists.

Use Hermes native browser for quick headed navigation, normal screenshots, and
simple authenticated browsing. Use Chrome DevTools MCP when console, network,
accessibility-tree, Lighthouse, performance trace, or source-mapped diagnostic
evidence is required. Both may connect to the dedicated QA profile; never use a
personal profile.

Hermes' official Windows installation path is WSL2. Verify with `hermes mcp
list`, `hermes mcp test chrome-devtools`, one model response, one native browser
smoke, and the controlled DevTools smoke.
