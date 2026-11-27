# Hosting provider routing

MahumTech AWS is the default for all new hosting, business or personal. Railway is
the secondary option. Deploy to the product's existing provider until an authorized
cutover is verified. Docwise stays on Railway. Keep client resources separate and
reuse authorized capacity and credits before adding recurring cost.

Temporary validation compute and persistent product hosting are separate decisions.
Follow the operator's compute policy for bounded validation; a sandbox is not a
production deployment. Confirm the exact source revision, persistent data and domain
routing before claiming a hosting cutover.

## Execution capacity

Prefer suitable existing remote capacity for heavy builds, integration and E2E
tests, browser capture and media processing. Keep lightweight orchestration and
necessary device or signed-in profile access local. Inspect competing workloads,
free resources, warm caches, startup time, network/tool compatibility, evidence
export and authorized cost limits before selecting a worker. Reuse existing
capacity before provisioning; a particular provider is not automatically faster
or cheaper.

Use disposable isolated environments. Split a long recording or render into
units that survive losing one box, and pull each result back as it finishes. Pin the source commit,
configuration and synthetic fixture manifest; isolate writable files, databases
and test resources. Export and verify required artifacts and logs before cleaning
up task-created compute. These execution preferences do not expand spending or
production-release authority.
