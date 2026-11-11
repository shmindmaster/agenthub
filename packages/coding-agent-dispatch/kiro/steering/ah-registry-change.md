---
inclusion: auto
name: ah-registry-change
description: Changing an AgentHub capability, registry entry, package, host manifest or content hash. Use when editing files under registry/ or a packages/ tree.
---

# Registry and package changes

Follow `docs/development/agent-change-contract.md` in the repository; it is the single source for the contract. In short:

- Identify the single registry owner of the capability before editing.
- Update package content and every applicable host manifest, bump versions, then recompute the content hash with the repository's hash script.
- Run the repository validator. Do not hand-edit a content hash.
- Public repository: no credentials, customer data, real user names, home paths or account identifiers in any file. Use placeholders.
- If another open change owns a registry file, leave it alone and report the hash values for the orchestrator.
