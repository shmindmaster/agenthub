# Governance

AgentHub is an Apache-2.0 public project maintained by Sarosh Hussain. Technical direction is currently maintainer-led. The repository does not claim a broader maintainer council or independent adoption that does not yet exist.

## Decision process

- Public bugs and proposals are discussed in GitHub issues or pull requests.
- Changes are evaluated against the host-neutral registry contract, the public/private overlay boundary, and the validate-audit-apply lifecycle.
- New capabilities reuse the owner recorded in `registry/capabilities.json`; they do not duplicate an existing owner or invent an undocumented host package format.
- Material architecture decisions are recorded in the implementing issue or pull request and reflected in the relevant public documentation.

## Contribution and review

Contributors follow [CONTRIBUTING.md](CONTRIBUTING.md). Pull requests must identify the affected host surfaces, public/private data boundary, validation performed, and any unsupported or degraded outcome.

The maintainer may decline work that embeds personal paths or identity in the public core, imports private overlays by default, expands credentials into generated configuration, creates a second path-binding implementation, or presents unchecked host support as parity.

## Security and private data

Vulnerabilities and accidental exposure risks use the private process in [SECURITY.md](SECURITY.md). Credentials, authentication state, customer data, personal overlay contents, and private capability packages are never acceptable public issue attachments.

## Releases and funding

Releases must come from a validated public tree and preserve Apache-2.0 licensing. Funding may support portability, interoperability, maintenance, documentation, and public validation, but does not buy private control of the project or a favorable result. Material grants, restrictions, overlapping funded work, and delivery updates will be disclosed in the relevant public issue or project update. Requested, awarded, received, and spent funds remain distinct states.

## Evolution

If independent contributors begin sustaining host adapters or shared policy modules, governance can expand through a public proposal naming responsibilities, review authority, and removal criteria. Until then, this document describes the current single-maintainer structure.
