# Personal policy fragment

Copy this file into `overlays/personal/policy-fragment.md` and replace the
placeholders. It is not part of the public core. When an overlay is present,
compile your personal rules into the deployment policy your hosts actually
read (this repository uses `global-agent-policy.md` for that).

## Local rules

- Keep credentials out of git. Registry entries name environment variables,
  never values.
- Put machine-specific roots in `agenthub.profile.json` (gitignored), not in
  tracked templates.
- Add private capability ids to `overlay.json` only when this machine should
  load them.
