# Shared content controls

Owner request: make exact caching, in-flight deduplication and aggregate spend
limits executable across agents, and measure cost, quality and latency effects.

The existing MediaStudio owner owns the reusable, on-demand SQLite ledger. The
ElevenLabs owner integrates its REST TTS adapter and disables unmetered STT. Agents on the same
machine and OS account share one default runtime directory; this is not a
network broker or an interception mechanism for native connectors.

Implementation sequence:

1. Inventory tracked public packages, ignored personal overlay executable files,
   MCP/native registrations and actual adapter call sites.
2. Add process-level synthetic tests, then implement transactional reservations,
   exact keys, durable submission states, conservative crash recovery and accepted
   asset reuse. No reset schedule, daemon or automatic budget configuration.
3. Make the governed CLI mandatory for paid REST TTS, disable unsupported paid
   routes and block the Codex native ElevenLabs connector using its documented
   app setting. Unknown billing retains
   the reservation, ambiguous submission never retries automatically.
4. Test concurrency, isolation, invalidation, gates, recovery and latency. Preserve
   provider/model/settings and distinguish synthetic avoided calls from invoices.
5. Review, bump affected packages, hash, validate, commit, merge, push, deploy and
   independently audit. Record bypass paths and any outstanding monetary policy.

Paid verification remains disabled pending explicit owner selection of an
aggregate budget. A historical per-call preview limit is not that approval.

Acceptance requires exact byte hashes, unchanged applicable quality gates,
independent subprocess races and conservative handling of lost responses. A
submitted request can outlive its worker. Only a provider receipt can release
the unused portion of its reservation; elapsed time cannot establish zero cost.

Implemented scope: cooperating processes sharing one OS account/local disk,
transactional ceiling reservations, exact bytes and gate state, fenced prepared
leases, durable request IDs before response-body reads, exact history recovery,
and credential/workspace namespaces. Synthetic process tests exercise real local
HTTP requests, competing purchases and lost responses. Benchmark groups contain
30 samples each with alternating baseline/governed pair order.

Open gates: new aggregate live budget, live acoustic/latency/invoice verification,
fresh-chat native tool removal, other hosts' connector denial and credential
isolation/shared service for remote agents. Raw SDK/shell/provider UI purchases
are not intercepted. This local release does not fulfill universal all-agent
provider spend enforcement. See the package content-controls reference for the
route matrix and operational commands. No automatic scheduler or reset is added.
