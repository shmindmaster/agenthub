# Native attachment verification

The verification phrase is ORCHID-RIVER-7429.

This synthetic file exists only to test Open WebUI native attachment extraction, embedding, retrieval, and answer generation. It contains no private or client information.

## What this fixture is for

It is a needle-in-a-haystack check for the **attachment** path only, which
`SKILL.md` deliberately separates from persistent corpus retrieval. Upload this
file to an Open WebUI chat, ask for the verification phrase, and a correct
stack answers `ORCHID-RIVER-7429` from the attachment.

That distinction is the whole point of the check. A pass proves the chat
attachment path extracted, embedded, retrieved, and answered. It proves nothing
about the Qdrant index or alias contract, which is a separate route through
`reindex` — so this fixture must never be used as evidence of corpus retrieval
acceptance, and must never be added to a persistent knowledge root.

The phrase is arbitrary and synthetic. It is chosen to be absent from every
real corpus, so a "pass" cannot come from anywhere but this file. If the phrase
ever appears in indexed material, replace it here — a needle that exists in the
haystack silently turns this check into one that cannot fail.
