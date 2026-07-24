# Framework integration

Detect the repository before changing it:

```powershell
rg -n '"vite"|"next"|"react-scripts"' package.json **/package.json
rg --files -g 'vite.config.*' -g 'next.config.*' -g 'pnpm-workspace.yaml' -g 'turbo.json'
```

For a real Vite application, evaluate
`vite-plugin-devtools-json@1.1.0`. Add
`integrations/vite/vite.config.fragment.ts` only when live Chrome workspace
mapping is demonstrably useful. Use the repository package manager, preserve
plugin order, choose a stable repository-specific UUID, and rerun native dev,
test, typecheck, and production-build commands on Windows and WSL paths used by
the team.

Do not add this plugin to Next.js. No supported one-for-one Next.js equivalent
was selected; use Next.js source maps, framework diagnostics, and Chrome
DevTools directly. In a monorepo, add the plugin only to actual Vite packages,
not the workspace root by default.
