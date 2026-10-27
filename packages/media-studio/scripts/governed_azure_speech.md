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

Offline tests: `python -m unittest test_governed_azure_speech test_governed_deepgram`.
