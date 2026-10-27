# Shared content controls

The Media Studio owner supplies `packages/media-studio/scripts/content_runtime.py`.
The ElevenLabs owner supplies `packages/elevenlabs/scripts/elevenlabs_cli.py` and
its mandatory TTS adapter. Resolve these paths from `AGENTHUB_ROOT` or the
canonical AgentHub checkout; never copy a helper into a product repository.
Python 3.11+ and the standard library are sufficient. No daemon or scheduler runs.

## Scope and fail-closed routes

| Route | Enforcement |
| --- | --- |
| Canonical ElevenLabs REST speech, sound effects (`sfx`) and music (`music`) on this OS account/disk | Required exact cache, singleflight, shared reservations and durable recovery |
| Canonical Deepgram Flux Sienna REST TTS through `scripts/deepgram_cli.py` | Exact cache, shared microdollar reservations, receipt-first persistence; ambiguous submissions fenced with no automatic recovery/retry |
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

The default OS runtime location may itself be relocated through a junction. In
that case the runtime resolves the canonical local destination only if the
original `ledger.sqlite3` and complete 32-byte `namespace-salt` already exist
together there. A partial relocation fails before creating state or submitting
content. Restore the original accounting directory as a unit; do not create a
replacement salt or configure an empty ledger to bypass missing history.
Explicit caller-supplied directories continue to reject linked ancestors.

When the original accounting cannot be recovered, paid speech remains blocked
unless the owner explicitly authorizes a new, bounded accounting epoch. The
canonical TTS `--recovery-epoch-manifest` route records historical accounting as
`UNKNOWN` and historical requests as `FENCED`; it never recreates lifetime
headroom. Its immutable private JSON authorization requires `epoch_id`,
`maximum_credits` (at most 1000), `owner_authorization`, `workspace`, and an
`allowed_text_sha256` list of at most 20 demonstrably new or never-submitted
sentences. Include any known ambiguous text hashes in `ambiguous_text_sha256`;
they are refused even if allowlisted. Historical ambiguous work cannot be
reclassified as new through this route. This explicit operator attestation is
not automated proof of the completeness of historical evidence.

The epoch lives in the same canonical local runtime under
`content-recovery-epochs/<epoch_id>`, has its own aggregate reservation ceiling,
and locks the exact authorization bytes against later cap/allowlist changes.
Only Flash v2.5 TTS is supported. Every new submission requires live remaining
allowance and live confirmation that overages are disabled. Normal exact-cache,
singleflight, unknown-response fencing and receipt requirements remain active.
The epoch does not claim an account-wide or restored historical billing ceiling.

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
fail closed. The one exception is HTTP 429 (rate or concurrency limit): the provider
refused before generating, so the worker releases its own submission
(`Ledger.reject`) and the exact request may be retried later. Recover the exact provider history item (GET only):

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
requires content, pronunciation, listening and artifact checks. Speaker identity
is advisory only (owner direction 2026-10-27: identity is advisory only; never fail,
block or re-voice on speaker similarity): an `identity` entry may be supplied for
information, is never required and is never verified. Supply a private JSON object
keyed by the required gate names. Each gate must include:

```json
{"pass":true,"output_sha256":"<exact-audio-sha256>","evidence_path":"<absolute-private-report-path>","evidence_sha256":"<report-sha256>","reviewer":"<identified-human-or-QA-tool>"}
```

```powershell
python $Control accept --namespace <saved-namespace> --cache-key <saved-key> --manifest <private-gates.json>
```

The command verifies actual evidence file hashes, output hashes and all required
passes. Reviewers remain responsible for substantive QA; this records evidence,
it does not compute listening quality itself. Assembly still
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

## Governed Deepgram Sienna

Run `scripts/deepgram_cli.py` from this canonical package. It quotes by default without credentials, network, or ledger creation. Supply `--text-file`, `--workspace`, `--revision`, `--dictionary-revision` and the exact approved `--expressivity`. Only `--execute` with distinct absent `--output`/`--receipt` files can submit. Model is fixed to `flux-sienna-en`, REST `/v2/speak`, mono linear16 WAV 48kHz, with data-improvement opt-out. No voice fallback, STT, generic provider proxy, redirects or automatic retry.

Current conservative price policy reserves 45 integer microdollars per UTF-8 input byte in `deepgram/usd-micros`, across participating namespaces. This bounds the published PAYG rate of $0.045 per 1,000 characters without claiming invoice settlement or assuming discounts. Policy expires 2026-11-24; recheck official https://deepgram.com/pricing before updating it. Quotes exclude retakes and taxes. Budget authorization is separate from narrator approval. No budget row means paid use is disabled. The intact primary ledger and 32-byte namespace salt must already exist; the adapter never initializes missing primary accounting.

If historical accounting is unavailable, a new epoch requires an explicit owner-approved aggregate ceiling, at most 3,000,000 microdollars ($3), and `--recovery-epoch-manifest`. It is never an inferred reset. Manifest fields: `epoch_id` (deepgram-prefixed), `maximum_usd_micros`, `owner_authorization` (actual owner direction), `workspace`, `price_policy`, `historical_accounting: UNKNOWN`, `historical_requests: FENCED`, `allowed_requests` containing exact `text_sha256`/`cache_key` pairs, and `inventory_proof` with absolute `path`/`sha256`. The external proof has `kind: deepgram-new-input-inventory`, `enumerated_scopes`, and complete `historical_rendered_text_sha256`, `ambiguous_rendered_text_sha256`, `new_rendered_text_sha256` lists. Only new rendered inputs disjoint from cached and ambiguous history qualify. Enumeration quality requires independent evidence review; a manifest is not provider proof of non-submission. No historical take may be repurchased through this route.

Authorization is immutable at the canonical OS-local runtime's `content-recovery-epochs/<epoch_id>`. A stable epoch namespace prevents changing credentials from repurchasing an allowed request. Missing/incomplete existing epoch accounting fails closed. No additional-batch or ceiling-extension command is supplied. Interrupted initialization requires inspection/restoration, never a fresh empty retry. This is cooperating-process coordination, not tamper-proof enforcement against the OS user. Keep manifests and private inventories outside this public repository.

Receipt IDs are durably bound before audio reads. Completed responses are quarantined privately with their original hash, byte count and safe failure stage before validation. Only the evidenced 44-byte mono 16-bit 48 kHz PCM streaming header with RIFF size `0x7fff0024` and data size `0x7fff0000` is finalized from the complete response length; PCM bytes remain unchanged, and receipts bind raw and finalized hashes. Ordinary truncated or malformed WAVs remain rejected. Valid finalized WAV bytes become pending assets, subject to all five acceptance gates.

All ambiguous failures, including 429, retain the maximum reservation and fence repurchase. No verified Deepgram history-recovery route is implemented. Response evidence assists diagnosis; it does not authorize resubmission or fabricate provider billing verification. Do not use an unverified billing header to release funds. Exact pending/accepted cache reuse is allowed; five hash-bound acceptance gates still control selection. No raw API path is represented as governed.
