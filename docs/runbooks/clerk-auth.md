# Clerk tooling and genuine user acceptance

Clerk is the fleet standard for personal application authentication and organization
roles/permissions. Client systems remain separate. Keep tenant membership, ownership, resource authorization,
financial approval rules and storage authorization enforced by the application
backend. A Clerk organization role alone does not grant access to every row,
citation, export or tenant. Existing migrations remain explicit product work.

## Official ownership and rollout

Use [Clerk's official plugin](https://github.com/clerk/skills), which now bundles
20 skills and the [hosted MCP](https://clerk.com/docs/guides/ai/mcp/clerk-mcp-server)
at `https://mcp.clerk.com/mcp`. Do not restore `clerk@agenthub`, vendor these
skills into this marketplace, or build another Clerk backend. The old Codex
`clerk-skills@clerk` has been replaced by `clerk@clerk`; remove the old plugin
only after verifying that exact retired installation exists.

Run `python scripts/Install-ClerkFleet.py` for a read-only plan, then add
`--apply` to install, or `--host <id>` for a targeted repair. The script uses
official native marketplaces on Claude, Codex, Copilot, Factory, Qoder and
Devin; Grok and Antigravity install the official upstream checkout. Cursor
loads a real local plugin folder. Cline CLI loads the official plugin through
its package loader; its separate extension needs its documented direct entry.
Amp gets a runtime registration adapter pointing at upstream skills, with the
remote MCP attached only to the routing skill. OpenCode, Warp and Gemini get
host-local upstream skills and a direct remote entry; VS Code Insiders uses the
Copilot plugin catalog and its own MCP configuration. Desktop/CLI aliases share
their primary host configuration. Nothing is copied into `~/.agents/skills`.

Use `--audit` for independent filesystem readback: all 20 official skill texts
must match the upstream checkout (allowing platform line ending normalization)
and each host's Clerk entry must name the exact official URL. This verifies
configuration, not host loading or OAuth. Preserve the output privately.

The upstream checkout and timestamped commit receipt live under
`%LOCALAPPDATA%/AgentHub/clerk`, outside Git. The installer never starts a coding
session or signs in. A completed installation means files/host management
commands succeeded, not that a fresh host session discovered tools, that OAuth
finished, or that a licensed host can execute. Gemini's known unavailable
license is still a runtime blocker after preparing settings. Restart/reload
each affected host and verify its skill list and MCP tool discovery before
claiming parity. Keep remote servers off by default where the host supports
it, using the switches in [plugin-deployment.md](plugin-deployment.md). Do not
erase OAuth state to repair a disabled server.

The official [CLI](https://github.com/clerk/cli) is the `clerk` executable
(npm package `clerk`, not `@clerk/cli`). Check `clerk --version` and command
`--help` first. Account/platform login uses the workstation's OS keychain and
browser callback. Existing authorized instance BAPI work can instead use an
approved `CLERK_SECRET_KEY` resolved from 1Password into the child process's
memory-only environment; account OAuth is not a prerequisite for that route.
Keep either transport on the workstation, never transfer credentials into a cloud test sandbox.
`clerk mcp` manages the hosted server; `clerk init` can create a development
application and write local keys, so it is not an audit command for an existing
application. MCP OAuth is a separate host grant; account tools can mutate live
applications. Grant only the permissions needed for the authorized task.
[clerk/mcp-tools](https://github.com/clerk/mcp-tools) is an OAuth integration
library, not an alternative hosted-server launcher. Use the official versioned
[OpenAPI specifications](https://github.com/clerk/openapi-specs) for exact FAPI
and BAPI request contracts.

### Codex on-demand activation and connection checks

Codex CLI 0.166 resolves the installed plugin server by the plain name `clerk`:
use `codex mcp login clerk --no-browser` for management-only OAuth. Complete
consent only for the authorized workspace and permissions; do not print tokens
or raw callback URLs. This does not start a model session.

For an authorized task, temporarily set the existing
`[plugins."clerk@clerk".mcp_servers.clerk]` `enabled` field to `true`, preserving
all other settings and grants. Restore its previous value afterward. In this
version, `-c` for that nested plugin setting did not activate the server. Do not
create a duplicate top-level MCP entry as a workaround. `codex mcp list --json`
reports `o_auth` while enabled; a disabled server can report `unsupported`
despite a completed OAuth grant.

For a real connection check without a model or thread, the official app-server
protocol supports `mcpServerStatus/list` with `serverName: "clerk"` and
`detail: "toolsAndAuthOnly"`. Filter to that server rather than discovering
every installed MCP. Verify its live tool inventory and `authStatus: "oAuth"`,
then stop the owned management process and restore the default off setting.
This proves authenticated discovery, not invocation of every tool, application
role acceptance or OAuth on another host.

### Other hosts: native management and isolated discovery

Use management commands without starting a model conversation. Claude's installed
official plugin resolves as `plugin:clerk:clerk`: run
`claude mcp login plugin:clerk:clerk --no-browser`, then
`claude mcp get plugin:clerk:clerk` and require `Connected`. Devin resolves the
official plugin as `clerk`: `devin mcp login clerk` completes its own OAuth;
`devin mcp get clerk` confirms configuration but does not prove live tool discovery.
Each grant belongs to that host; do not copy a token from Codex or another host.

Cursor CLI does not discover the IDE's installed plugin server in the tested
version. `python scripts/Prepare-ClerkManagement.py --host cursor --apply`
prepares a private, on-demand management directory under
`%LOCALAPPDATA%/AgentHub/clerk/management/cursor`, preserving the IDE plugin and
global settings. From that directory, run `cursor-agent mcp enable clerk`,
`cursor-agent mcp login clerk`, and `cursor-agent mcp list-tools clerk`.
The last command must return a fresh live inventory. This proves that isolated
CLI configuration; separately verify the IDE plugin before claiming IDE parity.
Disable the isolated server again after an authorized task if it is no longer
needed. The preparation helper neither logs in nor accesses credential stores.

Host commands and OAuth support change. Check installed `--help` and current
vendor documentation before using a route. In particular, Amp's legacy
`mcp oauth login` requires a registered client ID; an arbitrary ID or another
host's client identity is not a repair. Factory's unfiltered `mcp auth` can
authenticate every configured server: isolate Clerk using supported management
configuration rather than granting unrelated integrations. An installed plugin,
configuration readback, successful OAuth callback, live tool inventory and an
IDE's authenticated runtime remain separate evidence stages.

### Immediate application-session revocation

JWT signature/expiry validation alone can accept an already issued token until
its short expiry after the provider session is revoked. Products requiring
immediate revocation must check the verified token's session ID against current
provider state before serving protected resources. Match the session ID and user
subject, require active status, bound the actual network request, reject redirects
and fail closed on provider errors. Do not reuse a positive session state across
requests if immediate revocation is the contract. Record the additional provider
request volume and availability dependency. Test the same unexpired token before
and immediately after revoking only the harness-created session, then separately
test refresh denial, role removal, organization membership removal and resource
isolation. A mocked provider response is a regression test, not deployed proof.

## Acceptance matrix

For each deployed application/revision record the exact URL, source SHA,
synthetic tenant, real user subject, app role, timestamp and result. Keep raw
credentials and session material private; resolve approved 1Password references
only at runtime. Never put tokens, passwords, OTPs or authenticated storage
state in Git, chat, screenshots or shared artifacts.

| Layer | Required evidence |
| --- | --- |
| Genuine sign-in | Fresh browser context through the deployed application's normal Clerk UI, real password/SSO and required MFA/Device Trust challenge; backend verifies the resulting normal user session. Reload and sign out/revocation behave correctly. |
| Role mapping | Separate real admin, editor/CFO and viewer sessions; verify app role and tenant membership from backend readback. Also test pending, revoked and unaffiliated users. |
| Denial | Unauthenticated requests fail; viewer mutations fail; another tenant and guessed resource IDs fail. Check both UI and direct backend calls using each user's actual session. |
| Data boundaries | List/detail/search, source citations, attachments, generated reports, export job creation/status/download and retained publication URLs enforce the same tenant/resource rules. Never infer authorization from a hidden button or unguessable URL. |
| Changed authority | Revoke membership/permission and verify access ends; switch organizations without retaining previous tenant data. Signed URLs and cached/retained artifacts follow the product's explicit policy. |
| Workflow integrity | Verify human review/signoff and stale-source rejection, immutable retained publications, fresh review and replacement version where the product supports them. No admin impersonation as a normal-role substitute. |

Validate JWT signature, issuer, expiry and applicable audience/authorized-party
constraints server-side through supported Clerk SDKs. Derive the active tenant
from verified membership; never trust a body/header tenant ID alone. Use Clerk
custom permissions for application actions and enforce domain/resource rules
afterward. [Server-side `has()`](https://clerk.com/docs/guides/secure/authorization-checks)
checks custom permissions; Clerk system permissions are not in session claims.

Official testing tokens, mocked JWTs, development test emails/OTPs and auth
bypass are useful isolated development checks. Label them as such. They do not
establish deployed normal-role acceptance. BAPI user provisioning, sign-in
tickets or impersonation likewise do not establish genuine UI sign-in.

If a synthetic inbox cannot receive the real challenge, record the exact
blocker. Never invent an inbox code, enable production test mode, or globally
disable Device Trust/MFA. An explicitly authorized exception for one exact
synthetic QA user, such as `bypass_client_trust`, must be scoped and recorded;
it is not production challenge coverage. Check whether the deployed sign-in UI
actually offers password entry: existing verified users with passwords do not
prove that the instance's password sign-up/sign-in settings expose that flow.
Changes to instance-wide authentication settings need their own authorized
scope and before/after readback.

Report each stage separately: installed/configured, fresh-session discovery,
OAuth authenticated, development harness passed, genuine UI/backend role
acceptance passed, deployed revision verified. Any unperformed stage remains
blocked or unverified, with the concrete next action.

## Cursor companion rule

The registry owns the dedicated Cursor rule destination; the Clerk installer
renders only the following bounded policy block. Existing user rules are
preserved. [Cursor documents user rule files in `~/.cursor/rules`](https://prod.cursor.com/help/customization/rules).
This establishes a documented IDE destination, not fresh-session discovery or
CLI global-rule loading. Warp global rules require its separate Warp Drive UI;
the installer does not launch Warp or claim that policy has been activated there.

<!-- clerk-companion:start -->
Use Clerk for personal application authentication and organization permissions;
client systems remain separate. Use the official Clerk skills, hosted MCP and
CLI. Enforce tenant membership, app roles, resource ownership and domain rules
on the backend; organization membership alone does not authorize resources.

For auth changes, verify genuine deployed UI sign-in and direct backend access
with separate real admin, editor/CFO and viewer sessions. Test denied anonymous,
revoked and cross-tenant access, including citations, attachments and exports.
Mocked JWTs, dev testing tokens and impersonation do not prove real user access.
Resolve approved 1Password references only at runtime; never print credentials,
invent inbox codes or globally weaken MFA/Device Trust for QA. Report host
installation, discovery, OAuth and actual role acceptance as separate stages.

Read the full acceptance contract at https://github.com/shmindmaster/agenthub/blob/main/docs/runbooks/clerk-auth.md.
<!-- clerk-companion:end -->
