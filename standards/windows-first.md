# Windows-First Standard

- Prefer one authoritative Windows installation and one authoritative configuration home per agent surface.
- Keep a WSL installation only for a documented Linux-only capability, an intentionally Linux-executed project, or a verified technical advantage unavailable on Windows.
- The intended distribution set is `Ubuntu` plus Docker Desktop's managed `docker-desktop` distribution.
- Never modify Docker Desktop's managed WSL data directly.
- Before removing a WSL agent copy, verify that unique skills, sessions, configuration, credentials, databases, and workflows have been migrated or intentionally discarded.
- Record Windows and intentional WSL installations separately in `registry/installations.json`.
