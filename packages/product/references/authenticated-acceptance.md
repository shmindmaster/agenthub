# Authenticated acceptance

## Contents

- Why mocked auth does not count
- Required evidence per layer
- Session and credential handling
- Reporting stages separately

## Why mocked auth does not count

A real signed-in session is the only thing that exercises authorization. Vendor
testing tokens, mocked JWTs, development test codes and backend impersonation
are isolated development checks. Label them as such. They do not establish that
a user of a given role can and cannot do what the product claims, and they never
substitute for a deployed sign-in. Provisioning a user through an admin API is
not a sign-in either.

A hidden button or an unguessable URL is not authorization. Every rule the UI
implies must also hold on a direct backend call carrying that same user's own
session.

## Required evidence per layer

Record the exact URL, source revision, synthetic tenant, user subject, role,
timestamp and result for each row.

| Layer | Required evidence |
|---|---|
| Genuine sign-in | Fresh browser context through the deployed app's normal sign-in UI, real credentials and any required second factor; the backend verifies the resulting session. Reload, sign-out and revocation behave correctly. |
| Role mapping | Separate real sessions per role, for example admin, editor and viewer. Read role and tenant back from the backend, not from the UI. Cover pending, revoked and unaffiliated users. |
| Denial | Unauthenticated requests fail. Viewer mutations fail. Another tenant's data and guessed resource IDs fail. Check the UI and a direct backend call for each. |
| Data boundaries | List, detail, search, citations, attachments, generated reports, export creation, status and download, and any retained public URL all enforce the same tenant and resource rules. |
| Changed authority | Revoke a membership or permission and confirm access ends. Switch tenants and confirm no data carries over. Signed URLs and cached artifacts follow the product's stated policy. |
| Workflow integrity | Human review and sign-off hold, stale input is rejected, and published artifacts are immutable where the product promises it. Admin impersonation is not a substitute for a normal role. |

## Session and credential handling

Keep raw credentials and session material out of Git, chat, screenshots and
shared artifacts. Resolve approved secret references only at runtime, and print
a variable's name and whether it is set rather than its value.

Validate signature, issuer, expiry and audience server-side through the
supported SDK. Derive the active tenant from verified membership; never trust a
tenant ID in a request body or header alone. Check fine-grained permissions on
the server after membership is established, because a role alone rarely
authorizes a specific row, citation or export.

If a synthetic mailbox cannot receive a real challenge, record the exact
blocker. Do not invent a code, enable a production test mode, or disable
second-factor or device-trust enforcement across the instance to make QA pass.
An authorized exception for one named synthetic QA user is scoped and recorded,
and it is not challenge coverage.

Confirm the deployed sign-in UI actually offers the flow under test. Users who
once signed in with a password do not prove the instance's current settings
still expose password entry. Instance-wide authentication changes need their own
authorized scope and a before-and-after readback.

Where the fleet has a standard identity provider, use its official plugin, CLI
and MCP rather than hand-rolled auth, and read that provider's own acceptance
contract before claiming role coverage.

## Reporting stages separately

Report configured, fresh-session discovery, credential or OAuth authentication,
development harness passed, genuine UI and backend role acceptance passed, and
deployed revision verified as distinct stages. Any stage not performed stays
blocked or unverified, with the concrete next action named.
