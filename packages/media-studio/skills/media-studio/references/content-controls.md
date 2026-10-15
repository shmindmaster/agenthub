# Shared content controls

The Media Studio owner supplies `packages/media-studio/scripts/content_runtime.py`.
The ElevenLabs owner supplies `packages/elevenlabs/scripts/elevenlabs_cli.py` and
its mandatory TTS adapter. Resolve these paths from `AGENTHUB_ROOT` or the
canonical AgentHub checkout; never copy a helper into a product repository.
Python 3.11+ and the standard library are sufficient. No daemon or scheduler runs.

## Scope and fail-closed routes

| Route | Enforcement |
| --- | --- |
| Canonical ElevenLabs REST TTS on this OS account/disk | Required exact cache, singleflight, shared reservations and durable recovery |
| Canonical STT and other non-GET requests | Disabled until a conservative metered adapter exists |
| Codex ElevenLabs app | `content_host_controls.py --apply` sets the documented app `enabled=false`; verify fresh native app readback |
| Already-loaded native tools, other connectors, raw SDK/API/shell and provider UI | Not intercepted; cannot be represented as governed |
| Other local agent hosts | Same canonical CLI shares the ledger; native connector denial must be verified per host |
| Remote/cloud agents or another OS account/machine | No shared ledger; paid content must remain disabled pending shared service/credential isolation |
| Host coding/chat subscriptions, other paid APIs, Descript | Outside this adapter's spend accounting; no aggregate billing claim |

This is coordination among cooperating processes, not a security boundary against
programs running as the same unrestricted user. The app block uses Codex's
official app ID from its plugin `.app.json`, rather than the plugin name. It
requires new/reloaded sessions. Config readback alone does not prove removal of
tools already loaded into a chat. Do not claim all-agent provider enforcement
without verified host deny controls and credential isolation. Do not install a
redundant MCP integration or disable the host's coding/chat model.

Official setting: https://developers.openai.com/codex/config-reference
(`apps.<id>.enabled`). Host settings and native registrations must be refreshed
when expanding coverage. Paid specialist examples and Flows do not bypass policy.

## Budget and storage

All participating local hosts use `%LOCALAPPDATA%/AgentHub/runtime/content-controls`.
The CLI has no root override. Tests use isolated synthetic directories. Windows
requires a fixed local disk and rejects linked directory ancestors; runtime DACLs
allow the owner, SYSTEM and Administrators. SQLite uses WAL, FULL synchronous
writes and immediate transactions. The local salt scopes credential/workspace
HMAC namespaces; raw credentials and prompts are not stored. Audio and private
evidence stay local and outside Git. This storage is access-restricted, not
encrypted. Don't move it to OneDrive or a network disk.

The single `elevenlabs/credits` bucket spans all credential/workspace namespaces.
It is a lifetime aggregate ceiling, with no reset or automatic replenishment.
Each purchase reserves the full integer `--max-credits` before provider POST.
Actual unknown costs retain the entire amount. Only exact provider receipts
permit settlement; elapsed time and account-wide usage deltas are insufficient.
Provider overbilling can exceed a reservation; further purchases then fail.
The local cap cannot guarantee an upstream invoice ceiling.

Resolve `$Control` to `packages/media-studio/scripts/content_control.py`:

```powershell
python $Control status
# Only after explicit owner approval of this aggregate amount:
python $Control configure --bucket elevenlabs/credits --ceiling <approved-integer>
python $Control freeze --bucket elevenlabs/credits
# Only an expired reservation that never reached submitted can be released:
python $Control release-prepared --namespace <saved-namespace> --cache-key <saved-key>
```

Freeze sets the ceiling to existing commitments, preserving reuse and recovery;
an unset bucket fails explicitly. Release is atomic with submission and lease
takeover; it refuses live prepared, submitted and unknown reservations.
Agents must never raise/configure a ceiling merely to make a request succeed.
Budgets are operator-managed policy, not protected against same-user edits.

## Exact reuse and recovery

Keys bind provider endpoint, credential/workspace namespace, text/payload, model,
voice, output format, explicit settings, normalization, context/stitch IDs,
versioned dictionaries and `--cache-revision`. That revision must identify locked
voice/model/reference versions; bump it after a remote voice/reference/model
change. Vendor model IDs do not expose all weight revisions, so this is an
operator attestation, not automatic vendor drift detection. No fuzzy matching,
silent model downgrade or prompt rewriting occurs.

One fenced worker reserves/submits an exact request. Others wait and retrieve its
bytes. A crashed prepared worker can be replaced after its lease; a submitted
worker can never be replaced by a fresh purchase. Recovery refuses a submitted
worker until its lease expires, or the worker explicitly records an unknown
outcome. Request IDs are saved as soon as response headers arrive, including HTTP
error responses. A response without an ID never becomes reusable content.
Lost/ambiguous responses retain the reservation and
fail closed. Recover the exact provider history item (GET only):

```powershell
python $Cli reconcile --namespace <saved-namespace> --cache-key <saved-key> --cache-workspace <same-workspace> --history-id <exact-history-id>
```

The active credential/workspace must match the original namespace and history
must match its saved request ID. Missing IDs or unknown billing remain blocked.
Do not delete a ledger row or change revision to retry ambiguous work. An output
write failure leaves the generated asset reusable at a new output destination.

## Acceptance

Generation returns `pending` bytes and provenance for QA. Exact reuse preserves
those bytes and their state; it does not grant delivery approval. Acceptance
requires identity, content, pronunciation, listening and artifact checks. Supply
a private JSON object keyed by those gate names. Each gate must include:

```json
{"pass":true,"output_sha256":"<exact-audio-sha256>","evidence_path":"<absolute-private-report-path>","evidence_sha256":"<report-sha256>","reviewer":"<identified-human-or-QA-tool>"}
```

```powershell
python $Control accept --namespace <saved-namespace> --cache-key <saved-key> --manifest <private-gates.json>
```

The command verifies actual evidence file hashes, output hashes and all required
passes. Reviewers remain responsible for substantive QA; this records evidence,
it does not compute speaker identity or listening quality itself. Assembly still
requires its exact encoded-delivery gates. Corrupt cached bytes fail without a
new purchase. Never fabricate a PASS or treat pending audio as owner-approved.

## Evidence limits

Offline tests exercise separate processes against a local HTTP fixture, cap
races, key changes, unknown billing, fencing and lost-response history recovery.
The optional 30-sample benchmark reports synthetic p50/p95, unchanged bytes and
avoided POSTs. It is not provider latency, acoustic QA or invoice evidence.
Batch discounts and token prompt caching are separate, unimplemented features.
Live quality/cost testing needs a newly approved aggregate amount; never reuse a
historical per-call preview allowance as that authority.
