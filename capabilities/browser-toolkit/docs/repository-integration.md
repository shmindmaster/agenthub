# Repository integration

## Vite React Tailwind

Use repository-native commands. Add the DevTools JSON plugin only after the
evaluation in `integrations/README.md`; preserve the Tailwind/Vite plugin order.
Run the existing test, typecheck, dev, and production build commands.

## Next.js React Tailwind

Do not add the Vite plugin. Use Next.js source maps and diagnostics. Keep
repository-owned Playwright fixtures and `webServer` commands unchanged.

## Monorepo

Install the toolkit once. Each application owns its start, auth, seed/reset, and
artifact commands. Use unique ports and seed namespaces for parallel packages.
Test Windows, WSL, container, and paths-with-spaces mappings actually used.

## Existing Playwright

Preserve its version, lockfile, projects, fixtures, reporters, baselines, and
CI. Use Chrome DevTools MCP for live authenticated diagnosis; add or update
Playwright tests only under the repository's own conventions.

## No deterministic seed/reset

Stop master capture and return `READINESS_REPORT_ONLY`. Add an idempotent,
synthetic, environment-guarded seed/reset contract; verify persisted outcomes
and reset evidence before claiming deterministic E2E or demo readiness.
