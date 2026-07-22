# Autonomy Profiles

## interactive

Ordinary read-only work and proposed edits are allowed. Confirmation is required before destructive changes, external messages, installs, credential changes, pushes, merges, deployments, or production access.

## repo-autonomous

The agent may edit, install repository dependencies, test, commit, push, and update an existing pull request inside the assigned repository or worktree. It may not modify unrelated machine configuration, merge, deploy, rotate credentials, or communicate externally beyond the assigned repository workflow unless explicitly authorized.

## machine-maintenance

The agent may inspect and reconcile machine-wide agent installations and configuration only when the user explicitly requests maintenance. Exact targets must be verified before deletion. Credentials and runtime state remain unmanaged. Cleanup is report-only by default.

Host-native permission settings are mappings of these profiles. Labels such as `yolo`, `bypassPermissions`, `always-approve`, or disabled sandboxing are implementation details and must not silently broaden the selected profile.
