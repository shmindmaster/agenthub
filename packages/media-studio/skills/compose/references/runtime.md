# Runtime repair

The runtime check in SKILL.md throws `Stale runtime: <manifest>` when the deployed briefing kit or shared tools differ from the expected version.

To repair, set `MEDIA_STUDIO_PACKAGE_ROOT` to a package whose `plugin.json` version equals the version checked above, then run `pwsh -NoProfile -File "$env:MEDIA_STUDIO_PACKAGE_ROOT/scripts/Sync-MediaStudioKit.ps1"`. With no package source, ask for an AgentHub deploy instead of guessing.
