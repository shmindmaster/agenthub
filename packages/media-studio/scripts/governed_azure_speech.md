# Bounded Azure Speech jobs

`governed_azure_speech.py` uses an immutable, exact-request owner authorization
and the shared SQLite speech ledger. A new Azure job has a $1 ceiling in integer
microdollars. The quote conservatively charges all escaped SSML UTF-8 bytes at
the configured Neural HD rate; it is a reservation, not a verified invoice.
The rate expires and fails closed. No credentials are written to artifacts.

Use `generate(..., use_sdk=True)` with the native Azure Speech SDK. Preflight
the SDK import and required format/property before submitting a job. One SDK
operation returns a synthesis result ID, which is durably bound before the
application reads audio bytes. There is no application retry, redirect,
provider fallback, playback or audio output device. SDK internal retry behavior
is not established. An SDK result ID identifies synthesis, not billing.

Word-boundary events are retained only when the provider emits them and their
result IDs match the synthesis. Empty events mean alignment was not performed;
they must not be replaced with estimated word timing. Generated audio remains
pending substantive pronunciation, identity and listening QA.

An ambiguous submission retains its entire reservation and fences its exact
request key. `generate_manual_retake` supports only two explicitly authorized,
immutable, parent-linked manual replacements in the original ledger. Both
original unknown rows stay fenced and charged against the same ceiling. This
does not enable automatic retry, a new budget, or resetting historical usage.

Pronunciation: `pronunciations=[names]` on `quote` and `generate` wraps whole-word, case-sensitive
matches in `<phoneme alphabet="ipa">` using the repo-owned `pronunciation_lexicon.json` (standard voices
only, 1 to 16 distinct allowlisted names, fail closed on a hostile or missing entry). The pinned revision and
IPA enter the request, so the cache key and cost change only when it is used; existing keys stay identical.

Offline tests: `python -m unittest test_governed_azure_speech test_governed_deepgram test_pronunciation_lexicon test_check_name_pronunciation test_check_script_terms`.

An explicitly authorized bounded standard-neural job uses the separate
`azure-speech-bounded-standard-job` grant, exact cache keys, and a ceiling no
greater than 150,000 microdollars. It cannot mutate or reset an existing job.
This does not enlarge the older $1 grant or its supplemental authority.
Supported standard voices/styles are Jenny/friendly, Guy/friendly, and
Aria/narration-professional. Structured delivery accepts only exact-content
paragraph strings, escaped before wrapping in safe paragraph/sentence,
bookmark, break, and prosody markup. Rate is bounded to -10..0 percent and
interparagraph pauses to 250..700 milliseconds. No caller-supplied XML is used.

SDK bookmark events are retained beside the word events. A production consumer
must check complete lexical coverage, monotonically bounded offsets and all
expected paragraph bookmarks before using the actual audio clock. Caption
timing remains bound to the exact WAV hash; ASR timestamps are not forced
alignment. A valid clock does not establish warmth, pacing or listening QA.

SDK/config preflight now runs before a request is claimed. A missing dependency
therefore creates no unknown reservation. Legacy missing-SDK failures may use
`recover_pre_network_sdk_import(original_manifest, recovery_manifest, workspace,
planned)` after an independent review of the exact failed call. This is an
offline recovery, not generation or a general unknown-submission retry.

The coordinator-authored recovery manifest records kind
`azure-speech-pre-network-sdk-import-recovery-v1`, exact authorization
`Recover exact request proven never sent`, workspace, cache key, original
authorization and diagnostic SHA-256, review evidence, hash-bound original
Python/script/adapter paths, canonical Python realpath, and `sdk_call_line`.
The adapter proves the historical SDK transport imported the missing module
first, proves that call site selected `use_sdk=True`, and reproduces the missing
SDK with networking disabled in the original interpreter. Receipts, response
evidence, actual usage, changed inputs and ambiguous failures remain fenced.

Recovery preserves the original failed diagnostic and an immutable recovery
audit, keeps the same request key and maximum reservation, and changes only that
never-sent unknown row to an expired prepared row. Generation then uses the same
original immutable manifest and cache key with a working SDK interpreter. A
second recovery is refused, including after a later network failure. Do not
change revisions, reset accounting or infer recovery eligibility from the error
class alone.
